# Update Operaton Release — design

## Purpose

When the `operaton/operaton` repo publishes a **final** release (e.g.
`2.2.0`, `2.2.5`), the `operaton/operaton-helm` chart should automatically
pick up the new image version: bump the chart's own version using the
correct semver rule, update `appVersion` and the pinned image tag, and push
the change so the existing chart-testing/release pipeline publishes it.

Preliminary releases (`2.3.0-M1`, `...-RC1`) must not trigger this.

## Flow

```
operaton/release.yml (post_release job)
  └─ Notify Helm Chart Repository (new step, final releases only)
       └─ workflow_dispatch → operaton-helm/update-operaton-release.yaml
            ├─ Validate version is final
            ├─ Wait for Docker image on Docker Hub (≤45 min)
            ├─ Checkout (full history)
            ├─ Compute new chart version
            ├─ Update Chart.yaml + values.yaml
            └─ Commit & push to main
                 └─ triggers existing test-and-release.yaml
                      (lint → k8s install test → chart-releaser)
```

## 1. Changes to `operaton/operaton` (`.github/workflows/release.yml`)

Add a new step to the `post_release` job, placed immediately after the
existing **"Notify Docker Repository"** step (same job, so it fires right
after the Docker image build is kicked off — not after the image exists).

```yaml
- name: Notify Helm Chart Repository
  if: ${{github.event.inputs.dry_run == 'false' && needs.release_build.outputs.is_prerelease == 'false' }}
  env:
    HELM_ACTION_DISPATCH_TOKEN: ${{ secrets.HELM_ACTION_DISPATCH_TOKEN }}
    NEEDS_RELEASE_BUILD_OUTPUTS_VERSION: ${{ needs.release_build.outputs.version }}
  run: |
    PAYLOAD=$(jq -n --arg version "$NEEDS_RELEASE_BUILD_OUTPUTS_VERSION" \
      '{ref: "main", inputs: {operaton_version: $version}}')
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      -H "Authorization: Bearer $HELM_ACTION_DISPATCH_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -d "$PAYLOAD" \
      https://api.github.com/repos/operaton/operaton-helm/actions/workflows/update-operaton-release.yaml/dispatches)
    if [ "$response" -ne 204 ]; then
      echo "Failed to notify Helm chart repository. HTTP response code: $response"
      exit 1
    fi
```

The `is_prerelease == 'false'` condition is the "final releases only" gate
— `release_build` already computes this output, so no new version-parsing
logic is needed on the operaton side.

**Manual setup required (not part of this change):** a repo secret
`HELM_ACTION_DISPATCH_TOKEN` must be created on `operaton/operaton`,
containing a PAT with `Actions: write` permission on `operaton/operaton-helm`
— mirrors the existing `DOCKER_ACTION_DISPATCH_TOKEN`. The GitHub
`dispatches` API also only recognizes workflow files that exist on the
target repo's default branch, so the new `update-operaton-release.yaml`
workflow must be merged to `operaton-helm`'s `main` before this dispatch
step can succeed.

## 2. New workflow: `operaton-helm/.github/workflows/update-operaton-release.yaml`

```yaml
name: Update Operaton Release

on:
  workflow_dispatch:
    inputs:
      operaton_version:
        description: 'The final Operaton release version (e.g. 2.2.0 or 2.2.5)'
        required: true

jobs:
  update-release:
    name: Update Chart for Operaton Release
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Validate version is a final release
        env:
          OPERATON_VERSION: ${{ github.event.inputs.operaton_version }}
        run: |
          if ! [[ "$OPERATON_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "::error::operaton_version '$OPERATON_VERSION' is not a final release version (expected MAJOR.MINOR.PATCH)"
            exit 1
          fi

      - name: Wait for Docker image on Docker Hub
        env:
          OPERATON_VERSION: ${{ github.event.inputs.operaton_version }}
        run: |
          DEADLINE=$((SECONDS + 45 * 60))
          URL="https://hub.docker.com/v2/repositories/operaton/operaton/tags/${OPERATON_VERSION}/"
          while true; do
            STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$URL")
            if [ "$STATUS" == "200" ]; then
              echo "Docker image operaton/operaton:${OPERATON_VERSION} is available."
              break
            fi
            if [ "$SECONDS" -ge "$DEADLINE" ]; then
              echo "::error::Timed out after 45 minutes waiting for operaton/operaton:${OPERATON_VERSION} on Docker Hub"
              exit 1
            fi
            echo "Image not yet available (HTTP $STATUS), retrying in 60s..."
            sleep 60
          done

      - name: Checkout
        uses: actions/checkout@v7
        with:
          fetch-depth: 0
          persist-credentials: true

      - name: Compute new chart version
        id: version
        env:
          OPERATON_VERSION: ${{ github.event.inputs.operaton_version }}
        run: |
          CHART_FILE=charts/operaton/Chart.yaml

          CURRENT_CHART_VERSION=$(grep '^version:' "$CHART_FILE" | awk '{print $2}')
          IFS='.' read -r NEW_MAJOR NEW_MINOR NEW_PATCH <<< "$OPERATON_VERSION"

          bump_minor_reset_patch() {
            IFS='.' read -r cmaj cmin cpat <<< "$1"
            echo "${cmaj}.$((cmin + 1)).0"
          }

          if [ "$NEW_PATCH" == "0" ]; then
            NEW_CHART_VERSION=$(bump_minor_reset_patch "$CURRENT_CHART_VERSION")
            echo "Minor/major Operaton release. Chart: $CURRENT_CHART_VERSION -> $NEW_CHART_VERSION"
          else
            PREV_APP_VERSION="${NEW_MAJOR}.${NEW_MINOR}.$((NEW_PATCH - 1))"
            echo "Patch Operaton release. Looking for chart version shipped with appVersion $PREV_APP_VERSION..."
            FOUND_CHART_VERSION=""
            for COMMIT in $(git log --format=%H -- "$CHART_FILE"); do
              APP_V=$(git show "${COMMIT}:${CHART_FILE}" 2>/dev/null | grep '^appVersion:' | awk '{print $2}')
              if [ "$APP_V" == "$PREV_APP_VERSION" ]; then
                FOUND_CHART_VERSION=$(git show "${COMMIT}:${CHART_FILE}" | grep '^version:' | awk '{print $2}')
                break
              fi
            done

            if [ -n "$FOUND_CHART_VERSION" ]; then
              IFS='.' read -r fmaj fmin fpat <<< "$FOUND_CHART_VERSION"
              NEW_CHART_VERSION="${fmaj}.${fmin}.$((fpat + 1))"
              echo "Found chart $FOUND_CHART_VERSION for appVersion $PREV_APP_VERSION. Chart: -> $NEW_CHART_VERSION"
            else
              NEW_CHART_VERSION=$(bump_minor_reset_patch "$CURRENT_CHART_VERSION")
              echo "No chart version found for appVersion $PREV_APP_VERSION. Falling back to minor bump: $CURRENT_CHART_VERSION -> $NEW_CHART_VERSION"
            fi
          fi

          echo "chart_version=$NEW_CHART_VERSION" >> "$GITHUB_OUTPUT"

      - name: Update Chart.yaml and values.yaml
        env:
          OPERATON_VERSION: ${{ github.event.inputs.operaton_version }}
          NEW_CHART_VERSION: ${{ steps.version.outputs.chart_version }}
        run: |
          sed -i "s/^version: .*/version: ${NEW_CHART_VERSION}/" charts/operaton/Chart.yaml
          sed -i "s/^appVersion: .*/appVersion: ${OPERATON_VERSION}/" charts/operaton/Chart.yaml
          sed -i "s/^  tag: .*/  tag: ${OPERATON_VERSION}/" charts/operaton/values.yaml

      - name: Commit and push
        env:
          NEW_CHART_VERSION: ${{ steps.version.outputs.chart_version }}
          OPERATON_VERSION: ${{ github.event.inputs.operaton_version }}
        run: |
          git config user.name "$GITHUB_ACTOR"
          git config user.email "$GITHUB_ACTOR@users.noreply.github.com"
          git add charts/operaton/Chart.yaml charts/operaton/values.yaml
          git commit -m "release: Release chart version ${NEW_CHART_VERSION} for Operaton ${OPERATON_VERSION}"
          git push
```

### Version-bump rule (restated precisely)

- Classification is based on the **shape of the incoming Operaton version**,
  not on diffing against the chart's current `appVersion` — this correctly
  handles patch releases on older Operaton release branches even after the
  chart has already moved on to a newer minor line.
- `PATCH == 0` → minor/major release → bump current chart version's minor,
  reset patch to `0`.
- `PATCH > 0` → patch release → look up the chart version historically
  paired with `appVersion == MAJOR.MINOR.(PATCH-1)` by walking the git
  history of `Chart.yaml` (newest match wins, in case of amendments), and
  increment *that* chart version's patch component.
- If no historical match is found for the previous patch's `appVersion`,
  fall back to the minor-bump rule above.

### Known limitation

If a chart-only release happened between two Operaton patch releases and
already consumed the computed patch number, the computed chart version
could collide with an existing tag. This is not reconciled here — the
downstream `chart-releaser` step in `test-and-release.yaml` will fail
visibly on the duplicate tag, surfacing as a CI failure requiring manual
correction (bump the chart version by hand and re-push). Acceptable for v1.

### sed pattern caveat

The `values.yaml` update targets the line `  tag: ...` (two-space indent,
under `image:`). This assumes it is the only such line in the file —
true today. If `values.yaml` gains another `tag:` field at the same
indent level in the future, this step needs to switch to a YAML-aware
tool (e.g. `yq`) instead of `sed`.

## Testing plan

- Lint-check the new workflow YAML (`actionlint` or GitHub's workflow
  validation on push).
- Dry-run the version-computation step locally against the repo's actual
  git history for `Chart.yaml` (e.g. extract the `run:` block into a
  temporary script and execute with `OPERATON_VERSION` set to a few
  cases: a `.0` version, a `.N` patch version with a known prior match,
  and a patch version with no prior match) to confirm it produces the
  expected chart versions before relying on CI.
- Manually trigger `update-operaton-release.yaml` via `workflow_dispatch`
  in the GitHub UI with a real, already-published Operaton version to
  validate the Docker Hub wait step and the end-to-end commit/push path.
- Confirm the resulting push triggers `test-and-release.yaml` and that it
  lints, passes the k8s install test, and chart-releaser publishes
  successfully.
