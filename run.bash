#!/usr/bin/env bash
set -Eexo pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"
[[ -n "${1}" ]] || (echo "Must provide VM name as ARG1" && exit 1)
SOURCE_TEMPLATE_NAME="${1}"
PIPELINE_PARALLEL_VM_COUNT="${PIPELINE_PARALLEL_VM_COUNT:-"1"}"
PIPELINE_VM_CPU="${PIPELINE_VM_CPU:-"6"}"
PIPELINE_VM_RAM="${PIPELINE_VM_RAM:-"14G"}"
REPORT_FILE_NAME="report.yml"
ANKA_VERSION="$(anka -j version | jq -r '.body.version').$(anka -j version | jq -r '.body.build')"
rm -f ${REPORT_FILE_NAME}

if [[ "$(uname)" == "Darwin" ]]; then
    [[ "$(arch)" == i386 ]] && ARCH="amd64" || ARCH=$(arch)
else
  ARCH="amd64"
fi
printf "modify-types:\n" >>${REPORT_FILE_NAME}
for MODIFY_FILE in $(find ./host-phase-vm-prep/${ARCH} -type f -depth 1 | grep -v "/all"); do
  MODIFY_FILE_NAME="$(echo ${MODIFY_FILE} | rev | cut -d/ -f1 | rev)"
  printf "  - modify-type: ${MODIFY_FILE_NAME}\n" >>${REPORT_FILE_NAME}
  printf "    tests:\n" >>${REPORT_FILE_NAME}
  for TEST in $(ls | grep ".bash" | grep -v "run.bash"); do
    [[ -n "${TEST_NAME}" && ! "${TEST}" =~ "${TEST_NAME}" ]] && continue || true
    for ((index=1; index <= PIPELINE_PARALLEL_VM_COUNT; index++)); do
      (
        # Run specific prep script for specific versions
        echo "] HOST PHASE VM PREP"
        ./host-phase-vm-prep/${ARCH}/all
        if [[ -f "./host-phase-vm-prep/version-specific/${ARCH}/${ANKA_VERSION}" ]]; then
          ./host-phase-vm-prep/version-specific/${ARCH}/${ANKA_VERSION}
        fi

        VM_NAME="test${index}"
        rm -f ${VM_NAME}-${REPORT_FILE_NAME}
        anka delete --yes $VM_NAME || true
        anka clone "${SOURCE_TEMPLATE_NAME}" $VM_NAME

        # Modify VM for CPU/RAM/etc
        if [[ $(anka --machine-readable show $VM_NAME  | jq -r ".body.cpu_cores") != ${PIPELINE_VM_CPU} ]]; then
          anka stop $VM_NAME --force
          anka modify $VM_NAME set cpu ${PIPELINE_VM_CPU}
        fi
        if [[ $(anka --machine-readable show $VM_NAME  | jq -r ".body.ram") != ${PIPELINE_VM_RAM} ]]; then
          anka stop $VM_NAME --force
          anka modify $VM_NAME set ram ${PIPELINE_VM_RAM}
        fi
        "${MODIFY_FILE}" "${VM_NAME}" # modify-type
          
        echo "] INNER VM PRE TEST PREP"
        anka cp ./inner-vm-pre-test-prep/all $VM_NAME:
        anka run $VM_NAME bash -c "./all"
        if [[ -f ./inner-vm-pre-test-prep/${MACOS_VERSION} ]]; then
          anka cp ./inner-vm-pre-test-prep/${MACOS_VERSION} $VM_NAME:
          anka run $VM_NAME bash -c "./${MACOS_VERSION}"
        fi

        echo "] TEST ${TEST}"
        printf "      - vm_name: ${VM_NAME}\n" >>${VM_NAME}-${REPORT_FILE_NAME}
        printf "        total_vms: ${PIPELINE_PARALLEL_VM_COUNT}\n" >>${VM_NAME}-${REPORT_FILE_NAME}
        printf "        script: ${TEST}\n" >>${VM_NAME}-${REPORT_FILE_NAME}
        printf "        cpu: ${PIPELINE_VM_CPU}\n" >>${VM_NAME}-${REPORT_FILE_NAME}
        printf "        ram: ${PIPELINE_VM_RAM}\n" >>${VM_NAME}-${REPORT_FILE_NAME}
        echo ""
        anka cp ./${TEST} $VM_NAME:
        # Run prep steps in script
        : > log$VM_NAME # empty log file
        anka run $VM_NAME bash -c "GIT_SSL_NO_VERIFY=true ./${TEST} prep"
        { { {
          anka run $VM_NAME bash -c "time GIT_SSL_NO_VERIFY=true ./${TEST} build 2>&1"
        } 3>&- | tee -a log$VM_NAME >&3 3>&-
          exit ${PIPESTATUS}
        } 2>&1 | tee -a log$VM_NAME >&2 3>&-
        } 3>&1 && (
          echo "        runtime: $(tail -4 log${VM_NAME} | grep real | awk "{ print \$2 }" | xargs)" >>${VM_NAME}-${REPORT_FILE_NAME} \
          || echo "        runtime: $(tail -8 log$VM_NAME | tr "\n" " ")" >>${VM_NAME}-${REPORT_FILE_NAME}
        )
        anka delete --yes $VM_NAME || true
      ) &
    done
    wait
    for ((index=1; index <= PIPELINE_PARALLEL_VM_COUNT; index++)); do
      VM_NAME="test${index}"
      [[ -f "${VM_NAME}-${REPORT_FILE_NAME}" ]] && cat ${VM_NAME}-${REPORT_FILE_NAME} >> ${REPORT_FILE_NAME}
    done
  done
done