#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "${SCRIPT_DIR}"
if [[ -z "${1:-}" ]]; then
  echo "Pass the template name as argument 1" >&2
  exit 1
fi
SOURCE_TEMPLATE_NAME="$1"
PIPELINE_PARALLEL_VM_COUNT="${PIPELINE_PARALLEL_VM_COUNT:-1}"
PIPELINE_VM_CPU="${PIPELINE_VM_CPU:-6}"
PIPELINE_VM_RAM="${PIPELINE_VM_RAM:-14G}"
REPORT_FILE_NAME="report.yml"
TEST_NAME="${TEST_NAME:-}"
VM_TIMEOUT_SECONDS=3600
VM_ATTEMPTS=3

if [[ "${PIPELINE_VM_RAM}" == *GB* ]]; then
  echo "Use G for PIPELINE_VM_RAM. Example: 14G" >&2
  exit 1
fi
if [[ ! "${PIPELINE_PARALLEL_VM_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "PIPELINE_PARALLEL_VM_COUNT must be a positive integer" >&2
  exit 1
fi

anka_version_json="$(anka -j version)"
ANKA_VERSION="$(printf '%s\n' "${anka_version_json}" | jq -r '"\(.body.version).\(.body.build)"')"
rm -f "${REPORT_FILE_NAME}"

if [[ "$(uname)" == "Darwin" ]]; then
  if [[ "$(arch)" == "i386" ]]; then
    ARCH="amd64"
  else
    ARCH="$(arch)"
  fi
else
  ARCH="amd64"
fi

inner_prep_path() {
  local macos_version="$1"
  local scripts_dir="$2"
  local candidate="${macos_version%%-*}"
  while [[ -n "${candidate}" ]]; do
    if [[ -f "${scripts_dir}/${candidate}" ]]; then
      printf '%s\n' "${scripts_dir}/${candidate}"
      return 0
    fi
    if [[ "${candidate}" != *.* ]]; then
      break
    fi
    candidate="${candidate%.*}"
  done
  return 0
}

apply_cpu_and_ram() {
  local vm_name="$1"
  local vm_info cpu ram
  vm_info="$(anka --machine-readable show "${vm_name}")"
  cpu="$(printf '%s\n' "${vm_info}" | jq -r '.body.cpu_cores')"
  ram="$(printf '%s\n' "${vm_info}" | jq -r '.body.ram')"
  if [[ "${cpu}" == "${PIPELINE_VM_CPU}" && "${ram}" == "${PIPELINE_VM_RAM}" ]]; then
    return 0
  fi
  anka stop "${vm_name}" --force || true
  if [[ "${cpu}" != "${PIPELINE_VM_CPU}" ]]; then
    anka modify "${vm_name}" set cpu "${PIPELINE_VM_CPU}"
  fi
  if [[ "${ram}" != "${PIPELINE_VM_RAM}" ]]; then
    anka modify "${vm_name}" set ram "${PIPELINE_VM_RAM}"
  fi
}

capture_build_runtime() {
  local vm_name="$1"
  local test_file="$2"
  local vm_report="$3"
  local log_file="log${vm_name}"
  local run_status runtime
  : > "${log_file}"
  set +e
  {
    {
      {
        anka run "${vm_name}" bash -c "time GIT_SSL_NO_VERIFY=true ./${test_file} build 2>&1"
      } 3>&- | tee -a "${log_file}" >&3 3>&-
      exit "${PIPESTATUS[0]}"
    } 2>&1 | tee -a "${log_file}" >&2 3>&-
  } 3>&1
  run_status=$?
  set -e
  if (( run_status == 0 )); then
    runtime="$(tail -n 4 "${log_file}" | awk '/^real/ { value=$2 } END { print value }')"
  else
    runtime="$(tail -n 8 "${log_file}" | tr '\n' ' ')"
  fi
  printf '        runtime: %s\n' "${runtime}" >> "${vm_report}"
}

run_one_vm() {
  local index="$1"
  local modify_file="$2"
  local test_file="$3"
  local vm_name="test${index}"
  local vm_report="${vm_name}-${REPORT_FILE_NAME}"
  local version_script="./host-phase-vm-prep/${ARCH}/version-specific/${ANKA_VERSION}"
  local prep_script prep_name
  # Expand the VM name now. The EXIT trap runs after the local variable is gone.
  # shellcheck disable=SC2064
  trap "anka delete --yes $(printf '%q' "${vm_name}") >/dev/null 2>&1 || true" EXIT
  rm -f "${vm_report}"
  anka delete --yes "${vm_name}" || true
  anka clone "${SOURCE_TEMPLATE_NAME}" "${vm_name}"
  apply_cpu_and_ram "${vm_name}"
  if [[ -f "${version_script}" ]]; then
    "${version_script}" "${vm_name}"
  fi
  "${modify_file}" "${vm_name}"

  echo "] INNER VM PRE TEST PREP"
  anka cp ./inner-vm-pre-test-prep/all "${vm_name}:"
  anka run "${vm_name}" bash -c "./all"
  prep_script="$(inner_prep_path "${SOURCE_TEMPLATE_NAME}" ./inner-vm-pre-test-prep)"
  if [[ -n "${prep_script}" ]]; then
    prep_name="$(basename "${prep_script}")"
    anka cp "${prep_script}" "${vm_name}:"
    anka run "${vm_name}" bash -c "./${prep_name}"
  fi

  echo "] TEST ${test_file}"
  printf '      - vm_name: %s\n' "${vm_name}" >> "${vm_report}"
  printf '        total_vms: %s\n' "${PIPELINE_PARALLEL_VM_COUNT}" >> "${vm_report}"
  printf '        script: %s\n' "${test_file}" >> "${vm_report}"
  printf '        cpu: %s\n' "${PIPELINE_VM_CPU}" >> "${vm_report}"
  printf '        ram: %s\n' "${PIPELINE_VM_RAM}" >> "${vm_report}"
  anka cp "./${test_file}" "${vm_name}:"
  anka run "${vm_name}" bash -c "GIT_SSL_NO_VERIFY=true ./${test_file} prep"
  capture_build_runtime "${vm_name}" "${test_file}" "${vm_report}"
}

stop_worker() {
  local pid="$1"
  local pgid=""
  pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ -n "${pgid}" && "${pgid}" == "${pid}" ]]; then
    kill -9 -- "-${pgid}" 2>/dev/null || true
  else
    kill -9 "${pid}" 2>/dev/null || true
  fi
  wait "${pid}" 2>/dev/null || true
}

wait_for_vm_workers() {
  local start_epoch now_epoch pid still_running index
  start_epoch=$(date +%s)
  while true; do
    still_running=0
    for pid in "${WORKER_PIDS[@]}"; do
      if kill -0 "${pid}" 2>/dev/null; then
        still_running=1
        break
      fi
    done
    if (( still_running == 0 )); then
      for pid in "${WORKER_PIDS[@]}"; do
        wait "${pid}" || true
      done
      return 0
    fi
    now_epoch=$(date +%s)
    if (( now_epoch - start_epoch >= VM_TIMEOUT_SECONDS )); then
      echo "timeout reached"
      for pid in "${WORKER_PIDS[@]}"; do
        stop_worker "${pid}"
      done
      for ((index=1; index<=PIPELINE_PARALLEL_VM_COUNT; index++)); do
        anka delete --yes "test${index}" >/dev/null 2>&1 || true
      done
      return 1
    fi
    sleep 10
  done
}

append_vm_reports() {
  local index vm_report
  for ((index=1; index<=PIPELINE_PARALLEL_VM_COUNT; index++)); do
    vm_report="test${index}-${REPORT_FILE_NAME}"
    if [[ -f "${vm_report}" ]]; then
      cat "${vm_report}" >> "${REPORT_FILE_NAME}"
    fi
  done
}

set -m
echo "] HOST PHASE VM PREP"
"./host-phase-vm-prep/${ARCH}/all"
printf 'modify-types:\n' >> "${REPORT_FILE_NAME}"

while IFS= read -r modify_file; do
  [[ -n "${modify_file}" ]] || continue
  modify_name="$(basename "${modify_file}")"
  printf '  - modify-type: %s\n' "${modify_name}" >> "${REPORT_FILE_NAME}"
  printf '    tests:\n' >> "${REPORT_FILE_NAME}"
  while IFS= read -r test_path; do
    [[ -n "${test_path}" ]] || continue
    test_file="$(basename "${test_path}")"
    if [[ -n "${TEST_NAME}" && "${test_file}" != *"${TEST_NAME}"* ]]; then
      continue
    fi
    attempt=1
    while (( attempt <= VM_ATTEMPTS )); do
      WORKER_PIDS=()
      for ((index=1; index<=PIPELINE_PARALLEL_VM_COUNT; index++)); do
        run_one_vm "${index}" "${modify_file}" "${test_file}" &
        WORKER_PIDS+=("$!")
      done
      if wait_for_vm_workers; then
        break
      fi
      if (( attempt < VM_ATTEMPTS )); then
        echo "retry ${attempt} for ${test_file}"
        sleep 5
      fi
      attempt=$((attempt + 1))
    done
    append_vm_reports
  done < <(find . -maxdepth 1 -type f -name '*.bash' ! -name 'run.bash' | sort)
done < <(find "./host-phase-vm-prep/${ARCH}" -maxdepth 1 -type f ! -name all | sort)
