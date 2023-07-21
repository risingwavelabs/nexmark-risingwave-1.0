# Provide utilities for loading environments from file.
${__BENCHMARK_SOURCE_LIB_CORE_ENV_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_CORE_ENV_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

# Update PATH to include the local tomlenv directory.
PATH=${PWD}/tomlenv/bin:${PATH}

#######################################
# Load environment variables from the specified toml files by using tomlenv.
# Globals
#   None
# Arguments
#   List of file names.
# Returns
#   0 when load succeeds, non-zero when error happens.
#######################################
function env::load_from_toml_files() {
  (($# >= 1)) || { echo >&2 "not enough arguments" && return 1; }

  if common::run_and_capture_outputs tomlenv "$@"; then
    local export_vars
    # This awk command from Chatgpt!
    export_vars=$(echo "${CAPTURED_STDOUT}" | awk -F= '{ print "export " $1 "=" "${"$1":-\""substr($0,index($0,"=")+1)"\"}" }')
    logging::debugf "Environment variables:\n%s\n" "${export_vars}"
    eval "${export_vars}"
  else
    logging::errorf "Load environment variables from files failed!\n%s\n" "${CAPTURED_STDERR}"
    return 1
  fi
}

#######################################
# Generate a rendered manifest file with the environment variables.
# Notes
#   Environment variables should be loaded with `env::load_from_toml_files` before invoking this function.
# Globals
#   All exported ones.
# Arguments
#   Manifest file name.
# Outputs
#   STDOUT
# Returns
#   0 when succeeds, non-zero when error happens.
#######################################
function env::generate_rendered_manifest() {
  (($# == 1)) || { echo >&2 "not enough arguments" && return 1; }

  if ! [[ -f "$1" ]]; then
    logging::error "$1 isn't a regular file!"
    return 1
  fi

  envsubst <"$1"
}
