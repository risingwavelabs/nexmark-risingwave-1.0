#!/usr/bin/env bash

# === DEPENDENCIES ===
# yq
#
# === USAGE ===
# ./extract_queries <query-toml> <output-dir-path>
#
# === EXAMPLE ===
#
# ```
# runcmd() { ./scripts/extract-queries.sh manifests/nexmark/nexmark-sinks.template.yaml tmp; }
# runcmd
# ```

set -euo pipefail

function usage() {
  echo "Usage: $0 <query-yaml> <output-dir-path>" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 64
fi

QUERY_FILE=$1
OUTPUT_DIR=$2

if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required" >&2
  exit 127
fi

if [[ ! -r "${QUERY_FILE}" ]]; then
  echo "Query file is not readable: ${QUERY_FILE}" >&2
  exit 66
fi

mkdir -p "${OUTPUT_DIR}"

QUERIES="$(yq '.data | keys' <"$QUERY_FILE" | sed 's/^- //')"

for QUERY in $QUERIES; do
  OUTPATH="$OUTPUT_DIR/$QUERY"
  echo "$OUTPATH"
  QUOTED_QUERY="\"$QUERY\""
  QUERY_SQL="$(QUERY=$QUOTED_QUERY yq '.data | .[env(QUERY)]' <"$QUERY_FILE")"
  echo "$QUERY_SQL" > "$OUTPATH"
done
