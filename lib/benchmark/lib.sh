# Library file for the benchmark package.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_LIB_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_LIB_SH__=true

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/aws_s3.sh"
source "$(dirname "${BASH_SOURCE[0]}")/gcp_gcs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/command.sh"
source "$(dirname "${BASH_SOURCE[0]}")/component.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/runtime.sh"
source "$(dirname "${BASH_SOURCE[0]}")/stage.sh"
source "$(dirname "${BASH_SOURCE[0]}")/debug.sh"
