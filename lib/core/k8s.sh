# Provide utilities for operating with kubectl.
${__BENCHMARK_SOURCE_LIB_CORE_K8S_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_CORE_K8S_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

#######################################
# Utility function for running the kubectl command.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Arguments for running kubectl.
# Returns
#   Code that kubectl returns.
#######################################
function k8s::kubectl() {
  local extra_args=()
  [[ -n "${BENCHMARK_NAMESPACE}" ]] && extra_args+=(-n "${BENCHMARK_NAMESPACE}")
  kubectl "${extra_args[@]}" "$@"
}

#######################################
# Utility function for running the kubectl get command on a specified object. This wrapper hides the output
# from STDERR when kubectl fails.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Resource kind, e.g., pod
#   Resource name, e.g., web-pod-13je7
#   Other kubectl arguments.
# Output
#   STDOUT when succeeds.
# Returns
#   0 if the object exists, 255 if not, error code returned by kubectl otherwise.
#   254 will be returned when the original exit code is 255 to avoid conflict.
#######################################
function k8s::kubectl::get() {
  (($# >= 2)) || { echo >&2 "not enough arguments" && return 1; }
  [[ -n "$1" ]] || { echo >&2 "resource kind must be provided" && return 1; }
  [[ -n "$2" ]] || { echo >&2 "resource name must be provided" && return 1; }

  if common::run_and_capture_outputs k8s::kubectl get "$@"; then
    echo "${CAPTURED_STDOUT}"
    return 0
  else
    [[ "${CAPTURED_STDERR}" == *"not found"* ]] && return 255
    ((CAPTURED_EXIT_CODE == 255)) && return 254
    return "${CAPTURED_EXIT_CODE}"
  fi
}

#######################################
# Utility function for checking if the object exists.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Resource kind, e.g., pod
#   Resource name, e.g., web-pod-13je7.
# Returns
#   0 if the object exists, 255 if not, error code returned by kubectl otherwise.
#######################################
function k8s::kubectl::object_exists() {
  k8s::kubectl::get "$1" "$2" >/dev/null
}

#######################################
# Utility function for checking if a Job is completed.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Job name.
# Returns
#   0 if it is, 1 if not, 255 if the Job object doesn't exists, and other codes when kubectl fails.
#######################################
function k8s::job::is_completed() {
  local complete_status
  local exit_code=0
  complete_status=$(k8s::kubectl::get job "$1" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}') || exit_code=$?

  ((exit_code == 0)) || return "${exit_code}"

  [[ "${complete_status,,}" == "true" ]] || return 1
}

#######################################
# Utility function for checking if a Job is failed.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Job name.
# Returns
#   0 if it is, 1 if not, 255 if the Job object doesn't exists, and other codes when kubectl fails.
#######################################
function k8s::job::is_failed() {
  local failed_status
  local exit_code=0

  failed_status=$(k8s::kubectl::get job "$1" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}') || exit_code=$?

  ((exit_code == 0)) || return "${exit_code}"

  [[ "${failed_status,,}" == "true" ]] || return 1
}

K8S_JOB_COMPLETED=""
K8S_JOB_FAILED=""

#######################################
# Utility function for checking if a Job is completed or failed.
# Globals
#   BENCHMARK_NAMESPACE
#   K8S_JOB_COMPLETED
#   K8S_JOB_FAILED
# Arguments
#   Job name.
# Returns
#   0 if it is, 1 if not, 255 if the object doesn't exists, and other codes when kubectl fails.
#######################################
function k8s::job::is_completed_or_failed() {
  local complete_and_failed_status
  local exit_code=0

  complete_and_failed_status=$(k8s::kubectl::get job "$1" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status},{.status.conditions[?(@.type=="Failed")].status},') || exit_code=$?

  ((exit_code == 0)) || return "${exit_code}"

  # Load output into the array.
  local -a array
  IFS="," read -r -a array <<<"${complete_and_failed_status}"

  local complete_status="${array[0]}"
  local failed_status="${array[1]}"

  # Set the global vars.
  K8S_JOB_COMPLETED=false
  K8S_JOB_FAILED=false

  if [[ "${complete_status,,}" == "true" ]]; then
    K8S_JOB_COMPLETED=true
  fi

  if [[ "${failed_status,,}" == "true" ]]; then
    K8S_JOB_FAILED=true
  fi

  [[ "${K8S_JOB_COMPLETED}" == "true" || "${K8S_JOB_FAILED}" == "true" ]] || return 1
}

#######################################
# Utility function for waiting until a Job complete or fail.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_WAIT_RETRY_LIMIT
#   BENCHMARK_JOB_WAIT_RETRY_INTERVAL
#   K8S_JOB_COMPLETED
#   K8S_JOB_FAILED
# Arguments
#   Job name.
# Returns
#   0 if it completes or fails, 255 if the object doesn't exist, 1 when timeout, and other codes when kubectl fails.
#######################################
function k8s::job::wait_before_completed_or_failed() {
  (($# == 1)) || { echo >&2 "not enough arguments" && return 1; }

  local retry_count=0
  local retry_limit=${BENCHMARK_JOB_WAIT_RETRY_LIMIT:=60}
  local retry_interval=${BENCHMARK_JOB_WAIT_RETRY_INTERVAL:=5}

  local exit_code=0
  while ((retry_count < retry_limit)); do
    ((retry_count != 0)) && sleep "${retry_interval}"

    k8s::job::is_completed_or_failed "$1"
    exit_code=$?

    # Condition met, return.
    ((exit_code == 0)) && return 0

    # Condition unmet, retry.
    if ((exit_code == 1)); then
      retry_count=$((retry_count + 1))
      continue
    fi

    # On other errors, just return the exit code.
    return "${exit_code}"
  done

  logging::debug "Timeout waiting for Job $1 to complete or fail!"
  return 1
}

#######################################
# Utility function for getting debug info for a Job.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Job name.
# Outputs
#   STDOUT
# Returns
#   0 on success, 255 if the Job object doesn't exists, and other codes when kubectl fails.
#######################################
function k8s::job::debug() {
  local job=$1

  local manifest
  manifest=$(k8s::kubectl::get job "${job}" -o yaml)

  printf "Job manifest in YAML:\n%s\n" "${manifest}"
  printf "Pods controlled by Job %s:\n%s\n" "${job}" "$(k8s::kubectl::get pod -l job-name="${job}")"
}

#######################################
# Utility function for checking if the specified RisingWave is rolled out.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   RisingWave name
# Returns
#   0 if it is, 1 if not, 255 if the object doesn't exists, and other codes when kubectl fails.
#######################################
function k8s::risingwave::is_rolled_out() {
  local content
  content=$(k8s::kubectl::get risingwave "$1" -o jsonpath='{.metadata.generation},{.status.observedGeneration},{.status.conditions[?(@.type=="Running")].status},{.status.conditions[?(@.type=="Upgrading")].status},')

  # Load output into the array.
  local -a generation_and_conditions
  IFS="," read -r -a generation_and_conditions <<<"${content}"

  local current_generation="${generation_and_conditions[0]}"
  local observed_generation="${generation_and_conditions[1]}"
  local running_condition="${generation_and_conditions[2]}"
  local upgrading_condition="${generation_and_conditions[3]}"

  if ((current_generation == observed_generation)) &&
    [[ "${running_condition}" == "True" && ("${upgrading_condition}" == "" || "${upgrading_condition}" == "False") ]]; then
    return 0
  else
    return 1
  fi
}

#######################################
# Utility function for waiting before the specified RisingWave is rolled out.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_RISINGWAVE_WAIT_RETRY_LIMIT
#   BENCHMARK_RISINGWAVE_WAIT_RETRY_INTERVAL
# Arguments
#   RisingWave name
# Returns
#   0 if it is, 1 if not, 255 if the object doesn't exists, and other codes when kubectl fails.
#######################################
function k8s::risingwave::wait_before_rollout() {
  (($# == 1)) || { echo >&2 "not enough arguments" && return 1; }

  local retry_count=0
  local retry_limit=${BENCHMARK_RISINGWAVE_WAIT_RETRY_LIMIT:=60}
  local retry_interval=${BENCHMARK_RISINGWAVE_WAIT_RETRY_INTERVAL:=5}

  local exit_code=0
  while ((retry_count < retry_limit)); do
    ((retry_count != 0)) && sleep "${retry_interval}"

    k8s::risingwave::is_rolled_out "$1"
    exit_code=$?

    # Condition met, return.
    ((exit_code == 0)) && return 0

    # Condition unmet, retry.
    if ((exit_code == 1)); then
      retry_count=$((retry_count + 1))
      continue
    fi

    # On other errors, just return the exit code.
    return "${exit_code}"
  done

  logging::debug "Timeout waiting for RisingWave $1 to rollout!"
  return 1
}

#######################################
# Utility function for getting debug info for a RisingWave.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   RisingWave name.
# Outputs
#   STDOUT
# Returns
#   0 on success, 255 if the RisingWave object doesn't exists, and other codes when kubectl fails.
#######################################
function k8s::risingwave::debug() {
  local risingwave=$1

  local manifest
  manifest=$(k8s::kubectl::get risingwave "${risingwave}" -o yaml)

  printf "RisingWave manifest in YAML:\n%s\n" "${manifest}"
  printf "Pods controlled by RisingWave %s:\n%s\n" "${risingwave}" "$(k8s::kubectl::get pod -l risingwave/name="${risingwave}")"
}
