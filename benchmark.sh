#!/usr/bin/env bash

set -euo pipefail

BENCHMARK_BASE="$(dirname "${BASH_SOURCE[0]}")"
export BENCHMARK_BASE
BENCHMARK_CONSOLE=${BENCHMARK_CONSOLE:=""}
export BENCHMARK_CONSOLE

source "$(dirname "${BASH_SOURCE[0]}")/lib/benchmark/lib.sh"

if [[ -v "DEBUG" && ("${DEBUG}" == "1" || "${DEBUG}" == "true") ]]; then
  benchmark::debug::enable
  # Unset DEBUG to avoid unexpected behaviours
  unset DEBUG
fi

benchmark::command::run "$@"
