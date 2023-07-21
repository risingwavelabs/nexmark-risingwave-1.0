# Provide utilities for operating AWS S3 in benchmark script.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_AWS_S3_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_AWS_S3_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/../core/lib.sh"

#######################################
# Helper function for configuring the awscli.
# Globals
#   access_key
#   secret_access_key
#   BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY
#   BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::aws::_configure_cli() {
  if [[ "${BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY}" != "" && "${BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET}" != "" ]]; then
    access_key=${BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY}
    secret_access_key=${BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET}
  else
    logging::info "Input AWS credentials to proceed:"
    read -r -p "AWS Access Key ID: " access_key
    read -r -p "AWS Secret Access Key: " -s secret_access_key
    echo
  fi

  awscli::configure "" "${access_key}" "${secret_access_key}"
  logging::info "AWSCLI is configured to use profile ${AWSCLI_PROFILE}"
}

#######################################
# Configure the existing or create a new profile used by awscli with access key and secret access key.
#
# If BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY and BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET are not both set,
# it will start a prompt and ask for inputs of these two keys.
#
# Globals
#   BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY
#   BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::aws::configure_cli() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(awscli)
  local access_key
  local secret_access_key

  benchmark::external::aws::_configure_cli
}

#######################################
# Configure the existing or create a new profile used by awscli with access key and secret access key.
#
# If BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY and BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET are not both set,
# it will start a prompt and ask for inputs of these two keys.
#
# Notes
#   It overwrites the following environment variables used for accessing the S3 with the configured keys.
#   - BENCHMARK_RISINGWAVE_STORAGE_S3_ACCESS_KEY
#   - BENCHMARK_RISINGWAVE_STORAGE_S3_ACCESS_SECRET
# Globals
#   BENCHMARK_AWS_CREDENTIALS_ACCESS_KEY
#   BENCHMARK_AWS_CREDENTIALS_ACCESS_SECRET
#   BENCHMARK_RISINGWAVE_STORAGE_S3_ACCESS_KEY
#   BENCHMARK_RISINGWAVE_STORAGE_S3_ACCESS_SECRET
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::aws_s3::configure_cli() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(awscli)
  local access_key
  local secret_access_key

  benchmark::external::aws::_configure_cli

  # Overwrite the credential variables used by RisingWave.
  logging::warn "S3 configuration used by RisingWave is overwritten with the AWS credentials!"
  export BENCHMARK_RISINGWAVE_STORAGE_S3_ACCESS_KEY="${access_key}"
  export BENCHMARK_RISINGWAVE_STORAGE_S3_ACCESS_SECRET="${secret_access_key}"
  export BENCHMARK_FLINK_S3_ACCESS_KEY="${access_key}"
  export BENCHMARK_FLINK_S3_ACCESS_SECRET="${secret_access_key}"
}

#######################################
# Test if AWS S3 bucket creation is enabled.
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
#   BENCHMARK_S3_BUCKET_CREATE_ENABLED
# Arguments
#   None
# Returns
#   0 for true, 1 for false
#######################################
function benchmark::external::aws_s3::create_bucket_enabled() {
  [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "s3" && "${BENCHMARK_S3_BUCKET_CREATE_ENABLED}" == "true" ]]
}

#######################################
# Test if AWS S3 bucket deletion is enabled.
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
#   BENCHMARK_S3_BUCKET_DELETE_ENABLED
# Arguments
#   None
# Returns
#   0 for true, 1 for false
#######################################
function benchmark::external::aws_s3::delete_bucket_enabled() {
  [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "s3" && "${BENCHMARK_S3_BUCKET_DELETE_ENABLED}" == "true" ]]
}

#######################################
# Create the corresponding AWS S3 bucket if the creation is enabled. The function starts a prompt to ask for inputs
# of decision if BENCHMARK_AWS_ASK_BEFORE_PROCEED is true. It will first check if the bucket exists, and create it if it doesn't.
#
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
#   BENCHMARK_S3_BUCKET_CREATE_ENABLED
#   BENCHMARK_AWS_ASK_BEFORE_PROCEED
#   BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET
#   BENCHMARK_RISINGWAVE_STORAGE_S3_REGION
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::aws_s3::create_bucket() {
  benchmark::external::aws_s3::create_bucket_enabled || return 0

  benchmark::external::aws_s3::configure_cli

  benchmark::external::aws_s3::set_s3_bucket_region

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(awscli "s3: ${BENCHMARK_RISINGWAVE_STORAGE_S3_REGION}/${BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET}")

  if [[ "${BENCHMARK_AWS_ASK_BEFORE_PROCEED}" == "true" ]]; then
    logging::infof "Do you want to create the S3 bucket? [y/n]: "
    read -r ans
  else
    local ans="y"
  fi

  # Short circuit the function.
  [[ "${ans}" == "y" || "${ans}" == "yes" ]] || return 0

  logging::info "Creating ..."

  if awscli::s3api::bucket_exists "${BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET}"; then
    logging::warn "Already exists!"
    return 0
  fi

  if ! awscli::s3api::create_bucket "${BENCHMARK_RISINGWAVE_STORAGE_S3_REGION}" "${BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET}"; then
    logging::error "Failed!"
    return 1
  fi

  logging::info "Created!"
}

#######################################
# Delete the corresponding AWS S3 bucket if the deletion is enabled. The function starts a prompt to ask for inputs
# of decision if BENCHMARK_AWS_ASK_BEFORE_PROCEED is true. It will first check if the bucket exists, and delete it if it does.
#
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_TYPE
#   BENCHMARK_S3_BUCKET_CREATE_ENABLED
#   BENCHMARK_AWS_ASK_BEFORE_PROCEED
#   BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET
#   BENCHMARK_RISINGWAVE_STORAGE_S3_REGION
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::aws_s3::delete_bucket() {
  benchmark::external::aws_s3::delete_bucket_enabled || return 0

  benchmark::external::aws_s3::configure_cli

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(awscli "s3: ${BENCHMARK_RISINGWAVE_STORAGE_S3_REGION}/${BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET}")

  if [[ "${BENCHMARK_AWS_ASK_BEFORE_PROCEED}" == "true" ]]; then
    logging::warnf "Do you want to delete the S3 bucket forcefully? [y/n]: "
    read -r ans
  else
    local ans="y"
  fi

  # Short circuit the function.
  [[ "${ans}" == "y" || "${ans}" == "yes" ]] || return 0

  logging::info "Deleting ..."

  if ! awscli::s3api::bucket_exists "${BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET}"; then
    logging::warn "Not found!"
    return 0
  fi

  if ! AWSCLI_S3API_FORCE_DELETE_BUCKET=true awscli::s3api::delete_bucket "${BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET}"; then
    logging::error "Failed!"
    return 1
  fi

  logging::info "Deleted!"
}

#######################################
# Flink configure and check s3
#
# Globals
#   BENCHMARK_FLINK_S3_BUCKET
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::aws_s3::flink_config_s3() {
  benchmark::component::flink::enabled || return 0

  benchmark::external::aws_s3::configure_cli

  # shellcheck disable=SC2034
  local LOGGING_TAGS=(awscli "s3: ${BENCHMARK_FLINK_S3_BUCKET}")

  if ! awscli::s3api::bucket_exists "${BENCHMARK_FLINK_S3_BUCKET}"; then
    logging::error "Not found! Please specify an existing bucket."
    return 1
  fi
}

#######################################
# Delete the corresponding AWS S3 bucket folder if the deletion is enabled. The function starts a prompt to ask for inputs
#
# Globals
#   BENCHMARK_AWS_ASK_BEFORE_PROCEED
#   BENCHMARK_FLINK_S3_BUCKET
#   BENCHMARK_FLINK_S3_BUCKET_FOLDER
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::aws_s3::delete_bucket_folder() {
  benchmark::component::flink::enabled || return 0

  benchmark::external::aws_s3::configure_cli

  bucket_folder="${BENCHMARK_FLINK_S3_BUCKET}/${BENCHMARK_FLINK_S3_BUCKET_FOLDER}"
  # shellcheck disable=SC2034
  local LOGGING_TAGS=(awscli "s3: ${bucket_folder}")

  if [[ "${BENCHMARK_AWS_ASK_BEFORE_PROCEED}" == "true" ]]; then
    logging::warnf "Do you want to delete the S3 bucket forcefully? [y/n]: "
    read -r ans
  else
    local ans="y"
  fi

  # Short circuit the function.
  [[ "${ans}" == "y" || "${ans}" == "yes" ]] || return 0

  logging::info "Deleting ..."

  if ! awscli::s3api::bucket_exists "${BENCHMARK_FLINK_S3_BUCKET}"; then
    logging::warn "Not found!"
    return 0
  fi

  if ! awscli::s3api::delete_bucket_folder "${bucket_folder}"; then
    logging::error "Failed!"
    return 1
  fi

  logging::info "Deleted!"
}

#######################################
# Set the bucket region of s3.
#
# When kube config context is an EKS cluster,
# If BENCHMARK_RISINGWAVE_STORAGE_S3_REGION is not set, the s3 bucket should be aligned with the EKS region.
# If BENCHMARK_RISINGWAVE_STORAGE_S3_REGION is set but not aligned with the eks region, it will start a prompt and ask for confirm.
#
# Notes
#   It overwrites the following environment variables used for accessing the S3.
#   - BENCHMARK_RISINGWAVE_STORAGE_S3_REGION
# Globals
#   BENCHMARK_RISINGWAVE_STORAGE_S3_REGION
# Arguments
#   None
# Returns
#   0 if succeeds, non-zero on error.
#######################################
function benchmark::external::aws_s3::set_s3_bucket_region() {
  # shellcheck disable=SC2034
  local exit_code=0

  # EKS context example: arn:aws:eks:us-east-1:023339134545:cluster/test-useast1-eks-a
  k8s::kubectl config current-context | grep aws:eks >/dev/null || exit_code=$?
  if ((exit_code == 0)); then
    EKS_REGION=$(k8s::kubectl config current-context | cut -d':' -f 4)
    logging::info "EKS region: ${EKS_REGION}, RisingWave storage s3 region: ${BENCHMARK_RISINGWAVE_STORAGE_S3_REGION}"
    if [[ "${BENCHMARK_RISINGWAVE_STORAGE_S3_REGION}" != "" && "${BENCHMARK_RISINGWAVE_STORAGE_S3_REGION}" != "${EKS_REGION}" ]]; then
      logging::warnf "The s3 bucket region is inconsistent with the EKS region!\n"
      logging::warnf "Do you want to set the s3 bucket in ${BENCHMARK_RISINGWAVE_STORAGE_S3_REGION} region? [y/n]: "
      read -r ans
    else
      local ans="n"
    fi

    if [[ "${ans}" == "y" || "${ans}" == "yes" ]]; then
      return 0
    fi
    export BENCHMARK_RISINGWAVE_STORAGE_S3_REGION="${EKS_REGION}"
  fi
}