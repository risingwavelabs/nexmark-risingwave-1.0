# Command functions of benchmark script.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_COMMAND_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_COMMAND_SH__=true

source "$(dirname "${BASH_SOURCE[0]}")/../core/lib.sh"
source "$(dirname "${BASH_SOURCE[0]}")/aws_s3.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gcp_gcs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/runtime.sh"
source "$(dirname "${BASH_SOURCE[0]}")/stage.sh"

#######################################
# The main entrance of the benchmark script.
# Globals
#   BENCHMARK_*
#   BENCHMARK_BASE defines the base directory of kube-bench scripts.
#   BENCHMARK_ENV_OVERRIDE defines the override file to read.
# Arguments
#   Variable sized strings.
# Returns
#   Depends on the command runs.
#######################################
function benchmark::command::run() {
  local subcommand=""
  (($# >= 1)) && subcommand="$1"

  if [[ "${subcommand}" == "help" || "${subcommand}" == "" ]]; then
    benchmark::command::help "${@:2}"
    return 0
  fi

  prerequisites::benchmark::run
  benchmark::env::load

  logging::set_level "${BENCHMARK_LOG_LEVEL:-info}"

  if [[ "${subcommand}" != "envs" && "${subcommand}" != "eval" ]]; then
    local LOGGING_TAGS=("workspace/k8s" "namespace: ${BENCHMARK_NAMESPACE}")
    logging::info "Happy benchmarking!"
    unset LOGGING_TAGS
  fi

  case "${subcommand}" in
  hint)
    benchmark::command::hint "${@:2}"
    ;;
  aws)
    benchmark::command::aws "${@:2}"
    ;;
  kubectl | k)
    benchmark::command::kubectl "${@:2}"
    ;;
  d | dashboard)
    benchmark::command::dashboard "${@:2}"
    ;;
  logs)
    benchmark::command::logs "${@:2}"
    ;;
  envs)
    benchmark::command::envs "${@:2}"
    ;;
  eval)
    benchmark::command::eval "${@:2}"
    ;;
  connect)
    benchmark::command::connect "${@:2}"
    ;;
  init)
    benchmark::command::init "${@:2}"
    ;;
  setup)
    benchmark::command::setup "${@:2}"
    ;;
  teardown)
    benchmark::command::teardown "${@:2}"
    ;;
  prepare)
    benchmark::command::prepare "${@:2}"
    ;;
  clean)
    benchmark::command::clean "${@:2}"
    ;;
  start)
    benchmark::command::start "${@:2}"
    ;;
  stop)
    benchmark::command::stop "${@:2}"
    ;;
  *)
    benchmark::command::help
    ;;
  esac
}

function benchmark::command::help() {
  cat <<EOF
usage: $(benchmark::runtime::script_path) command [arguments...]

commands:
  help          show help message
  hint          show hints of useful commands
  kubectl|k     alias for running kubectl without namespace
  aws           alias for running aws without profile
  logs          show logs of benchmark job
                  -f            specify if the logs should be streamed
                  --tail=10     lines of recent log file to display (defaults to 10)
  envs          show loaded environment variables
  eval          show rendered content of template file
  connect       connect to the running RisingWave via psql
  init          initialize the benchmark workspace
  setup         setup resources for benchmark
                  -i            run init before setting up
  teardown      teardown resources created by setup
                  -f            remove the workspace(namespace) forcefully
  prepare       prepare for the benchmark run
  clean         clean the benchmark run, including materialized views, sources, topics, and jobs
  start         start the benchmark run
  stop          stop the benchmark run
  dashboard|d   serve the meta dashboard at localhost by proxying the traffic

globals
  BENCHMARK_WORKDIR       path to store session files (defaults to the script path)
  BENCHMARK_ENV_OVERRIDE  path to the override file (defaults to env.override.toml under the script path)
EOF
}

function benchmark::command::init() {
  benchmark::stage::init
}

function benchmark::command::logs() {
  # shellcheck disable=SC2034
  local LOGGING_TAGS=("benchmark: ${BENCHMARK_JOB_TYPE}")

  if ! benchmark::stage::is_started; then
    logging::error "Not started yet!"
    return 1
  fi
  k8s::kubectl logs -l job-name="${BENCHMARK_JOB_NAME}" --all-containers=true "$@"
}

function benchmark::command::envs() {
  env | grep "^BENCHMARK_" | sort
}

function benchmark::command::eval() {
  (($# == 1)) || { echo >&2 "not enough arguments" && return 1; }

  env::generate_rendered_manifest "$1"
}

function benchmark::command::connect::_is_port_open() {
  # shellcheck disable=SC2217
  true &>/dev/null </dev/tcp/localhost/4567
}

# List of commands required by the benchmark connect command.
readonly -a _BENCHMARK_CONNECT_REQUIRED_COMMANDS=(
  psql
)

function benchmark::command::connect::with_forward() {
  prerequisites::check_commands_existence_and_try_install "${_BENCHMARK_CONNECT_REQUIRED_COMMANDS[@]}"

  session_file=$(benchmark::runtime::session_path connect.sock)
  export session_file

  if [[ -f "${session_file}" ]]; then
    logging::info "Sharing a background forward process, keep that process alive!"
    logging::infof "Connecting with\n  %s\n" "psql -h localhost -p 4567 -d dev -U root"
    psql -h localhost -p 4567 -d dev -U root
    return
  fi

  if benchmark::command::connect::_is_port_open; then
    logging::error "Failed to listen on localhost:4567, error: bind failed, address already in use!"
    return 1
  fi

  forward_pid=0
  export forward_pid
  trap 'rm -f ${session_file}; if ((forward_pid!=0)); then pkill -9 -P ${forward_pid} || :; fi' RETURN TERM EXIT
  touch "${session_file}"

  common::run k8s::kubectl port-forward svc/"${BENCHMARK_RISINGWAVE_NAME}-frontend" 4567:service &
  forward_pid=$!

  while ! benchmark::command::connect::_is_port_open; do
    if ! common::run kill -0 "${forward_pid}"; then
      logging::error "Failed to forward the traffic!"
      return 1
    fi
    sleep 1
  done

  logging::info "Forwarding traffic to one of the frontend Pods, listening on localhost:4567..."

  logging::infof "Connecting with\n  %s\n" "psql -h localhost -p 4567 -d dev -U root"
  psql -h localhost -p 4567 -d dev -U root

  # Terminate the forward process.
  pkill -TERM -P ${forward_pid} || :
  rm -f "${session_file}"

  wait "${forward_pid}" || return 0
}

function benchmark::command::connect() {
  if ! benchmark::runtime::is_console k8s; then
    benchmark::command::connect::with_forward
  else
    logging::infof "Connecting with\n  %s\n" "psql -h ${BENCHMARK_RISINGWAVE_NAME}-frontend.${BENCHMARK_NAMESPACE} -p 4567 -d dev -U root"
    psql -h "${BENCHMARK_RISINGWAVE_NAME}"-frontend."${BENCHMARK_NAMESPACE}" -p 4567 -d dev -U root
  fi
}

function benchmark::command::kubectl() {
  logging::debug "kubectl -n ${BENCHMARK_NAMESPACE} $*"
  k8s::kubectl "$@"
}

function benchmark::command::setup() {
  local init_before_setup=false
  while getopts ":i" opt; do
    case "${opt}" in
    i)
      init_before_setup=true
      ;;
    *) ;;
    esac
  done

  if [[ "${init_before_setup}" == "true" ]]; then
    benchmark::stage::is_initialized || benchmark::stage::init
  else
    benchmark::stage::init::check_status
  fi

  case "${BENCHMARK_SYSTEM}" in
  "risingwave")
    logging::info "Benchmark system is RisingWave."

    benchmark::external::aws_s3::create_bucket
    benchmark::external::gcp_gcs::create_bucket

    # Background in subshell to avoid global variable conflicts.
    # shellcheck disable=SC2034
    local BACKGROUND_PIDS=()

    job::spawn "(benchmark::component::etcd::start)"
    job::spawn "(benchmark::component::kafka::start)"

    job::wait

    benchmark::component::risingwave::start
    ;;
  "flink")
    logging::info "Benchmark system is Flink."

    benchmark::external::aws_s3::flink_config_s3

    local BACKGROUND_PIDS=()

    job::spawn "(benchmark::component::kafka::start)"
    job::spawn "(benchmark::component::flink::start)"

    job::wait
    ;;
  *)
    logging::error "Invalid benchmark system: ${BENCHMARK_SYSTEM}!"
    return 1
    ;;
  esac
}

function benchmark::command::teardown() {
  local force_teardown=false
  while getopts ":f" opt; do
    case "${opt}" in
    f)
      force_teardown=true
      ;;
    *) ;;
    esac
  done

  benchmark::stage::init::check_status

  if [[ "${force_teardown}" == "true" ]]; then
    logging::info "Teardown forcefully! Deleting namespace ${BENCHMARK_NAMESPACE}..."
    common::run kubectl delete ns "${BENCHMARK_NAMESPACE}"
    logging::info "Deleted!"
  else
    FORCE=true benchmark::stage::clean

    # shellcheck disable=SC2034
    local BACKGROUND_PIDS=()

    case "${BENCHMARK_SYSTEM}" in
    "risingwave")
      job::spawn "(benchmark::component::etcd::stop)"
      job::spawn "(benchmark::component::kafka::stop)"
      job::spawn "(benchmark::component::risingwave::stop)"

      job::wait
      ;;
    "flink")
      job::spawn "(benchmark::component::kafka::stop)"
      job::spawn "(benchmark::component::flink::stop)"

      job::wait
      ;;
    *)
      logging::error "Invalid benchmark system: ${BENCHMARK_SYSTEM}!"
      return 1
      ;;
    esac
  fi

  benchmark::external::aws_s3::delete_bucket
  benchmark::external::gcp_gcs::delete_bucket
  benchmark::external::aws_s3::delete_bucket_folder
}

function benchmark::command::prepare() {
  benchmark::stage::init::check_status
  benchmark::stage::setup::check_status

  benchmark::stage::prepare
}

function benchmark::command::start() {
  benchmark::stage::init::check_status
  benchmark::stage::setup::check_status

  benchmark::stage::start
}

function benchmark::command::stop() {
  benchmark::stage::init::check_status
  benchmark::stage::setup::check_status

  benchmark::stage::stop
}

function benchmark::command::clean() {
  benchmark::stage::init::check_status
  benchmark::stage::setup::check_status

  benchmark::stage::clean
}

function benchmark::command::aws() {
  benchmark::external::aws::configure_cli

  logging::debug "aws --profile ${AWSCLI_PROFILE} $*"
  awscli::aws "$@"
}

function benchmark::command::dashboard::_is_open() {
  # shellcheck disable=SC2217
  true &>/dev/null </dev/tcp/localhost/5691
}

function benchmark::command::dashboard() {
  if benchmark::command::dashboard::_is_open; then
    logging::error "Failed to listen on localhost:5691, error: bind failed, address already in use!"
    return 1
  fi

  common::run k8s::kubectl port-forward svc/"${BENCHMARK_RISINGWAVE_NAME}-meta" 5691:dashboard &
  local forward_pid=$!
  # shellcheck disable=SC2064
  trap "pkill -9 -P ${forward_pid}" RETURN

  while ! benchmark::command::dashboard::_is_open; do
    if ! common::run kill -0 "${forward_pid}"; then
      logging::error "Failed to forward the traffic!"
      return 1
    fi
    sleep 1
  done

  logging::info "Serving the dashboard at http://localhost:5691"

  local os
  os=$(uname -s)
  if [[ "${os}" == "Darwin" ]]; then
    open "http://localhost:5691"
  fi

  wait "${forward_pid}" || return $?
}

function benchmark::command::hint() {
  local script
  script=$(benchmark::runtime::script_path)
  cat <<EOF
kubectl:
  List the Pods
  ${script} kubectl get pods

  Describe a Pod
  ${script} kubectl describe pod <pod-name>

  List the Jobs
  ${script} kubectl get jobs

  Describe a Job
  ${script} kubectl describe job <job-name>

  List the RisingWave
  ${script} kubectl get risingwave

  Show logs of a Pod
  ${script} kubectl logs <pod-name>
  ${script} kubectl logs <pod-name> -f

  Show logs of the previous run containers of a Pod
  ${script} kubectl logs <pod-name> -p

  Attach and run bash inside a pod if there's a bash in the image (defaults to the first container in the Pod)
  ${script} kubectl exec -it <pod-name> -- bash

aws:
  Summarize the usage of the S3 bucket
  ${script} aws s3 ls --summarize --human-readable --recursive s3://${BENCHMARK_RISINGWAVE_STORAGE_S3_BUCKET}/${BENCHMARK_RISINGWAVE_STORAGE_S3_DATA_DIRECTORY}
EOF
}
