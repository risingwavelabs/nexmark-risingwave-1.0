# Provide utilities for debugging.
${__BENCHMARK_SOURCE_LIB_BENCHMARK_DEBUG_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_BENCHMARK_DEBUG_SH__=true

#######################################
# Enable all debug options.
# Globals
#   BENCHMARK_TRACE_COMMAND
#   BENCHMARK_SHOW_COMMAND_OUTPUT
#   BENCHMARK_LOG_LEVEL
# Arguments
#   None
# Return
#   0
#######################################
# shellcheck disable=SC2034
function benchmark::debug::enable() {
  BENCHMARK_TRACE_COMMAND=true
  BENCHMARK_SHOW_COMMAND_OUTPUT=true
  BENCHMARK_LOG_LEVEL=debug
}
