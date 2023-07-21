${__BENCHMARK_SOURCE_LIB_CORE_ARGS_SH__:=false} && return 0 || __BENCHMARK_SOURCE_LIB_CORE_ARGS_SH__=true

#######################################
# Utility function for transforming a key-value string pair in raw argument into
# a one-line JSON stirng.
# Globals:
#   None
# Arguments:
#   The key-value string seperated by comma, e.g, "a:b,c:d"
# Outputs
#   STDOUT the result, e.g., {"a": "b", "c": "d"}
# Returns
#   0
#######################################
function args::convert_key_value_pairs_to_json() {
  local key_value_pairs=$1

  # shellcheck disable=SC2016
  local awk_prog='{
      printf "{";
      for (i = 1; i <= NF; i++) {
          n = index($i, ":");
          key = substr($i, 1, n - 1);
          value = substr($i, n + 1);
          printf("\"%s\": \"%s\"", key, value);
          if (i < NF) {
              printf ", ";
          }
      }
      printf "}";
  }'

  echo "${key_value_pairs}" | awk -F, "${awk_prog}"
}