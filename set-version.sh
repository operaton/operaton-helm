#!/usr/bin/env bash

NEW_VERSION=$1
CURRENT_VERSION=$(cat charts/operaton-bpm/Chart.yaml |grep version |sed 's/version: //')

if [ -z "$1" ]; then
  echo "⚠️ You did not provide the new version. Incrementing the minor version of the current version."
  CURRENT_VERSION=$(grep '^version:' charts/operaton-bpm/Chart.yaml | sed 's/version: //')
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
else
  NEW_VERSION=$1
fi


echo "🔍 Current project version is $CURRENT_VERSION, updating to $NEW_VERSION"

echo "🔄 Updating version in README.md"
sed -e "s/{{ CHART_VERSION }}/$NEW_VERSION/g" README.tpl.md > README.md
exit 1


echo "🔄 Updating version in Chart.yml"
sed -i '' -e "s/^version: .*/version: $NEW_VERSION/" charts/operaton-bpm/Chart.yaml

echo "✅ Version updated to $NEW_VERSION"
