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

QUERIES="$(cat $QUERY_FILE | yq '.data | keys' | sed 's/^- //')"

for QUERY in $QUERIES
do
  OUTPATH="$OUTPUT_DIR/$QUERY"
  echo $OUTPATH
  QUOTED_QUERY="\"$QUERY\""
  QUERY_SQL="$(cat $QUERY_FILE \
  | QUERY=$QUOTED_QUERY yq '.data | .[env(QUERY)]')"
  echo "$QUERY_SQL" > $OUTPATH
done
