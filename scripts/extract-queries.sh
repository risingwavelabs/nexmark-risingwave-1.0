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

QUERY_FILE=$1
OUTPUT_DIR=$2

QUERIES="$(yq '.data | keys' <"$QUERY_FILE" | sed 's/^- //')"

for QUERY in $QUERIES
do
  OUTPATH="$OUTPUT_DIR/$QUERY"
  echo "$OUTPATH"
  QUOTED_QUERY="\"$QUERY\""
  QUERY_SQL="$(QUERY=$QUOTED_QUERY yq '.data | .[env(QUERY)]' <"$QUERY_FILE")"
  echo "$QUERY_SQL" > "$OUTPATH"
done
