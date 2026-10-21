# Update Operaton Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `operaton/operaton` publishes a final release, automatically bump the `operaton-helm` chart's version (using the correct semver rule) and point it at the new Operaton image, then push so the existing release pipeline publishes it.

**Architecture:** A new `workflow_dispatch`-triggered GitHub Actions workflow in `operaton-helm` (`update-operaton-release.yaml`) waits for the Docker image, computes the next chart version from git history, edits `Chart.yaml`/`values.yaml`, and pushes to `main`. A new step in `operaton/operaton`'s `release.yml` (`post_release` job) fires that workflow via the GitHub REST dispatch API, gated to final releases only.

**Tech Stack:** GitHub Actions (YAML), bash, `git`, `curl`, Docker Hub public API.

**Spec:** `docs/superpowers/specs/2026-10-21-update-operaton-release-design.md`

## Global Constraints

- Dispatch gate (operaton side): fire only when `dry_run == 'false' && needs.release_build.outputs.is_prerelease == 'false'`.
- New workflow's file name must be exactly `update-operaton-release.yaml` — the dispatch URL path references it literally.
- Docker Hub wait: poll every 60s, hard timeout 45 minutes, target `https://hub.docker.com/v2/repositories/operaton/operaton/tags/<version>/`.
- Version classification is based on the **shape of the incoming version** (`PATCH == 0` vs `PATCH > 0`), never by diffing against the chart's current `appVersion`.
- Patch-release lookup: walk `git log` over `charts/operaton/Chart.yaml`, newest match wins, to find the chart version historically paired with `appVersion == MAJOR.MINOR.(PATCH-1)`; increment *that* chart version's patch. No match → fall back to bumping the current chart version's minor (patch reset to 0).
- Exact commit message on the operaton-helm side: `release: Release chart version <chartversion> for Operaton <operatonversion>`.
- `values.yaml`'s `image.tag` line is matched by `^  tag: .*` (two-space indent) — this assumes it's the only such line today; do not generalize this to a YAML-aware tool as part of this plan (noted as a future caveat only).
- New secret `HELM_ACTION_DISPATCH_TOKEN` on `operaton/operaton` is a manual, out-of-band setup step — no code in this plan creates it.
- The local `operaton` checkout's `origin` remote is a fork (`cachescrubber/operaton`), not upstream `operaton/operaton`. **Do not push Task 2's commit anywhere.** Leave it local; the user decides how it reaches upstream (PR from their own fork, or direct push if they have write access to `operaton/operaton`).

---

## File Structure

- Create: `operaton-helm/.github/workflows/update-operaton-release.yaml` — the new workflow; self-contained, no new script files (matches this repo's existing convention of inline `run:` blocks).
- Modify: `operaton/.github/workflows/release.yml` — one new step in the existing `post_release` job.

No other files change. Both deliverables are independent: Task 1 produces a working, independently-dispatchable workflow; Task 2 produces a working caller. Either can be merged/tested before the other, though Task 1 must land on `operaton-helm`'s `main` before Task 2's dispatch call can succeed (the GitHub dispatch API only sees workflows present on the target's default branch) — captured in Task 3's rollout checklist.

---

### Task 1: `update-operaton-release.yaml` workflow (operaton-helm repo)

**Files:**
- Create: `.github/workflows/update-operaton-release.yaml`

**Interfaces:**
- Consumes: `workflow_dispatch` input `operaton_version` (string, e.g. `"2.2.5"`), provided by whoever dispatches it (Task 2, or a manual trigger).
- Produces: a commit on `main` titled `release: Release chart version <chartversion> for Operaton <operatonversion>`, which `test-and-release.yaml` (existing, unmodified) picks up via its `push: branches: [main]` trigger.

This task's only non-trivial logic is the chart-version computation (branching + a git-history loop). We prove that logic first against disposable fixtures, then transplant the exact proven bash into the workflow file.

- [ ] **Step 1: Write the fixture-based test for the version-computation logic**

Create `/private/tmp/claude-502/-Users-kthoms-Development-git-operaton-operaton-helm/24d17ba0-1ea5-4189-a629-b43bfc89fcff/scratchpad/test-compute-version.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

git -C "$FIXTURE_DIR" init -q -b main
git -C "$FIXTURE_DIR" config user.email "test@example.com"
git -C "$FIXTURE_DIR" config user.name "Test"

write_chart() {
  cat > "$FIXTURE_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: fixture
version: $1
appVersion: $2
EOF
  git -C "$FIXTURE_DIR" add Chart.yaml
  git -C "$FIXTURE_DIR" commit -q -m "chart $1 / app $2"
}

write_chart 1.0.1 2.1.0
write_chart 1.0.2 2.1.1
write_chart 1.1.0 2.2.0   # HEAD: current chart version 1.1.0, appVersion 2.2.0

run_compute() {
  (cd "$FIXTURE_DIR" && OPERATON_VERSION="$1" CHART_FILE=Chart.yaml bash "$SCRIPT_UNDER_TEST")
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    echo "FAIL: $3 — expected '$2', got '$1'"
    exit 1
  fi
  echo "PASS: $3 -> $1"
}

# Case A: minor/major release (PATCH == 0) -> bump current chart's minor, reset patch
RESULT=$(run_compute "2.3.0")
assert_eq "$RESULT" "1.2.0" "minor-release path"

# Case B: patch release, previous patch's chart version found (2.1.1 -> chart 1.0.2)
RESULT=$(run_compute "2.1.2")
assert_eq "$RESULT" "1.0.3" "patch-release path (match found)"

# Case C: patch release, previous patch's chart version NOT found -> fallback to minor bump
RESULT=$(run_compute "9.9.9")
assert_eq "$RESULT" "1.2.0" "patch-release path (fallback)"

echo "All assertions passed."
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
chmod +x /private/tmp/claude-502/-Users-kthoms-Development-git-operaton-operaton-helm/24d17ba0-1ea5-4189-a629-b43bfc89fcff/scratchpad/test-compute-version.sh
SCRIPT_UNDER_TEST=/private/tmp/claude-502/-Users-kthoms-Development-git-operaton-operaton-helm/24d17ba0-1ea5-4189-a629-b43bfc89fcff/scratchpad/compute-version.sh \
  /private/tmp/claude-502/-Users-kthoms-Development-git-operaton-operaton-helm/24d17ba0-1ea5-4189-a629-b43bfc89fcff/scratchpad/test-compute-version.sh
```

Expected: fails because `compute-version.sh` doesn't exist yet (`bash: .../compute-version.sh: No such file or directory`).

- [ ] **Step 3: Write the version-computation logic under test**

Create `/private/tmp/claude-502/-Users-kthoms-Development-git-operaton-operaton-helm/24d17ba0-1ea5-4189-a629-b43bfc89fcff/scratchpad/compute-version.sh`:

```bash
CURRENT_CHART_VERSION=$(grep '^version:' "$CHART_FILE" | awk '{print $2}')
IFS='.' read -r NEW_MAJOR NEW_MINOR NEW_PATCH <<< "$OPERATON_VERSION"

bump_minor_reset_patch() {
  IFS='.' read -r cmaj cmin cpat <<< "$1"
  echo "${cmaj}.$((cmin + 1)).0"
}

if [ "$NEW_PATCH" == "0" ]; then
  NEW_CHART_VERSION=$(bump_minor_reset_patch "$CURRENT_CHART_VERSION")
else
  PREV_APP_VERSION="${NEW_MAJOR}.${NEW_MINOR}.$((NEW_PATCH - 1))"
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
  else
    NEW_CHART_VERSION=$(bump_minor_reset_patch "$CURRENT_CHART_VERSION")
  fi
fi

echo "$NEW_CHART_VERSION"
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
SCRIPT_UNDER_TEST=/private/tmp/claude-502/-Users-kthoms-Development-git-operaton-operaton-helm/24d17ba0-1ea5-4189-a629-b43bfc89fcff/scratchpad/compute-version.sh \
  /private/tmp/claude-502/-Users-kthoms-Development-git-operaton-operaton-helm/24d17ba0-1ea5-4189-a629-b43bfc89fcff/scratchpad/test-compute-version.sh
```

Expected: all three `PASS:` lines, then `All assertions passed.`. If a case fails, fix `compute-version.sh` (not the test) and rerun until it passes — the three cases in Step 1 are the spec's contract, not negotiable.

- [ ] **Step 5: Write the real workflow file, inlining the proven logic**

Create `.github/workflows/update-operaton-release.yaml`:

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
          CHART_FILE: charts/operaton/Chart.yaml
        run: |
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

- [ ] **Step 6: Validate the workflow file is well-formed YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/update-operaton-release.yaml'))" && echo "YAML OK"
```

Expected: `YAML OK` with no exception.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/update-operaton-release.yaml
git commit -m "feat: add Update Operaton Release workflow"
```

---

### Task 2: Notify-Helm step in `operaton/operaton`'s `release.yml`

**Files:**
- Modify: `/Users/kthoms/Development/git/operaton/operaton/.github/workflows/release.yml` (`post_release` job — currently lines 335-416 as last read; insert after the "Notify Docker Repository" step, which ends right before the job's "Check out the code" step)

**Interfaces:**
- Consumes: `needs.release_build.outputs.version` and `needs.release_build.outputs.is_prerelease` (already produced by the existing `release_build` job — no change needed there), plus a new repo secret `HELM_ACTION_DISPATCH_TOKEN` (manual setup, see Task 3).
- Produces: a `workflow_dispatch` POST to `https://api.github.com/repos/operaton/operaton-helm/actions/workflows/update-operaton-release.yaml/dispatches` with body `{"ref": "main", "inputs": {"operaton_version": "<version>"}}` — this is exactly the input contract Task 1's workflow expects.

Since this step is a near-identical sibling of the existing "Notify Docker Repository" step (same job, same gating style, same curl-dispatch pattern), there's no separate logic to unit-test — correctness is "does it parse as valid YAML and match the existing step's shape." Verification is therefore YAML validation plus a manual review diff, not a bash test harness.

- [ ] **Step 1: Insert the new step**

In `/Users/kthoms/Development/git/operaton/operaton/.github/workflows/release.yml`, find:

```yaml
      - name: Notify Docker Repository
        if: ${{github.event.inputs.dry_run == 'false' }}
        env:
          DOCKER_ACTION_DISPATCH_TOKEN: ${{ secrets.DOCKER_ACTION_DISPATCH_TOKEN }}
          NEEDS_RELEASE_BUILD_OUTPUTS_VERSION: ${{ needs.release_build.outputs.version}}
        run: |
          PAYLOAD=$(jq -n --arg version "$NEEDS_RELEASE_BUILD_OUTPUTS_VERSION" \
            '{ref: "main", inputs: {version: $version, snapshot: "false"}}')
          response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Authorization: Bearer $DOCKER_ACTION_DISPATCH_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -d "$PAYLOAD" \
            https://api.github.com/repos/operaton/operaton-docker/actions/workflows/build-test-and-publish.yml/dispatches)
          if [ "$response" -ne 204 ]; then
            echo "Failed to notify Docker repository. HTTP response code: $response"
            exit 1
          fi

      - name: Check out the code
```

Replace it with (inserting the new step between the two, keeping both originals intact):

```yaml
      - name: Notify Docker Repository
        if: ${{github.event.inputs.dry_run == 'false' }}
        env:
          DOCKER_ACTION_DISPATCH_TOKEN: ${{ secrets.DOCKER_ACTION_DISPATCH_TOKEN }}
          NEEDS_RELEASE_BUILD_OUTPUTS_VERSION: ${{ needs.release_build.outputs.version}}
        run: |
          PAYLOAD=$(jq -n --arg version "$NEEDS_RELEASE_BUILD_OUTPUTS_VERSION" \
            '{ref: "main", inputs: {version: $version, snapshot: "false"}}')
          response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
            -H "Authorization: Bearer $DOCKER_ACTION_DISPATCH_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -d "$PAYLOAD" \
            https://api.github.com/repos/operaton/operaton-docker/actions/workflows/build-test-and-publish.yml/dispatches)
          if [ "$response" -ne 204 ]; then
            echo "Failed to notify Docker repository. HTTP response code: $response"
            exit 1
          fi

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

      - name: Check out the code
```

- [ ] **Step 2: Validate YAML syntax**

```bash
cd /Users/kthoms/Development/git/operaton/operaton
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML OK"
```

Expected: `YAML OK` with no exception.

- [ ] **Step 3: Commit locally — do not push**

```bash
cd /Users/kthoms/Development/git/operaton/operaton
git add .github/workflows/release.yml
git commit -m "feat(release): notify operaton-helm to update the chart on final releases"
```

**Stop here.** This checkout's `origin` remote is `cachescrubber/operaton`, a fork — not `operaton/operaton` upstream. Do not `git push`. Tell the user the commit is ready locally and ask how they want it to reach upstream (open a PR from their own fork/remote, or push directly if they have write access to `operaton/operaton`).

---

### Task 3: Manual rollout checklist

Not code — operational steps that must happen outside this repo's git history, in the stated order, before the automation is live. Present this to the user as a checklist; do not attempt to perform these automatically.

**Files:** none.

- [ ] **Step 1: Merge Task 1 to `operaton-helm`'s `main` first**

The GitHub Actions `dispatches` API only triggers workflows that already exist on the target repository's default branch. `update-operaton-release.yaml` must be merged to `operaton-helm`'s `main` before Task 2's dispatch call can succeed.

- [ ] **Step 2: Create the `HELM_ACTION_DISPATCH_TOKEN` secret**

In `operaton/operaton`'s repo settings, add a secret named `HELM_ACTION_DISPATCH_TOKEN` containing a PAT (classic PAT with `repo` scope, or fine-grained PAT with `Actions: write` permission) that has write access to `operaton/operaton-helm`. Mirrors the existing `DOCKER_ACTION_DISPATCH_TOKEN`.

- [ ] **Step 3: Merge/land Task 2 on `operaton/operaton`**

Once Steps 1–2 are done, get the local commit from Task 2 into `operaton/operaton`'s `main` (PR or direct push, per the user's access).

- [ ] **Step 4: End-to-end smoke test**

Manually trigger `update-operaton-release.yaml` via `workflow_dispatch` in the GitHub UI (or `gh workflow run`) on `operaton-helm`, passing a real, already-published final Operaton version as `operaton_version`. Confirm:
- the Docker Hub wait step passes quickly (image already exists),
- the computed chart version matches expectations for that version's patch/minor shape,
- `Chart.yaml` and `values.yaml` are updated and pushed with the exact commit message format,
- the push triggers `test-and-release.yaml` and it completes (lint → k8s install test → chart-releaser publish).

- [ ] **Step 5: Verify the real trigger chain**

Wait for (or trigger a dry-run of) the next final Operaton release and confirm `release.yml`'s `post_release` job actually fires the dispatch and the chain completes unattended.

---

## Self-Review Notes

- **Spec coverage:** trigger gate (Task 2), Docker Hub wait with 45-min timeout (Task 1 Step 5), checkout (Task 1 Step 5), major/minor vs patch chart-version logic including fallback (Task 1 Steps 1-5, tested), `values.yaml` tag sync (Task 1 Step 5 "Update Chart.yaml and values.yaml"), exact commit message (Task 1 Step 5, Global Constraints), fork-remote caveat (Task 2 Step 3), manual secret/merge-order prerequisites (Task 3) — all covered.
- **Placeholder scan:** none found; all `run:` blocks are complete, runnable bash.
- **Type/name consistency:** `chart_version` output name matches between Task 1's computation step and its consuming "Update Chart.yaml and values.yaml" / "Commit and push" steps; `operaton_version` input name matches between Task 1's `workflow_dispatch` input and Task 2's dispatch payload key.
