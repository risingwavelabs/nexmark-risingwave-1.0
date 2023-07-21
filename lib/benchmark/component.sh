# Benchmark components functions.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_COMPONENT_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_COMPONENT_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/../core/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/runtime.sh"

#######################################
# Test if etcd is enabled.
# Globals
#   None
# Arguments
#   None
# Returns
#   0
#######################################
function benchmark::component::etcd::enabled() {
  return 0
}

#######################################
# If etcd is enabled, start the etcd component and wait before it's running.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_ETCD_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::etcd::start() {
  benchmark::component::etcd::enabled || return 0

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(component "etcd: ${BENCHMARK_ETCD_NAME}")

  logging::info "Starting..."

  if ! helm::release::is_deployed "${BENCHMARK_ETCD_NAME}"; then
    local template_path
    template_path=$(benchmark::runtime::path manifests/etcd/values.template.yaml)

    if ! common::run "env::generate_rendered_manifest ${template_path} | helm::helm upgrade --install --wait ${BENCHMARK_ETCD_NAME} -f - bitnami/etcd"; then
      logging::error "Failed!"
      return 1
    fi
  fi

  logging::info "Started!"
}

#######################################
# If etcd is enabled, stop the etcd component and delete all the persistent volumes.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_ETCD_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::etcd::stop() {
  benchmark::component::etcd::enabled || return 0

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(component "etcd: ${BENCHMARK_ETCD_NAME}")

  logging::info "Stopping..."

  if helm::release::exists "${BENCHMARK_ETCD_NAME}"; then
    common::run helm::helm uninstall "${BENCHMARK_ETCD_NAME}"
  fi
  common::run k8s::kubectl delete pvc -l app.kubernetes.io/instance="${BENCHMARK_ETCD_NAME}"

  logging::info "Stopped!"
}

#######################################
# Test if kafka is enabled.
# Globals
#   BENCHMARK_KAFKA_ENABLED
# Arguments
#   None
# Returns
#   0 for true, 1 for false
#######################################
function benchmark::component::kafka::enabled() {
  [[ "${BENCHMARK_KAFKA_ENABLED}" == "true" ]]
}

#######################################
# Test if kafka keep pod is enabled.
# Globals
#   BENCHMARK_KAFKA_KEEP_POD_ENABLED
# Arguments
#   None
# Returns
#   0 for true, 1 for false
#######################################
function benchmark::component::kafka::keep_pod_enabled() {
  [[ "${BENCHMARK_KAFKA_KEEP_POD_ENABLED}" == "true" ]]
}

#######################################
# If kafka is enabled, start the kafka component and wait before it's running.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_KAFKA_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::kafka::start() {
  benchmark::component::kafka::enabled || return 0

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(component "kafka: ${BENCHMARK_KAFKA_NAME}")

  logging::info "Starting..."

  if ! helm::release::is_deployed "${BENCHMARK_KAFKA_NAME}"; then
    local template_path
    template_path=$(benchmark::runtime::path manifests/kafka/values.template.yaml)

    if ! common::run "env::generate_rendered_manifest ${template_path} | helm::helm upgrade --install --wait ${BENCHMARK_KAFKA_NAME} -f -  bitnami/kafka"; then
      logging::error "Failed!"
      return 1
    fi
  fi

  logging::info "Started!"
}

#######################################
# If kafka is enabled, stop the kafka component and delete all the persistent volumes.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_KAFKA_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::kafka::stop() {
  benchmark::component::kafka::enabled || return 0

  benchmark::component::kafka::keep_pod_enabled && return 0

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(component "kafka: ${BENCHMARK_KAFKA_NAME}")

  logging::info "Stopping..."

  if helm::release::exists "${BENCHMARK_KAFKA_NAME}"; then
    common::run helm::helm uninstall "${BENCHMARK_KAFKA_NAME}"
  fi
  common::run k8s::kubectl delete pvc -l app.kubernetes.io/instance="${BENCHMARK_KAFKA_NAME}"

  logging::info "Stopped!"
}

#######################################
# Create a ConfigMap in Kubernetes as the template of the RisingWave config.
#
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_RISINGWAVE_NAME
#   RISINGWAVE_CONFIG_TEMPLATE_FILE
#   BENCHMARK_RISINGWAVE_STORAGE_S3_DATA_DIRECTORY
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::risingwave::create_config_template_configmap() {
  local config_template_file=${RISINGWAVE_CONFIG_TEMPLATE_FILE:-"$(benchmark::runtime::path manifests/risingwave/config/risingwave.toml)"}

  if ! [[ -f "${config_template_file}" ]]; then
    logging::errorf "RisingWave config template file isn't a regular file! Path: %s" "${config_template_file}"
    return 1
  fi

  local session_config_file
  session_config_file=$(benchmark::runtime::session_path risingwave/risingwave.toml)

  # Generate configmap file to session dir.
  mkdir -p "$(dirname "${session_config_file}")" && env::generate_rendered_manifest "${config_template_file}" >"${session_config_file}"

  # Create configmap YAML with kubectl and apply it.
  local configmap_name=${BENCHMARK_RISINGWAVE_NAME}-config-template
  common::run "k8s::kubectl create configmap ${configmap_name} --from-file=${session_config_file} --dry-run=client -o yaml | k8s::kubectl apply -f -"
}

#######################################
# Delete the template ConfigMap from Kubernetes.
#
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_RISINGWAVE_NAME
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::risingwave::delete_config_template_configmap() {
  local configmap_name=${BENCHMARK_RISINGWAVE_NAME}-config-template

  common::run k8s::kubectl delete cm "${configmap_name}" --ignore-not-found=true
}

#######################################
# Get the path to the manifest file according to the storage type.
#
# Globals
#   BENCHMARK_RISINGWAVE_NAME
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
# Arguments
#   None
# Outputs
#   STDOUT, for the path of the manifest file
#   STDERR, for error logs
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::risingwave::manifest_file() {
  benchmark::runtime::path manifests/risingwave/risingwave.template.yaml
}

#######################################
# Create or update the Secrets to store the credentials if necessary.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_RISINGWAVE_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::risingwave::create_credentials_secrets() {
  # shellcheck disable=SC2155
  if [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "s3" ]]; then
    local path=$(benchmark::runtime::path manifests/risingwave/secrets/s3-credentials.template.yaml)
    common::run "env::generate_rendered_manifest ${path} | k8s::kubectl apply -f -"
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "s3c" ]]; then
    local path=$(benchmark::runtime::path manifests/risingwave/secrets/s3c-credentials.template.yaml)
    common::run "env::generate_rendered_manifest ${path} | k8s::kubectl apply -f -"
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "minio" ]]; then
    local path=$(benchmark::runtime::path manifests/risingwave/secrets/minio-credentials.template.yaml)
    common::run "env::generate_rendered_manifest ${path} | k8s::kubectl apply -f -"
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "gcs" ]]; then
    local path=$(benchmark::runtime::path manifests/risingwave/secrets/gcs-credentials.template.yaml)
    common::run "env::generate_rendered_manifest ${path} | k8s::kubectl apply -f -"
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "azureblob" ]]; then
    local path=$(benchmark::runtime::path manifests/risingwave/secrets/azureblob-credentials.template.yaml)
    common::run "env::generate_rendered_manifest ${path} | k8s::kubectl apply -f -"
  fi
}

#######################################
# Delete the Secrets to store the credentials if necessary.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_RISINGWAVE_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::risingwave::clean_credentials_secrets() {
  if [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "s3" ]]; then
    common::run k8s::kubectl delete secret "${BENCHMARK_RISINGWAVE_NAME}-s3-credentials" --ignore-not-found=true
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "s3c" ]]; then
    common::run k8s::kubectl delete secret "${BENCHMARK_RISINGWAVE_NAME}-${BENCHMARK_RISINGWAVE_STORAGE_S3C_VENDOR}-credentials" --ignore-not-found=true
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "minio" ]]; then
    common::run k8s::kubectl delete secret "${BENCHMARK_RISINGWAVE_NAME}-minio-credentials" --ignore-not-found=true
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "gcs" ]]; then
    common::run k8s::kubectl delete secret "${BENCHMARK_RISINGWAVE_NAME}-gcs-credentials" --ignore-not-found=true
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "azureblob" ]]; then
    common::run k8s::kubectl delete secret "${BENCHMARK_RISINGWAVE_NAME}-azureblob-credentials" --ignore-not-found=true
  fi
}

#######################################
# Start or update the RisingWave and wait before it is fully rolled out.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_RISINGWAVE_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::risingwave::start() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(component "risingwave: ${BENCHMARK_RISINGWAVE_NAME}")

  logging::info "Starting..."

  # Setup the ConfigMap and Secret.
  benchmark::component::risingwave::create_config_template_configmap
  benchmark::component::risingwave::create_credentials_secrets

  local manifest_file
  manifest_file=$(benchmark::component::risingwave::manifest_file)

  # Generate manifest and apply it.
  common::run "env::generate_rendered_manifest ${manifest_file} | k8s::kubectl apply -f -"

  # Wait until the RisingWave is rolled out. Print debug info when fails.
  if ! k8s::risingwave::wait_before_rollout "${BENCHMARK_RISINGWAVE_NAME}"; then
    logging::errorf "Failed! Debug info:\n%s\n" "$(k8s::risingwave::debug "${BENCHMARK_RISINGWAVE_NAME}")"
    return 1
  fi

  logging::info "Started!"
}

#######################################
# Stop the RisingWave by deleting the object. This function will not wait before Pods are deleted.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_RISINGWAVE_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::risingwave::stop() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(component "risingwave: ${BENCHMARK_RISINGWAVE_NAME}")

  logging::info "Stopping..."

  local manifest_file
  manifest_file=$(benchmark::component::risingwave::manifest_file)

  common::run "env::generate_rendered_manifest ${manifest_file} | k8s::kubectl delete -f - --ignore-not-found=true"

  common::run k8s::kubectl delete pvc -l risingwave/name="${BENCHMARK_RISINGWAVE_NAME}"

  benchmark::component::risingwave::delete_config_template_configmap
  benchmark::component::risingwave::clean_credentials_secrets

  logging::info "Stopped!"
}

#######################################
# Test if benchmark system is flink.
# Globals
#   BENCHMARK_FLINK_ENABLED
# Arguments
#   None
# Returns
#   0 for true, 1 for false
#######################################
function benchmark::component::flink::enabled() {
  [[ "${BENCHMARK_FLINK_ENABLED}" == "true" ]]
}

#######################################
# Start or update the Flink and wait before it is fully rolled out.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_FLINK_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::flink::start() {
  benchmark::component::flink::enabled || return 0

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(component "flink: ${BENCHMARK_FLINK_NAME}")

  logging::info "Starting..."

  local manifest_file
  manifest_file=$(benchmark::runtime::path manifests/flink/flink-session.template.yaml)

  # Generate manifest and apply it.
  common::run "env::generate_rendered_manifest ${manifest_file} | k8s::kubectl apply -f -"

  local exit_code=0
  k8s::kubectl rollout status deploy flink-jobmanager flink-taskmanager --watch || exit_code=$?

  # Condition unmet, Print debug info when fails.
  if ((exit_code != 0)); then
    logging::errorf "Failed! Debug info:\n%s\n" "$(k8s::kubectl::get deploy flink-jobmanager flink-taskmanager -o yaml)"
    return "${exit_code}"
  fi

  logging::info "Started!"
}

#######################################
# Stop the Flink by deleting the object. This function will not wait before Pods are deleted.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_FLINK_*
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::component::flink::stop() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(component "flink: ${BENCHMARK_FLINK_NAME}")

  logging::info "Stopping..."

  local manifest_file
  manifest_file=$(benchmark::runtime::path manifests/flink/flink-session.template.yaml)

  common::run "env::generate_rendered_manifest ${manifest_file} | k8s::kubectl delete -f - --ignore-not-found=true"

  logging::info "Stopped!"
}
