# Benchmark stage definitions.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_STAGE_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_STAGE_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/../core/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/runtime.sh"
source "$(dirname "${BASH_SOURCE[0]}")/component.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

#######################################
# Create the Kubernetes namespace if it doesn't exist.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::stage::init::create_namespace_if_not_exists() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(k8s "namespace: ${BENCHMARK_NAMESPACE}")

  local exit_code=0
  k8s::kubectl::object_exists ns "${BENCHMARK_NAMESPACE}" || exit_code=$?

  if ((exit_code == 255)); then
    local manifest_file
    manifest_file=$(benchmark::runtime::path manifests/namespace/ns.template.yaml)
    common::run "env::generate_rendered_manifest ${manifest_file} | k8s::kubectl apply -f -"
    logging::info "Created!"
  else
    return "${exit_code}"
  fi
}

#######################################
# Add helm repos and update if necessary.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_CLI_HELM_UPDATE
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::stage::init::update_helm_repos() {
  if ! helm::repo::exists bitnami; then
    common::run helm::helm repo add bitnami https://charts.bitnami.com/bitnami
    common::run helm::helm repo add kafka-ui https://provectus.github.io/kafka-ui
    if [[ "${BENCHMARK_CLI_HELM_UPDATE}" == "true" ]]; then
      common::run helm::helm repo update
    fi
  fi
}

#######################################
# Test if the workspace is initialized.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_GHCR_REGISTRY_SECRET
# Arguments
#   None
# Returns
#   0 for true, 1 for false
#######################################
function benchmark::stage::is_initialized() {
  helm::repo::exists bitnami
  k8s::kubectl::object_exists ns "${BENCHMARK_NAMESPACE}"
}

#######################################
# Check the init status of the workspace and report an error if not.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_GHCR_REGISTRY_SECRET
# Arguments
#   None
# Outputs
#   STDERR
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::init::check_status() {
  if ! benchmark::stage::is_initialized; then
    logging::error "Uninitialized!"
    return 1
  fi
}

#######################################
# Initialize the workspace by creating the namespace and the GHCR secret. If the script is not running inside the
# console Pod, it will also automatically update the helm repos.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_GHCR_REGISTRY_SECRET
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::init() {
  benchmark::stage::init::update_helm_repos
  benchmark::stage::init::create_namespace_if_not_exists
}

#######################################
# Run setup for prepare stage, e.g., loading ConfigMaps for the nexmark benchmark.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_TYPE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::prepare::setup() {
  if [[ "${BENCHMARK_JOB_TYPE}" == nexmark* ]]; then
    logging::info "Loading resources for nexmark..."
    local manifest_files
    manifest_files=$(benchmark::runtime::path "manifests/nexmark/*.template.yaml")
    for f in ${manifest_files}; do
      common::run "env::generate_rendered_manifest ${f} | k8s::kubectl apply -f -"
    done
    logging::info "Done!"
  fi

  if [[ "${BENCHMARK_JOB_TYPE}" == "flink-nexmark-kafka" ]]; then
    logging::info "Loading resources for flink..."
    local manifest_files
    manifest_files=$(benchmark::runtime::path "manifests/flink-nexmark/*.template.yaml")
    for f in ${manifest_files}; do
      common::run "env::generate_rendered_manifest ${f} | k8s::kubectl apply -f -"
    done
    logging::info "Done!"
  fi
}

#######################################
# Run the prepare Job and wait before it completes or fails. The function will print the outputs of the
# Job run, but won't delete it afterwards.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_TYPE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::prepare::run_job() {
  local manifest_file
  manifest_file=$(benchmark::runtime::path manifests/benchmarks/"${BENCHMARK_JOB_TYPE}"/prepare.template.yaml)

  if ! [[ -f "${manifest_file}" ]]; then
    logging::error "Not supported!"
    return 1
  fi

  local job_name="${BENCHMARK_JOB_NAME}-prepare"

  # If Job already exists, skip the apply.
  if ! k8s::kubectl::object_exists job "${job_name}"; then
    common::run "env::generate_rendered_manifest ${manifest_file} | k8s::kubectl apply -f -"
  fi

  logging::info "Running..."

  # Wait until Job finishes.
  if k8s::job::wait_before_completed_or_failed "${job_name}"; then
    if [[ "${K8S_JOB_FAILED}" == "true" ]]; then
      logging::errorf "Failed! Logs:\n%s\n" "$(k8s::kubectl logs -l job-name="${job_name}" --tail="${BENCHMARK_LOGGING_TAIL}" --all-containers=true)"
      logging::errorf "$(k8s::kubectl describe job "${job_name}")"
      return 1
    else
      logging::infof "Succeeded! Logs:\n%s\n" "$(k8s::kubectl logs -l job-name="${job_name}" --tail="${BENCHMARK_LOGGING_TAIL}" --all-containers=true)"
      return 0
    fi
  else
    logging::errorf "Job failed to stop! Debug info: \n%s\n" "$(k8s::job::debug "${job_name}")"
    return 1
  fi
}

#######################################
# Run the prepare stage.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_TYPE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::prepare() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=("benchmark: ${BENCHMARK_JOB_TYPE}" "stage: prepare")

  benchmark::stage::prepare::setup
  benchmark::stage::prepare::run_job
}

#######################################
# Test if prepare stage has been run.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::is_prepared() {
  local job_name="${BENCHMARK_JOB_NAME}-prepare"

  k8s::kubectl::object_exists job "${job_name}"
  k8s::job::is_completed "${job_name}"
}

#######################################
# Test if start stage has been run.
# Globals
#   BENCHMARK_NAMESPACE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::is_started() {
  local job_name="${BENCHMARK_JOB_NAME}"
  k8s::kubectl::object_exists job "${job_name}"
}

#######################################
# Start the benchmark run stage, by starting the benchmark run Job and waiting until it is running.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_TYPE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::start() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=("benchmark: ${BENCHMARK_JOB_TYPE}" "stage: run")

  if ! benchmark::stage::is_prepared; then
    logging::error "Not prepared!"
    return 1
  fi

  local manifest_file
  manifest_file=$(benchmark::runtime::path manifests/benchmarks/"${BENCHMARK_JOB_TYPE}"/start.template.yaml)

  if ! [[ -f "${manifest_file}" ]]; then
    logging::error "Not supported!"
    return 1
  fi

  local job_name="${BENCHMARK_JOB_NAME}"

  # If Job already exists, skip the apply.
  logging::info "Starting..."
  if ! k8s::kubectl::object_exists job "${job_name}"; then
    common::run "env::generate_rendered_manifest ${manifest_file} | k8s::kubectl apply -f -"
  fi

  # Wait until the Job starts to run.
  if ! common::run k8s::kubectl wait --timeout=300s --for=condition=Initialized pod -l job-name="${job_name}"; then
    logging::errorf "Job failed to start! Debug info: \n%s\n" "$(k8s::job::debug "${job_name}")"
    return 1
  fi

  logging::infof "Running! Check the logs with:\n    %s\n" "$(benchmark::runtime::script_path) logs -f"
}

#######################################
# Stop the benchmark run, by deleting the Job object and waiting until the Pod is also deleted.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_TYPE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::stop() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=("benchmark: ${BENCHMARK_JOB_TYPE}" "stage: run")

  benchmark::stage::is_started || return 0

  local job_name="${BENCHMARK_JOB_NAME}"

  logging::info "Stopping..."

  if k8s::kubectl::object_exists job "${job_name}"; then
    if ! common::run k8s::kubectl delete job "${job_name}" --cascade=foreground --ignore-not-found=true; then
      logging::error "Failed to stop!"
      return 1
    fi
  fi

  logging::info "Stopped!"
}

#######################################
# Run the clean Job, to delete internal resources like materialized views, tables, sources, Kafka topic, and others.
# It waits before the Job completes or fails and will print the log afterwards.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_TYPE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::clean::run_job() {
  local manifest_file
  manifest_file=$(benchmark::runtime::path manifests/benchmarks/"${BENCHMARK_JOB_TYPE}"/clean.template.yaml)

  if ! [[ -f "${manifest_file}" ]]; then
    logging::error "Not supported!"
    return 1
  fi

  local job_name="${BENCHMARK_JOB_NAME}-clean"

  # If Job already exists, skip the apply.
  if ! k8s::kubectl::object_exists job "${job_name}"; then
    common::run "env::generate_rendered_manifest ${manifest_file} | k8s::kubectl apply -f -"
  fi

  logging::info "Running..."

  # Wait until Job finishes.
  if k8s::job::wait_before_completed_or_failed "${job_name}"; then
    if [[ "${K8S_JOB_FAILED}" == "true" ]]; then
      logging::errorf "Failed! Logs:\n%s\n" "$(k8s::kubectl logs -l job-name="${job_name}" --tail="${BENCHMARK_LOGGING_TAIL}" --all-containers=true)"
      return 1
    else
      logging::infof "Succeeded! Logs:\n%s\n" "$(k8s::kubectl logs -l job-name="${job_name}" --tail="${BENCHMARK_LOGGING_TAIL}" --all-containers=true)"
      return 0
    fi
  else
    logging::errorf "Job failed to stop! Debug info: \n%s\n" "$(k8s::job::debug "${job_name}")"
    return 1
  fi
}

#######################################
# Run teardown for clean stage, e.g., deleting ConfigMaps for the nexmark benchmark.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_TYPE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::clean::teardown() {
  if [[ "${BENCHMARK_JOB_TYPE}" == nexmark* ]]; then
    logging::info "Unloading resources for nexmark..."
    local manifest_files
    manifest_files=$(benchmark::runtime::path "manifests/nexmark/*.yaml")
    for f in ${manifest_files}; do
      common::run "env::generate_rendered_manifest ${f} | k8s::kubectl delete -f - --ignore-not-found=true"
    done
    logging::info "Done!"
  fi
}

#######################################
# Run the clean stage. It will run the following steps in order:
# - Run clean job
# - Stop the benchmark run
# - Delete the clean job
# - Delete the prepare job
# Globals
#   FORCE, true or 1 means force delete all objects no matter the clean Job succeeds or fails.
#   BENCHMARK_NAMESPACE
#   BENCHMARK_JOB_TYPE
# Arguments
#   None
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::clean() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=("benchmark: ${BENCHMARK_JOB_TYPE}" "stage: clean")

  # Try stop first.
  benchmark::stage::stop

  # If there's a prepare Job object, then it means clean hasn't been executed.
  # Run the clean Job and then delete the clean job, and prepare in order.
  local prepare_job_name="${BENCHMARK_JOB_NAME}-prepare"
  if k8s::kubectl::object_exists job "${prepare_job_name}"; then
    # If FORCE is true, then in any cases the Job objects will be deleted!
    if [[ -v "FORCE" && ("${FORCE}" == "true" || "${FORCE}" == "1") ]]; then
      benchmark::stage::clean::run_job || :
    else
      benchmark::stage::clean::run_job
    fi

    local clean_job_name="${BENCHMARK_JOB_NAME}-clean"

    common::run k8s::kubectl delete job "${clean_job_name}" --cascade=foreground --ignore-not-found=true
    common::run k8s::kubectl delete job "${prepare_job_name}" --cascade=foreground --ignore-not-found=true
  fi

  # Teardown resources.
  benchmark::stage::clean::teardown
}

#######################################
# Check the component setup status.
# Globals
#   BENCHMARK_NAMESPACE
#   BENCHMARK_SYSTEM
#   BENCHMARK_RISINGWAVE_NAME
#   BENCHMARK_POSTGRESQL_NAME
# Arguments
#   None
# Outputs
#   STDERR
# Returns
#   0 when succeeds, non-zero on error.
#######################################
function benchmark::stage::setup::check_status() {
  case "${BENCHMARK_SYSTEM}" in
  "risingwave")
    if ! k8s::kubectl::object_exists risingwave "${BENCHMARK_RISINGWAVE_NAME}"; then
      logging::error "RisingWave not found! Set up first!"
      return 1
    fi
    ;;
  "postgresql")
    if ! k8s::kubectl::object_exists statefulset.apps "${BENCHMARK_POSTGRESQL_NAME}"; then
      logging::error "PostgreSQL not found! Set up first!"
      return 1
    fi
    ;;
  "flink")
    if ! k8s::kubectl::object_exists deploy flink-jobmanager; then
      logging::error "Flink not found! Set up first!"
      return 1
    fi
    ;;
  *)
    logging::error "Invalid benchmark system: ${BENCHMARK_SYSTEM}!"
    return 1
    ;;
  esac
}
