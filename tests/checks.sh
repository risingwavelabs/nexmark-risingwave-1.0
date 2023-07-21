#!/usr/bin/env bash

shopt -s globstar
set -euo pipefail

SCRIPT_PATH=${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
ROOT_PATH=${SCRIPT_DIR}/..
TOMLENV_PATH=${ROOT_PATH}/tomlenv
MANIFESTS_DIR=${ROOT_PATH}/manifests
BINARY_PATH=${SCRIPT_DIR}/bin
A8M_ENVSUBST_BIN=${BINARY_PATH}/envsubst
ENV_FILE=${ROOT_PATH}/env.toml

source "${ROOT_PATH}/lib/core/env.sh"

function tests::env::ensure_binary_path() {
  if [[ ! -d "${BINARY_PATH}" ]]; then
    mkdir -p "${BINARY_PATH}" >/dev/null
  fi
}

function tests::env::install_a8m_envsubst() {
  if [[ ! -f "${A8M_ENVSUBST_BIN}" ]]; then
    logging::info "a8m/envsubst not found, installing..."
    curl -L https://github.com/a8m/envsubst/releases/download/v1.2.0/envsubst-"$(uname -s)"-"$(uname -m)" -o "${A8M_ENVSUBST_BIN}" 2>/dev/null
    chmod +x "${A8M_ENVSUBST_BIN}"
    logging::info "Installed!"
  fi
}

function tests::env::load_toml_env() {
  local ENV_FILES=("${ENV_FILE}")
  env::load_from_toml_files "${ENV_FILES[@]}"
}

function tests::env::initialize() {
  tests::env::ensure_binary_path
  tests::env::install_a8m_envsubst
  tests::env::load_toml_env
}

function tests::task::run_checks_on_all_yaml_templates_and_report_env_not_found() {
  local fail_cnt=0
  local cur_cnt=1
  logging::info "Check environment variables for template YAML files under manifests..."

  set +e
  local template_files=("${MANIFESTS_DIR}"/**/*.template.yaml)
  local error_msg
  for f in "${template_files[@]}"; do
    if error_msg=$(${A8M_ENVSUBST_BIN} -no-unset <"$f" 2>&1 >/dev/null); then
      printf "[%d/%d] %s $(color::ansi::green "PASS")\n" "${cur_cnt}" "${#template_files[@]}" "${f#"${ROOT_PATH}/"}"
    else
      ((fail_cnt++))
      printf "[%d/%d] %s $(color::ansi::red "FAIL")\n" "${cur_cnt}" "${#template_files[@]}" "${f#"${ROOT_PATH}/"}"
      echo "${error_msg%"\n"}"
    fi
    ((cur_cnt++))
  done

  set -e
  if [[ ${fail_cnt} -gt 0 ]]; then
    logging::error "Failed!"
    return 1
  fi

  logging::info "All files passed the check!"
}

tests::env::initialize || exit 1

# Run tests
tests::task::run_checks_on_all_yaml_templates_and_report_env_not_found
