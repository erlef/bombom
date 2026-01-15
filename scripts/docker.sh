#!/usr/bin/env bash
set -euo pipefail

# Local Docker runner for the CI build (amd64 + arm64)
# Artifacts end up in ./dist/<arch>/
#
# Usage:
#   ./scripts/docker.sh [amd64|arm64]
#   If no architecture is specified, builds both amd64 and arm64

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_ROOT="$ROOT/dist"

OTP_VERSION="${OTP_VERSION:-28.1.1}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.1}"
MUSL_VERSION="${MUSL_VERSION:-1.2.5}"

BOMBOM_REPO_URL="${BOMBOM_REPO_URL:-https://github.com/stritzinger/bombom.git}"
BOMBOM_REF="${BOMBOM_REF:-main}"
PIADINA_REPO_URL="${PIADINA_REPO_URL:-https://github.com/stritzinger/piadina.git}"
PIADINA_REF="${PIADINA_REF:-main}"

OTP_CDN_BASE_URL="${OTP_CDN_BASE_URL:-https://beam-machine-universal.b-cdn.net}"
BEAMMACHINE_HOME_URL="${BEAMMACHINE_HOME_URL:-https://beammachine.cloud/}"
REBAR3_URL="${REBAR3_URL:-https://s3.amazonaws.com/rebar3/rebar3}"

IMAGE_BASE="${IMAGE_BASE:-bombom}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need_cmd docker

docker buildx version >/dev/null 2>&1 || {
  echo "docker buildx is required (Docker Desktop usually includes it)." >&2
  exit 1
}

# Register QEMU/binfmt (needed if you run arm64 on an amd64 host)
docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null 2>&1 || true

run_one() {
  local arch="$1"
  local platform="$2"
  local image="${IMAGE_BASE}:${arch}"

  mkdir -p "$DIST_ROOT/$arch"

  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "Building image $image for platform $platform..."
    docker buildx build \
      --load \
      --platform "$platform" \
      -t "$image" \
      -f "$ROOT/scripts/Dockerfile.build-linux" \
      "$ROOT"
  else
    echo "Image $image already exists, using existing image"
  fi

  docker run --rm \
    --platform "$platform" \
    -e ARCH_IN="$arch" \
    -e OTP_VERSION="$OTP_VERSION" \
    -e OPENSSL_VERSION="$OPENSSL_VERSION" \
    -e MUSL_VERSION="$MUSL_VERSION" \
    -e OTP_CDN_BASE_URL="$OTP_CDN_BASE_URL" \
    -e BEAMMACHINE_HOME_URL="$BEAMMACHINE_HOME_URL" \
    -e REBAR3_URL="$REBAR3_URL" \
    -e BOMBOM_REPO_URL="$BOMBOM_REPO_URL" \
    -e BOMBOM_REF="$BOMBOM_REF" \
    -e PIADINA_REPO_URL="$PIADINA_REPO_URL" \
    -e PIADINA_REF="$PIADINA_REF" \
    -e APP_VER="${APP_VER:-dev-local}" \
    -v "$ROOT:/work:rw" \
    -w /work \
    "$image" \
    bash -lc '
      set -euo pipefail
      chmod +x scripts/build-linux-driver.sh
      ./scripts/build-linux-driver.sh
      echo "Artifacts:"
      ls -lh "dist/${ARCH_IN}/" || true
    '
}

main() {
  local arch="${1:-}"
  local arches=()

  case "$arch" in
    amd64|arm64) arches=("$arch") ;;
    "") arches=(amd64 arm64) ;;
    *)
      echo "ERROR: Invalid architecture '$arch'. Use 'amd64' or 'arm64'." >&2
      echo "Usage: $0 [amd64|arm64]" >&2
      exit 1
      ;;
  esac

  for a in "${arches[@]}"; do
    case "$a" in
      amd64) run_one amd64 linux/amd64 ;;
      arm64) run_one arm64 linux/arm64 ;;
    esac
  done

  echo
  echo "Done. Artifacts are under:"
  for a in "${arches[@]}"; do
    echo "  $DIST_ROOT/$a/"
  done
}

main "$@"
