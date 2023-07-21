# Provide utilities for operating GCP GCS in benchmark script.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_GCP_GCS_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_GCP_GCS_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/../core/lib.sh"

#######################################
# Activate service account and overwrite GCS credentials
#
# Notes
#   It overwrites the following environment variables used for accessing the GCS with the configured keys.
#   - BENCHMARK_RISINGWAVE_STORAGE_GCS_SERVICE_ACCOUNT_CREDENTIALS
# Globals
#   BENCHMARK_GCLOUD_SERVICE_ACCOUNT_KEY_FILE
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::gcp_gcs::configure_gcloud() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(gcloud)
  local gcs_credentials

  if [[ "${BENCHMARK_GCLOUD_SERVICE_ACCOUNT_KEY_FILE}" == "" ]]; then
    logging::error "Failed! gcloud service account key file must be provided!"
    return 1
  fi

  glcoud::activate_service_account

  # shellcheck disable=SC2155
  local os=$(uname -s)
  case "${os}" in
  Linux)
    gcs_credentials=$(jq '.' "${BENCHMARK_GCLOUD_SERVICE_ACCOUNT_KEY_FILE}" | base64 -w 0)
    ;;
  Darwin)
    gcs_credentials=$(jq '.' "${BENCHMARK_GCLOUD_SERVICE_ACCOUNT_KEY_FILE}" | base64)
    ;;
  *)
    logging:error "Unsupported platform ${os}"
    return 1
    ;;
  esac

  logging::info "GCS credentials used by RisingWave is overwriten with the service account key file!"
  export BENCHMARK_RISINGWAVE_STORAGE_GCS_SERVICE_ACCOUNT_CREDENTIALS="${gcs_credentials}"
}

#######################################
# Test if GCP GCS bucket creation is enabled.
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
#   BENCHMARK_GCS_BUCKET_CREATE_ENABLED
# Arguments
#   None
# Returns
#   0 for true, 1 for false
#######################################
function benchmark::external::gcp_gcs::create_bucket_enabled() {
  [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "gcs" && "${BENCHMARK_GCS_BUCKET_CREATE_ENABLED}" == "true" ]]
}

#######################################
# Create the corresponding GCP GCS bucket if the creation is enabled. The function starts a prompt to ask for inputs
# of decision if BENCHMARK_GCLOUD_ASK_BEFORE_PROCEED is true. It will first check if the bucket exists, and create it if it doesn't.
#
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
#   BENCHMARK_GCS_BUCKET_CREATE_ENABLED
#   BENCHMARK_GCLOUD_ASK_BEFORE_PROCEED
#   BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET
#   BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::gcp_gcs::create_bucket() {
  benchmark::external::gcp_gcs::create_bucket_enabled || return 0

  benchmark::external::gcp_gcs::configure_gcloud

  benchmark::external::gcp_gcs::set_gcs_bucket_location

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(gcloud "gcs: ${BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION}/${BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET}")

  if [[ "${BENCHMARK_GCLOUD_ASK_BEFORE_PROCEED}" == "true" ]]; then
    logging::infof "Do you want to create the GCS bucket? [y/n]: "
    read -r ans
  else
    local ans="y"
  fi

  # Short circuit the function.
  [[ "${ans}" == "y" || "${ans}" == "yes" ]] || return 0

  logging::info "Creating ..."

  if glcoud::bucket_exists "${BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET}"; then
    logging::warn "Already exists!"
    return 0
  fi

  if ! gcloud::create_bucket "${BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION}" "${BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET}"; then
    logging::error "Failed!"
    return 1
  fi

  logging::info "Created!"
}

#######################################
# Test if GCP GCS bucket deletion is enabled.
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
#   BENCHMARK_GCS_BUCKET_DELETE_ENABLED
# Arguments
#   None
# Returns
#   0 for true, 1 for false
#######################################
function benchmark::external::gcp_gcs::delete_bucket_enabled() {
  [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "gcs" && "${BENCHMARK_GCS_BUCKET_DELETE_ENABLED}" == "true" ]]
}

#######################################
# Delete the corresponding GCP GCS bucket if the deletion is enabled. The function starts a prompt to ask for inputs
# of decision if BENCHMARK_GCLOUD_ASK_BEFORE_PROCEED is true. It will first check if the bucket exists, and delete it if it does.
#
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
#   BENCHMARK_GCS_BUCKET_CREATE_ENABLED
#   BENCHMARK_GCLOUD_ASK_BEFORE_PROCEED
#   BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET
#   BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::gcp_gcs::delete_bucket() {
  benchmark::external::gcp_gcs::delete_bucket_enabled || return 0

  benchmark::external::gcp_gcs::configure_gcloud

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(gcloud "gcs: ${BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION}/${BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET}")

  if [[ "${BENCHMARK_GCLOUD_ASK_BEFORE_PROCEED}" == "true" ]]; then
    logging::warnf "Do you want to delete the GCS bucket forcefully? [y/n]: "
    read -r ans
  else
    local ans="y"
  fi

  # Short circuit the function.
  [[ "${ans}" == "y" || "${ans}" == "yes" ]] || return 0

  logging::info "Deleting ..."

  if ! glcoud::bucket_exists "${BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET}"; then
    logging::warn "Not found!"
    return 0
  fi

  if ! gcloud::delete_bucket "${BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET}"; then
    logging::error "Failed!"
    return 1
  fi

  logging::info "Deleted!"
}

#######################################
# Set the bucket location of gcs.
#
# When kube config context is an GKE cluster,
# If BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION is not set, the gcs bucket should be aligned with the GKE region.
# If BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION is set but not aligned with the GKE region, it will start a prompt and ask for confirm.
#
# Notes
#   It overwrites the following environment variables used for accessing the S3.
#   - BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::gcp_gcs::set_gcs_bucket_location() {
  # shellcheck disable=SC2034
  local exit_code=0

  # GKE context example: gke_rwcdev_asia-southeast1_dev-gcp-asse1-gke-a-gke
  k8s::kubectl config current-context | grep gke >/dev/null || exit_code=$?
  if ((exit_code == 0)); then
    GKE_REGION=$(k8s::kubectl config current-context | cut -d'_' -f 3)
    logging::info "GKE location: ${GKE_REGION}, RisingWave storage gcs location: ${BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION}"
    if [[ "${BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION}" != "" && "${BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION}" != "${GKE_REGION}" ]]; then
      logging::warnf "The gcs bucket location is inconsistent with the GKE location!\n"
      logging::warnf "Do you want to set the gcs bucket in ${BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION} location? [y/n]: "
      read -r ans
    else
      local ans="n"
    fi

    if [[ "${ans}" == "y" || "${ans}" == "yes" ]]; then
      return 0
    fi
    export BENCHMARK_RISINGWAVE_STORAGE_GCS_LOCATION="${GKE_REGION}"
  fi
}