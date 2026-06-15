#!/usr/bin/env bash

shopt -s globstar
set -euo pipefail

SCRIPT_PATH=${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}
SCRIPT_DIR=$(dirname "${SCRIPT_PATH}")
ROOT_PATH=${SCRIPT_DIR}/..
MANIFESTS_DIR=${ROOT_PATH}/manifests
BINARY_PATH=${SCRIPT_DIR}/bin
A8M_ENVSUBST_BIN=${BINARY_PATH}/envsubst
ENV_FILE=${ROOT_PATH}/env.toml
SMOKE_CONFIG_FILES=(
  "${ROOT_PATH}/benchmarks/risingwave/benchmark.toml"
  "${ROOT_PATH}/benchmarks/flink/benchmark.toml"
)

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
  export BENCHMARK_BASE="${ROOT_PATH}"
  source "${ROOT_PATH}/lib/benchmark/env.sh"
  benchmark::env::overrides
}

function tests::task::tracked_template_files() {
  if command -v git >/dev/null 2>&1 && git -C "${ROOT_PATH}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${ROOT_PATH}" ls-files --cached --others --exclude-standard -- "manifests/**/*.template.yaml"
  else
    find "${MANIFESTS_DIR}" -name "*.template.yaml" -type f | sed "s#^${ROOT_PATH}/##"
  fi
}

function tests::task::run_checks_on_all_yaml_templates_and_report_env_not_found() {
  local fail_cnt=0
  local cur_cnt=1
  logging::info "Check environment variables for template YAML files under manifests..."

  set +e
  local template_files=()
  while IFS= read -r template_file; do
    template_files+=("${ROOT_PATH}/${template_file}")
  done < <(tests::task::tracked_template_files)

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

function tests::task::run_config_smoke() {
  local config_file
  for config_file in "${SMOKE_CONFIG_FILES[@]}"; do
    logging::info "Smoke test config ${config_file#"${ROOT_PATH}/"}..."

    (
      set -euo pipefail

      while IFS= read -r env_name; do
        unset "${env_name}"
      done < <(env | awk -F= '/^(BENCHMARK|TRICK)_/ {print $1}')

      export BENCHMARK_BASE="${ROOT_PATH}"
      export PATH="${ROOT_PATH}/tomlenv/bin:${PATH}"
      source "${ROOT_PATH}/lib/benchmark/env.sh"

      env::load_from_toml_files "${ENV_FILE}" "${config_file}"
      benchmark::env::overrides

      local render_dir
      render_dir=$(mktemp -d)
      trap 'rm -rf "${render_dir}"' EXIT

      "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/kafka/values.template.yaml" >"${render_dir}/kafka-values.yaml"

      grep -q "repository: bitnamilegacy/kafka" "${render_dir}/kafka-values.yaml"
      grep -q "protocol: PLAINTEXT" "${render_dir}/kafka-values.yaml"
      if grep -q "SASL" "${render_dir}/kafka-values.yaml"; then
        exit 1
      fi

      case "${BENCHMARK_SYSTEM}" in
      risingwave)
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/risingwave/risingwave.template.yaml" >"${render_dir}/risingwave.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/benchmarks/nexmark-kafka/prepare.template.yaml" >"${render_dir}/prepare.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/benchmarks/nexmark-kafka/start.template.yaml" >"${render_dir}/start.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/benchmarks/nexmark-kafka/clean.template.yaml" >"${render_dir}/clean.yaml"

        grep -q "benchmark-risingwave" "${render_dir}/risingwave.yaml"
        grep -q '"postgresql":' "${render_dir}/risingwave.yaml"
        grep -q '"minio":' "${render_dir}/risingwave.yaml"
        grep -q '"bucket":"hummock"' "${render_dir}/risingwave.yaml"
        grep -q "name: default" "${render_dir}/risingwave.yaml"
        grep -q "connector:" "${render_dir}/risingwave.yaml"

        BENCHMARK_PODS_DISTRIBUTION_NODE_SELECTORS="node-group:benchmark"
        benchmark::env::overrides
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/risingwave/risingwave.template.yaml" >"${render_dir}/risingwave-affinity.yaml"
        grep -q '"benchmark/pod-affinity":"metastore"' "${render_dir}/risingwave-affinity.yaml"

        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/minio/values.template.yaml" >"${render_dir}/minio-values.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/postgresql/metastore.template.yaml" >"${render_dir}/postgresql-values.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/risingwave/secrets/minio-credentials.template.yaml" >"${render_dir}/minio-secret.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/risingwave/secrets/metastore-postgresql-credentials.template.yaml" >"${render_dir}/postgresql-secret.yaml"
        grep -q "repository: bitnamilegacy/minio" "${render_dir}/minio-values.yaml"
        grep -q "repository: bitnamilegacy/postgresql" "${render_dir}/postgresql-values.yaml"
        ;;
      flink)
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/flink/flink-session.template.yaml" >"${render_dir}/flink.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/benchmarks/flink-nexmark-kafka/prepare.template.yaml" >"${render_dir}/prepare.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/benchmarks/flink-nexmark-kafka/start.template.yaml" >"${render_dir}/start.yaml"
        "${A8M_ENVSUBST_BIN}" -no-unset <"${ROOT_PATH}/manifests/benchmarks/flink-nexmark-kafka/clean.template.yaml" >"${render_dir}/clean.yaml"

        grep -q "benchmark-flink" "${render_dir}/flink.yaml"
        grep -q "state.checkpoints.dir: s3://flink/checkpoints" "${render_dir}/flink.yaml"
        ;;
      *)
        logging::error "Invalid smoke system: ${BENCHMARK_SYSTEM}"
        exit 1
        ;;
      esac
    )

    logging::info "Config smoke test passed!"
  done
}

tests::env::initialize || exit 1

# Run tests
tests::task::run_checks_on_all_yaml_templates_and_report_env_not_found
tests::task::run_config_smoke
