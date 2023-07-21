# Benchmark runtime functions.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_RUNTIME_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_RUNTIME_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/../core/lib.sh"

#######################################
# Function to help check if the script is running inside a console Pod.
# Globals
#   BENCHMARK_CONSOLE
# Arguments
#   Console type, either docker or k8s, optional.
# Returns
#   0 if true, 1 otherwise.
#######################################
function benchmark::runtime::is_console() {
  if (($# == 0)); then
    [[ "${BENCHMARK_CONSOLE}" != "" ]]
  else
    [[ "${BENCHMARK_CONSOLE}" == "$1" ]]
  fi
}

#######################################
# Get the current script path.
# Globals
#   BASH_SOURCE
# Arguments
#   None
# Outputs
#   STDOUT
# Returns
#   0
#######################################
function benchmark::runtime::script_path() {
  echo "${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}"
}

#######################################
# Get the path relative to the current script path.
# Globals
#   BASH_SOURCE
# Arguments
#   Sub path.
# Outputs
#   STDOUT
# Returns
#   0
#######################################
function benchmark::runtime::path() {
  echo "${BENCHMARK_BASE}/$1"
}

#######################################
# Get the current work dir.
# Globals
#   BENCHMARK_WORKDIR
#   BASH_SOURCE
# Arguments
#   None
# Outputs
#   STDOUT
# Returns
#   0
#######################################
function benchmark::runtime::workdir() {
  echo "${BENCHMARK_WORKDIR:=$(dirname "$(benchmark::runtime::script_path)")}"
}

#######################################
# Get the path relative to the session dir (under the work dir).
# Globals
#   BASH_SOURCE
# Arguments
#   Sub path.
# Outputs
#   STDOUT
# Returns
#   0
#######################################
function benchmark::runtime::session_path() {
  echo "$(benchmark::runtime::workdir)/.session/$1"
}
