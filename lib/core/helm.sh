# Provide utilities for operating helm.
${__BENCHMARK_SOURCE_LIB_CORE_HELM_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_CORE_HELM_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

#######################################
# Utility function for running the helm command.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Arguments for running helm.
# Returns
#   Code that helm returns.
#######################################
function helm::helm() {
  local extra_args=()
  [[ -n "${BENCHMARK_NAMESPACE}" ]] && extra_args+=(--namespace "${BENCHMARK_NAMESPACE}")
  helm "${extra_args[@]}" "$@"
}

#######################################
# Utility function for checking if a helm release is deployed.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Release name.
# Returns
#   0 if it is, non-zero otherwise.
#######################################
function helm::release::is_deployed() {
  helm::helm list --deployed -q | grep -w -q "$1"
}

#######################################
# Utility function for checking if a helm release exists, no matter the status.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Release name.
# Returns
#   0 if it is, non-zero otherwise.
#######################################
function helm::release::exists() {
  helm::helm list -q | grep -w -q "$1"
}

#######################################
# Utility function for checking if a helm repo exists.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   Repo name.
# Returns
#   0 if it is, non-zero otherwise.
#######################################
function helm::repo::exists() {
  helm::helm repo list 2>/dev/null | awk 'NR>1 {print $1}' | grep -w -q "$1"
}