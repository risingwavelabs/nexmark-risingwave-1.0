# Perform operations on AWS resources with the gcloud cli.
${__BENCHMARK_SOURCE_LIB_CORE_GCP_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_CORE_GCP_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

#######################################
# Utility function for gcloud activate service account.
# Returns
#   Code that gcloud returns.
#######################################
function glcoud::activate_service_account() {
  gcloud auth activate-service-account --key-file "${BENCHMARK_GCLOUD_SERVICE_ACCOUNT_KEY_FILE}" >/dev/null

  local active_service_account
  active_service_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
  logging::info "gcloud active service account is ${active_service_account}"
}

# Check if a bucket exists in the specified location.
# Arguments:
#   Bucket name.
# Returns
#   0 if the bucket exists, non-zero else or on error.
#######################################
function glcoud::bucket_exists() {
  (($# == 1)) || { echo >&2 "not enough arguments" && return 1; }
  [[ -n "$1" ]] || { echo >&2 "bucket must be provided" && return 1; }

  local bucket=$1

  gcloud storage ls |grep gs://"${bucket}"/ >/dev/null
}

#######################################
# Create a bucket in the specified location.
# Arguments:
#   Location
#   Bucket name
# Returns
#   Code that gcloud returns.
#######################################
function gcloud::create_bucket() {
  (($# == 2)) || { echo >&2 "not enough arguments" && return 1; }
  [[ -n "$1" && -n "$2" ]] || { echo >&2 "either location or bucket must be provided" && return 1; }

  local location=$1
  local bucket=$2

  gcloud storage buckets create gs://"${bucket}" --location "${location}" >/dev/null 2>&1
}

#######################################
# Create a bucket in the specified location.
# Arguments:
#   Location
#   Bucket name
# Returns
#   Code that gcloud returns.
#######################################
function gcloud::delete_bucket() {
  (($# == 1)) || { echo >&2 "not enough arguments" && return 1; }
  [[ -n "$1" ]] || { echo >&2 "bucket must be provided" && return 1; }

  local bucket=$1

  gcloud storage rm --recursive gs://"${bucket}" >/dev/null 2>&1
}
