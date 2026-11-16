#!/usr/bin/env bash
# Updates the chart and app versions shown in the README.md examples.
# Usage: ./update-readme.sh CHART_VERSION APP_VERSION

set -euo pipefail

CHART_VERSION=${1:?chart version required}
APP_VERSION=${2:?app version required}
README=README.md

# Keep the column alignment of the example command outputs
SEARCH_ROW=$(printf '%-24s%-16s%-16s%s' "operaton/operaton" "$CHART_VERSION" "$APP_VERSION" "Helm chart for Operaton")
LIST_CHART=$(printf '%-32s%s' "operaton-$CHART_VERSION" "$APP_VERSION")

sed -E \
  -e "s#^operaton/operaton .*Helm chart for Operaton\$#${SEARCH_ROW}#" \
  -e "s#--version [0-9][0-9A-Za-z.+-]*#--version ${CHART_VERSION}#g" \
  -e "s#The version \`[^\`]*\` will be used#The version \`${CHART_VERSION}\` will be used#" \
  -e "s#operaton-[0-9][0-9A-Za-z.+-]* +[^ ]+\$#${LIST_CHART}#" \
  "$README" > "$README.tmp"
mv "$README.tmp" "$README"
