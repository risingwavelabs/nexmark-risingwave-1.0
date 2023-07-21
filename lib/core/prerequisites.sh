# Define prerequisites and provide utilities for verifying the prerequisites.
${__BENCHMARK_SOURCE_LIB_CORE_PREREQUISITES_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_CORE_PREREQUISITES_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

#######################################
# Utility function for checking the existence of the command list given.
# Globals
#   PATH, optional
# Arguments
#   Variable sized strings.
# Returns
#   0 if succeeds, non-zero otherwise.
#######################################
function prerequisites::check_commands_existence() {
  for command in "$@"; do
    if ! common::command_exists "${command}"; then
      logging::error "Command ${command} not found!"
      return 1
    fi
  done
}

#######################################
# Utility function for checking the existence of the command list given,
# and will try installation if the command is not found.
# Globals
#   PATH, optional
# Arguments
#   Variable sized strings.
# Returns
#   0 if succeeds, non-zero otherwise.
#######################################
function prerequisites::check_commands_existence_and_try_install() {
  local os
  os=$(uname -s)
  case "${os}" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) os="" ;;
  esac

  for command in "$@"; do
    if ! common::command_exists "${command}"; then
      local install_func="prerequisites::install::${os}::${command}"
      if [[ $(type -t "${install_func}") == function ]]; then
        logging::info "Command ${command} not found, try installing..."
        if ${install_func}; then
          logging::info "Command ${command} installed!"
        else
          logging::error "Command ${command} installation failed!"
          return 1
        fi
      else
        logging::error "Command ${command} not found!"
        return 1
      fi
    fi
  done
}

# List of commands required by the benchmark script.
readonly -a _BENCHMARK_REQUIRED_COMMANDS=(
  awk
  kubectl
  helm
  envsubst
  aws
  tomlenv
  jq
)

#######################################
# Utility function for running checks on prerequisites for the benchmark script, including
#   * Existence of the required commands
# Globals
#   PATH, optional
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero otherwise.
#######################################
function prerequisites::benchmark::run() {
  prerequisites::check_commands_existence_and_try_install "${_BENCHMARK_REQUIRED_COMMANDS[@]}"
}

# List of commands required by the console script.
readonly -a _CONSOLE_REQUIRED_COMMANDS=(
  awk
  kubectl
  envsubst
  tomlenv
)

#######################################
# Utility function for running checks on prerequisites for the console script, including
#   * Existence of the required commands
# Globals
#   PATH, optional
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero otherwise.
#######################################
function prerequisites::console::run() {
  prerequisites::check_commands_existence_and_try_install "${_CONSOLE_REQUIRED_COMMANDS[@]}"
}

# Installation functions below.

function prerequisites::install::macos::with_brew() {
  prerequisites::check_commands_existence brew
  brew install "$1"
}

function prerequisites::install::macos::awk() {
  : # Expect a built-in awk
}

function prerequisites::install::macos::envsubst() {
  prerequisites::install::macos::with_brew gettext
}

function prerequisites::install::macos::kubectl() {
  prerequisites::install::macos::with_brew kubectl
}

function prerequisites::install::macos::helm() {
  prerequisites::install::macos::with_brew helm
}

function prerequisites::install::macos::aws() {
  prerequisites::install::macos::with_brew awscli
}

function prerequisites::install::macos::tomlenv() {
  logging::error "Please download it from the https://github.com/risingwavelabs/kube-bench/releases and make sure it is in the \$PATH"
  return 1
}

function prerequisites::install::macos::psql() {
  prerequisites::install::macos::with_brew postgresql
}

function prerequisites::install::linux::awk() {
  : # Expect a built-in awk
}

function prerequisites::install::linux::envsubst() {
  if common::command_exists apt; then
    apt -y install gettext
  elif common::command_exists yum; then
    yum -y install gettext
  elif common::command_exists dnf; then
    dnf -y install gettext
  else
    logging::error "Failed to recognize the Linux distribution. Please try install it yourself!"
  fi
}

function prerequisites::install::linux::kubectl() {
  if common::command_exists apt; then
    apt -y install kubectl
  elif common::command_exists yum; then
    yum -y install kubectl
  elif common::command_exists dnf; then
    dnf -y install kubectl
  else
    logging::error "Failed to recognize the Linux distribution. Please try install it yourself!"
  fi
}

function prerequisites::install::linux::helm() {
  prerequisites::check_commands_existence curl
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

function prerequisites::install::linux::aws() {
  if common::command_exists apt; then
    apt -y install awscli
  elif common::command_exists yum; then
    yum -y install awscli
  elif common::command_exists dnf; then
    dnf -y install awscli
  else
    logging::error "Failed to recognize the Linux distribution. Please try install it yourself!"
  fi
}

function prerequisites::install::linux::tomlenv() {
  logging::error "Please download it from the https://github.com/risingwavelabs/kube-bench/releases and make sure it is in the \$PATH"
  return 1
}

function prerequisites::install::linux::psql() {
  if common::command_exists apt; then
    apt -y install postgresql-client
  elif common::command_exists yum; then
    yum -y install postgresql
  elif common::command_exists dnf; then
    dnf -y install postgresql
  else
    logging::error "Failed to recognize the Linux distribution. Please try install it yourself!"
  fi
}
