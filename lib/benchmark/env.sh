# Benchmark env functions.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_ENV_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_ENV_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/../core/lib.sh"

#######################################
# Run overrides according to the current environment variables.
# Globals
#   BENCHMARK_*
# Arguments
#   None
# Returns
#   0
#######################################
function benchmark::env::overrides() {
  if [[ "${BENCHMARK_JOB_TYPE}" == "nexmark-kafka" ]] ||
     [[ "${BENCHMARK_JOB_TYPE}" == "flink-nexmark-kafka" ]]; then
    if [[ "${BENCHMARK_KAFKA_ENABLED}" != "true" ]]; then
      logging::warn "Benchmark type is ${BENCHMARK_JOB_TYPE}! Kafka must be enabled!"
      export BENCHMARK_KAFKA_ENABLED=true

      # shellcheck disable=SC2155
      export BENCHMARK_PODS_DISTRIBUTION_GEN_AFFINITY_ZK=$(
        cat <<EOF | jq -c
{
 "podAffinity": {
   "requiredDuringSchedulingIgnoredDuringExecution": [
     {
       "topologyKey": "kubernetes.io/hostname",
       "labelSelector": {
         "matchLabels": {
           "benchmark/pod-affinity": "kafka"
         }
       }
     }
   ]
 }
}
EOF
      )
    fi
  fi

  if [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "s3" ]]; then
    # shellcheck disable=SC2155
    export BENCHMARK_RISINGWAVE_STORAGE_GEN_OBJECTS=$(
      cat <<EOF | jq -c
{
  "dataDirectory": "${BENCHMARK_RISINGWAVE_STORAGE_S3_DATA_DIRECTORY}",
  "s3": {
    "region": "${BENCHMARK_RISINGWAVE_STORAGE_S3_REGION}",
    "bucket": "${BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET}",
    "credentials": {
      "secretName": "${BENCHMARK_RISINGWAVE_NAME}-s3-credentials"
    }
  }
}
EOF
    )
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "s3c" ]]; then
    # shellcheck disable=SC2155
    export BENCHMARK_RISINGWAVE_STORAGE_GEN_OBJECTS=$(
      cat <<EOF | jq -c
{
  "dataDirectory": "${BENCHMARK_RISINGWAVE_STORAGE_S3_DATA_DIRECTORY}",
  "s3": {
    "region": "${BENCHMARK_RISINGWAVE_STORAGE_S3C_REGION}",
    "bucket": "${BENCHMARK_RISINGWAVE_STORAGE_S3C_BUCKET}",
    "endpoint": "${BENCHMARK_RISINGWAVE_STORAGE_S3C_ENDPOINT}",
    "virtualHostedStyle": "${BENCHMARK_RISINGWAVE_STORAGE_S3C_VIRTUAL_HOSTED_STYLE}",
    "credentials": {
      "secretName": "${BENCHMARK_RISINGWAVE_NAME}-${BENCHMARK_RISINGWAVE_STORAGE_S3C_VENDOR}-credentials"
    }
  }
}
EOF
    )
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "gcs" ]]; then
    # shellcheck disable=SC2155
    export BENCHMARK_RISINGWAVE_STORAGE_GEN_OBJECTS=$(
      cat <<EOF | jq -c
{
  "dataDirectory": "${BENCHMARK_RISINGWAVE_STORAGE_GCS_DATA_DIRECTORY}",
  "gcs": {
    "bucket": "${BENCHMARK_RISINGWAVE_STORAGE_GCS_BUCKET}",
    "root": "${BENCHMARK_RISINGWAVE_STORAGE_GCS_DATA_DIRECTORY}",
    "credentials": {
      "secretName": "${BENCHMARK_RISINGWAVE_NAME}-gcs-credentials"
    }
  }
}
EOF
    )
  elif [[ "${BENCHMARK_RISINGWAVE_STORAGE_TYPE}" == "azureblob" ]]; then
    # shellcheck disable=SC2155
    export BENCHMARK_RISINGWAVE_STORAGE_GEN_OBJECTS=$(
      cat <<EOF | jq -c
{
  "dataDirectory": "${BENCHMARK_RISINGWAVE_STORAGE_AZUREBLOB_DATA_DIRECTORY}",
  "azureBlob": {
    "endpoint": "${BENCHMARK_RISINGWAVE_STORAGE_AZUREBLOB_ENDPOINT}",
    "root": "${BENCHMARK_RISINGWAVE_STORAGE_AZUREBLOB_DATA_DIRECTORY}",
    "container": "${BENCHMARK_RISINGWAVE_STORAGE_AZUREBLOB_CONTAINER}",
    "credentials": {
      "secretName": "${BENCHMARK_RISINGWAVE_NAME}-azureblob-credentials"
    }
  }
}
EOF
    )
  fi

  if [[ "${BENCHMARK_PODS_DISTRIBUTION_NODE_SELECTORS}" != "" ]]; then
    BENCHMARK_PODS_DISTRIBUTION_GEN_NODE_SELECTOR=$(args::convert_key_value_pairs_to_json "${BENCHMARK_PODS_DISTRIBUTION_NODE_SELECTORS}")
    export BENCHMARK_PODS_DISTRIBUTION_GEN_NODE_SELECTOR

    # shellcheck disable=SC2155
    export BENCHMARK_PODS_DISTRIBUTION_GEN_AFFINITY_FRONTEND_META=$(
      cat <<EOF | jq -c
{
 "podAffinity": {
   "requiredDuringSchedulingIgnoredDuringExecution": [
     {
       "topologyKey": "kubernetes.io/hostname",
       "labelSelector": {
         "matchLabels": {
           "benchmark/pod-affinity": "etcd"
         }
       }
     }
   ]
 }
}
EOF
    )

    case "${BENCHMARK_PODS_DISTRIBUTION_MUTUAL_EXCLUSIVE_POLICY}" in
    global)
      # shellcheck disable=SC2155
      export BENCHMARK_PODS_DISTRIBUTION_GEN_AFFINITY=$(
        cat <<EOF | jq -c
{
 "podAntiAffinity": {
   "requiredDuringSchedulingIgnoredDuringExecution": [
     {
       "topologyKey": "kubernetes.io/hostname",
       "namespaceSelector": {},
       "labelSelector": {
         "matchLabels": {
           "benchmark/system": "kube-bench",
           "benchmark/mutual-exclusive-key": "${BENCHMARK_PODS_DISTRIBUTION_MUTUAL_EXCLUSIVE_KEY}"
         }
       }
     }
   ]
 }
}
EOF
      )
      ;;
    namespace)
      # shellcheck disable=SC2155
      export BENCHMARK_PODS_DISTRIBUTION_GEN_AFFINITY=$(
        cat <<EOF | jq -c
{
 "podAntiAffinity": {
   "requiredDuringSchedulingIgnoredDuringExecution": [
     {
       "topologyKey": "kubernetes.io/hostname",
       "namespaceSelector": {},
       "labelSelector": {
         "matchLabels": {
           "benchmark/system": "kube-bench",
           "benchmark/mutual-exclusive-key": "${BENCHMARK_PODS_DISTRIBUTION_MUTUAL_EXCLUSIVE_KEY}"
         }
       }
     }
   ]
 }
}
EOF
      )
      ;;
    *) ;;
    esac
  fi

  # Set risingwave compactor and compute affinity.
  if [[ "${BENCHMARK_PODS_DISTRIBUTION_NODE_SELECTORS}" != "" &&
  "${BENCHMARK_PODS_DISTRIBUTION_COMPACTOR_COMPUTE_AFFINITY_ENABLED}" == "true" ]]; then
    export BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_CPU_LIMIT="${BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_CPU_LIMIT}"
    export BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_CPU_LIMIT="${BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_CPU_LIMIT}"

    export BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_CPU_REQUEST="${BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_CPU_REQUEST}"
    export BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_CPU_REQUEST="${BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_CPU_REQUEST}"

    export BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_MEM_LIMIT="${BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_MEM_LIMIT}"
    export BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_MEM_LIMIT="${BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_MEM_LIMIT}"

    export BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_MEM_REQUEST="${BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_MEM_REQUEST}"
    export BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_MEM_REQUEST="${BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_MEM_REQUEST}"

    # shellcheck disable=SC2155
    export BENCHMARK_PODS_DISTRIBUTION_GEN_AFFINITY_COMPUTE=$(
      cat <<EOF | jq -c
{
 "podAffinity": {
   "requiredDuringSchedulingIgnoredDuringExecution": [
     {
       "topologyKey": "kubernetes.io/hostname",
       "labelSelector": {
         "matchLabels": {
           "benchmark/pod-affinity": "compactor"
         }
       }
     }
   ]
 }
}
EOF
    )
  else
    export {BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_CPU_LIMIT,BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_CPU_LIMIT}="${BENCHMARK_RISINGWAVE_RESOURCES_CPU_LIMIT}"
    export {BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_CPU_REQUEST,BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_CPU_REQUEST}="${BENCHMARK_RISINGWAVE_RESOURCES_CPU_REQUEST}"

    export {BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_MEM_LIMIT,BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_MEM_LIMIT}="${BENCHMARK_RISINGWAVE_RESOURCES_MEM_LIMIT}"
    export {BENCHMARK_RISINGWAVE_RESOURCES_COMPACTOR_MEM_REQUEST,BENCHMARK_RISINGWAVE_RESOURCES_COMPUTE_MEM_REQUEST}="${BENCHMARK_RISINGWAVE_RESOURCES_MEM_REQUEST}"

    export BENCHMARK_PODS_DISTRIBUTION_GEN_AFFINITY_COMPUTE="${BENCHMARK_PODS_DISTRIBUTION_GEN_AFFINITY}"
  fi

  # Set the node envs.
  if [[ -v BENCHMARK_RISINGWAVE_QUERY_LOG_PATH ]]; then
    BENCHMARK_RISINGWAVE_GEN_NODE_ENVS=$(echo "${BENCHMARK_RISINGWAVE_GEN_NODE_ENVS}" | jq --arg path "${BENCHMARK_RISINGWAVE_QUERY_LOG_PATH}" '. + {RW_QUERY_LOG_PATH: $path}' -c)
  fi
}

#######################################
# Load environment variables for running benchmarks from the env.toml and the override file,
# and run overrides after the loading.
# Globals
#   BENCHMARK_ENV_OVERRIDE
#   BENCHMARK_*
# Arguments
#   None
# Returns
#   0
#######################################
function benchmark::env::load() {
  local override_file
  override_file="${BENCHMARK_ENV_OVERRIDE:-$(benchmark::runtime::path env.override.toml)}"

  # Load envs from files.
  env::load_from_toml_files "$(benchmark::runtime::path env.toml)" "${override_file}"

  # Run dynamic overrides.
  benchmark::env::overrides
}
