#!/usr/bin/env bash

NEW_VERSION=$1
CURRENT_VERSION=$(cat charts/operaton/Chart.yaml |grep version |sed 's/version: //')

if [ -z "$1" ]; then
  echo "⚠️ You did not provide the new version. Incrementing the minor version of the current version."
  CURRENT_VERSION=$(grep '^version:' charts/operaton/Chart.yaml | sed 's/version: //')
  IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
  NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
else
  NEW_VERSION=$1
fi


echo "🔍 Current project version is $CURRENT_VERSION, updating to $NEW_VERSION"

echo "🔄 Updating version in README.md"
APP_VERSION=$(grep '^appVersion:' charts/operaton/Chart.yaml | sed 's/appVersion: //')
./update-readme.sh "$NEW_VERSION" "$APP_VERSION"

echo "🔄 Updating version in Chart.yml"
sed -i '' -e "s/^version: .*/version: $NEW_VERSION/" charts/operaton/Chart.yaml

echo "✅ Version updated to $NEW_VERSION"
