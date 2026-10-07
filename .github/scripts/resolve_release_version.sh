#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PUBSPEC_PATH="${ROOT_DIR}/pubspec.yaml"
OUTPUT_FILE="${GITHUB_OUTPUT:-}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: resolve_release_version.sh [--dry-run] [--github-output PATH] [--pubspec PATH]

Resolves the release version and Android versionCode:
- Reads base version from pubspec.yaml (e.g. 1.0.0).
- If v${BASE_VERSION} does not exist, uses v${BASE_VERSION}.
- If v${BASE_VERSION} exists, increments fix counter (v${BASE_VERSION}_fix1, etc).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --github-output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --pubspec)
      PUBSPEC_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${PUBSPEC_PATH}" ]]; then
  echo "pubspec not found: ${PUBSPEC_PATH}" >&2
  exit 1
fi

BASE_VERSION="$(
  sed -n -E 's/^[[:space:]]*version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?[[:space:]]*\r?$/\1/p' "${PUBSPEC_PATH}" \
    | head -n 1
)"

if [[ -z "${BASE_VERSION}" ]]; then
  echo "Unable to read base semver from ${PUBSPEC_PATH}" >&2
  exit 1
fi

git -C "${ROOT_DIR}" fetch --tags --force >/dev/null 2>&1 || true

# Check if base tag v1.0.0 exists
if ! git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/v${BASE_VERSION}" >/dev/null 2>&1; then
  RELEASE_VERSION="${BASE_VERSION}"
  RELEASE_TAG="v${BASE_VERSION}"
  NEXT_FIX=0
else
  LATEST_FIX="$(
    git -C "${ROOT_DIR}" tag --list "v${BASE_VERSION}_fix*" \
      | sed -n -E "s/^v${BASE_VERSION//./\\.}_fix([0-9]+)$/\\1/p" \
      | sort -n \
      | tail -n 1
  )"

  if [[ -z "${LATEST_FIX}" ]]; then
    NEXT_FIX=1
  else
    NEXT_FIX=$((LATEST_FIX + 1))
  fi

  RELEASE_VERSION="${BASE_VERSION}_fix${NEXT_FIX}"
  RELEASE_TAG="v${RELEASE_VERSION}"
fi

IFS='.' read -r MAJOR MINOR PATCH <<<"${BASE_VERSION}"
BASE_CODE=$((MAJOR * 1000000 + MINOR * 1000 + PATCH))
ANDROID_VERSION_CODE=$((BASE_CODE * 100 + NEXT_FIX))
ANDROID_VERSION_CODE_LIMIT=2100000000
if (( ANDROID_VERSION_CODE <= 0 || ANDROID_VERSION_CODE > ANDROID_VERSION_CODE_LIMIT )); then
  echo "Computed Android versionCode ${ANDROID_VERSION_CODE} exceeds supported range." >&2
  exit 1
fi

if [[ -n "${OUTPUT_FILE}" ]]; then
  {
    echo "release_version=${RELEASE_VERSION}"
    echo "release_tag=${RELEASE_TAG}"
    echo "android_version_code=${ANDROID_VERSION_CODE}"
  } >> "${OUTPUT_FILE}"
fi

echo "release_version=${RELEASE_VERSION}"
echo "release_tag=${RELEASE_TAG}"
echo "android_version_code=${ANDROID_VERSION_CODE}"

if (( DRY_RUN == 1 )); then
  echo "Resolved in dry-run mode."
fi
