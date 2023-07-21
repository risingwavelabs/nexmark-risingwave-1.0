# Provide utilities for background job control.
${__BENCHMARK_SOURCE_LIB_CORE_JOB_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_CORE_JOB_SH__=true

#######################################
# Run the command in the background.
# Globals
#   BACKGROUND_PIDS
# Arguments
#   Variable sized strings
# Outputs
#   Depends on the command that executes
# Returns
#   0
#######################################
function job::spawn() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(background command)

  if [[ "${BENCHMARK_TRACE_COMMAND}" == "true" ]]; then
    logging::debug "$*"
  fi

  # shellcheck disable=SC2294
  eval "$@" &

  local pid=$!
  # shellcheck disable=SC2034
  BACKGROUND_PIDS["${pid}"]="$*"

  if [[ "${BENCHMARK_TRACE_COMMAND}" == "true" ]]; then
    logging::debug "$*, pid: ${pid}"
  fi
}

#######################################
# Wait for the background jobs to complete one by one. If any of the background jobs returns non-zero code,
# the function breaks and returns with that code.
# Globals
#   BACKGROUND_PIDS
# Arguments
#   None
# Outputs
#   None
# Returns
#   0 if all succeeds, the first non-zero exit code otherwise.
#######################################
function job::wait() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(background command)

  local cmd
  local exit_code=0

  for pid in "${!BACKGROUND_PIDS[@]}"; do
    cmd=${BACKGROUND_PIDS[${pid}]}
    exit_code=0
    wait "${pid}" || exit_code=$?

    if [[ "${BENCHMARK_TRACE_COMMAND}" == "true" ]]; then
      logging::debug "${cmd[*]}, pid: ${pid}, exit code: ${exit_code}"
    fi

    ((exit_code == 0)) || return "${exit_code}"
  done
}

#######################################
# Wait for all the background jobs to complete. It returns the last non-zero code it met or 0.
# Globals
#   BACKGROUND_PIDS
# Arguments
#   None
# Outputs
#   None
# Returns
#   0 if all succeeds, the last non-zero exit code otherwise.
#######################################
function job::wait_all() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(background command)

  local cmd
  local return_code=0
  local exit_code=0

  for pid in "${!BACKGROUND_PIDS[@]}"; do
    cmd=${BACKGROUND_PIDS[${pid}]}

    exit_code=0
    wait "${pid}" || exit_code=$?
    ((exit_code==0)) || return_code=${exit_code}

    if [[ "${BENCHMARK_TRACE_COMMAND}" == "true" ]]; then
      logging::debug "${cmd[*]}, pid: ${pid}, exit code: ${exit_code}"
    fi
  done

  return "${return_code}"
}
