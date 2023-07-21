# Provide utilities for common usages, such as executing commands.
${__BENCHMARK_SOURCE_LIB_CORE_COMMON_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_CORE_COMMON_SH__=true

#######################################
# Utility function for running commands with a debug log and verbose control.
# Globals
#   BENCHMARK_TRACE_COMMAND
#   BENCHMARK_SHOW_COMMAND_OUTPUT
# Arguments
#   Command to run and arguments.
# Returns
#   Code returns from the command.
#######################################
function common::run() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(command)

  if [[ "${BENCHMARK_TRACE_COMMAND}" == "true" ]]; then
    logging::debug "$*"
  fi

  local exit_code=0

  {
    if [[ ${BENCHMARK_SHOW_COMMAND_OUTPUT:=true} == "true" ]]; then
      # shellcheck disable=SC2294
      eval "$@"
    else
      # shellcheck disable=SC2294
      eval "$@" >/dev/null 2>&1
    fi
  } || exit_code=$?

  if [[ "${BENCHMARK_TRACE_COMMAND}" == "true" ]]; then
    logging::debug "$*, exit code: ${exit_code}"
  fi

  return ${exit_code}
}

# Global variables used for capturing stdout and stderr of command run by `common::run_and_capture_outputs`.
CAPTURED_STDOUT=""
CAPTURED_STDERR=""
CAPTURED_EXIT_CODE=0

#######################################
# Utility function for running commands and capture its stdout and stderr separately.
# The solution comes from the following answer on the stackoverflow:
# https://stackoverflow.com/questions/11027679/capture-stdout-and-stderr-into-different-variables
# Note
#   To use this function concurrently in jobs, please make sure to wrap it in a subshell so that
#   the variables won't conflict with each other.
# Globals
#   CAPTURED_STDOUT
#   CAPTURED_STDERR
#   CAPTURED_EXIT_CODE
# Arguments
#   Command to run and arguments.
# Returns
#   Code returns from the command.
#######################################
function common::run_and_capture_outputs() {
  # shellcheck disable=SC2034
  {
    IFS=$'\n' read -r -d '' CAPTURED_STDERR
    IFS=$'\n' read -r -d '' CAPTURED_STDOUT
    IFS=$'\n' read -r -d '' CAPTURED_EXIT_CODE
  } < <((printf '\0%s\0%d\0' "$("$@")" "${?}" 1>&2) 2>&1)

  return "${CAPTURED_EXIT_CODE}"
}

#######################################
# Utility function for checking if command exists.
# Globals
#   PATH, optional
# Arguments
#   Command name
# Returns
#   0 if exists, non-zero if not.
#######################################
function common::command_exists() {
  (($# == 1)) || { echo >&2 "not enough arguments" && return 1; }
  [[ -n "$1" ]] || { echo >&2 "command name must be provided" && return 1; }

  command -v "$1" >/dev/null 2>&1
}
