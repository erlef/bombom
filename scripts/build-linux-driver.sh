#!/usr/bin/env bash
set -euo pipefail

# Shared build driver used by BOTH:
# - GitHub Actions workflow (.github/workflows/build-linux.yml)
# - Local Docker runner (scripts/docker.sh), including arm64 emulation
#
# Responsibilities:
# - Map ARCH_IN -> BM_ARCH / OUT_ARCH / NEEDLE_ARCH
# - Build OTP_TARBALL_URL
# - Resolve MUSL_SO_URL
# - Ensure rebar3 exists
# - Derive OUTPUT + APP_VER
# - Run scripts/build-linux.sh
# - Normalize artifacts into dist/<arch>/
#
# Inputs (env):
#   ARCH_IN            (required)  "amd64" | "arm64"
#   OTP_VERSION        (required)  e.g. "28.1.1"
#
# Optional inputs (env):
#   OPENSSL_VERSION    default "3.5.1"
#   MUSL_VERSION       default "1.2.5"
#   OTP_CDN_BASE_URL   default "https://beam-machine-universal.b-cdn.net"
#   BEAMMACHINE_HOME_URL default "https://beammachine.cloud/"
#   REBAR3_URL         default "https://s3.amazonaws.com/rebar3/rebar3"
#
#   BOMBOM_REPO_URL / BOMBOM_REF / PIADINA_REPO_URL / PIADINA_REF
#   OUTPUT             (optional) if you want to override output filename
#   APP_VER            (optional) if you want to override version label

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

# shellcheck source=./build-config.sh
source "$ROOT/scripts/build-config.sh"

ARCH_IN="${ARCH_IN:-}"
OTP_VERSION="${OTP_VERSION:-}"

[[ -n "$ARCH_IN" ]] || die "ARCH_IN is required (amd64|arm64)"
[[ -n "$OTP_VERSION" ]] || die "OTP_VERSION is required"

OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.1}"
MUSL_VERSION="${MUSL_VERSION:-1.2.5}"

OTP_CDN_BASE_URL="${OTP_CDN_BASE_URL:-https://beam-machine-universal.b-cdn.net}"
BEAMMACHINE_HOME_URL="${BEAMMACHINE_HOME_URL:-https://beammachine.cloud/}"
REBAR3_URL="${REBAR3_URL:-https://s3.amazonaws.com/rebar3/rebar3}"

# Map architecture (sets BM_ARCH / OUT_ARCH / NEEDLE_ARCH)
map_architecture "$ARCH_IN"

# Derive URLs unless provided
OTP_TARBALL_URL="${OTP_TARBALL_URL:-$(build_otp_tarball_url "$OTP_VERSION" "$BM_ARCH" "$OPENSSL_VERSION" "$MUSL_VERSION" "$OTP_CDN_BASE_URL")}"

if [[ -z "${MUSL_SO_URL:-}" ]]; then
  MUSL_SO_URL="$(resolve_musl_runtime_url "$BEAMMACHINE_HOME_URL" "$NEEDLE_ARCH")"
fi

# Derive OUTPUT unless provided
OUTPUT="${OUTPUT:-$(build_output_filename "$OUT_ARCH")}"

# Derive APP_VER unless provided
if [[ -z "${APP_VER:-}" ]]; then
  if [[ "${GITHUB_REF_TYPE:-}" == "tag" && -n "${GITHUB_REF_NAME:-}" ]]; then
    APP_VER="$GITHUB_REF_NAME"
  elif [[ -n "${GITHUB_SHA:-}" ]]; then
    APP_VER="dev-${GITHUB_SHA:0:7}"
  else
    APP_VER="dev-local"
  fi
fi

ensure_rebar3() {
  if command -v rebar3 >/dev/null 2>&1; then
    log "rebar3 already present: $(command -v rebar3)"
    rebar3 --version || true
    return 0
  fi

  log "Installing rebar3 from $REBAR3_URL"
  local tmp
  tmp="$(mktemp -d)"
  curl -fL --retry 3 --retry-delay 2 --retry-all-errors --max-time 180 \
    "$REBAR3_URL" -o "$tmp/rebar3"
  chmod +x "$tmp/rebar3"

  # Install to /usr/local/bin (use sudo only if needed)
  if [[ -w /usr/local/bin ]]; then
    install -m 0755 "$tmp/rebar3" /usr/local/bin/rebar3
  else
    command -v sudo >/dev/null 2>&1 || die "Need sudo to install rebar3, but sudo not available"
    sudo install -m 0755 "$tmp/rebar3" /usr/local/bin/rebar3
  fi

  rebar3 --version || true
  rm -rf "$tmp"
}

ensure_rebar3

# Export for build-linux.sh
export ARCH_IN OTP_VERSION OPENSSL_VERSION MUSL_VERSION
export OTP_CDN_BASE_URL BEAMMACHINE_HOME_URL REBAR3_URL
export BM_ARCH OUT_ARCH NEEDLE_ARCH
export OTP_TARBALL_URL MUSL_SO_URL OUTPUT APP_VER

# If running in GitHub Actions, publish key outputs for later steps
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "ARCH_IN=$ARCH_IN"
    echo "OUTPUT=$OUTPUT"
    echo "APP_VER=$APP_VER"
    echo "OTP_TARBALL_URL=$OTP_TARBALL_URL"
    echo "MUSL_SO_URL=$MUSL_SO_URL"
    echo "NEEDLE_ARCH=$NEEDLE_ARCH"
    echo "OUT_ARCH=$OUT_ARCH"
  } >> "$GITHUB_ENV"
fi

log "Build inputs:"
log "  ARCH_IN=$ARCH_IN (BM_ARCH=$BM_ARCH OUT_ARCH=$OUT_ARCH NEEDLE_ARCH=$NEEDLE_ARCH)"
log "  OTP_VERSION=$OTP_VERSION"
log "  OUTPUT=$OUTPUT"
log "  APP_VER=$APP_VER"

chmod +x "$ROOT/scripts/build-linux.sh"
"$ROOT/scripts/build-linux.sh"

# Normalize artifacts to dist/<arch>/
mkdir -p "$ROOT/dist/$ARCH_IN"

if [[ -f "$ROOT/dist/$OUTPUT" ]]; then
  mv -f "$ROOT/dist/$OUTPUT" "$ROOT/dist/$ARCH_IN/$OUTPUT"
fi
if [[ -f "$ROOT/dist/$OUTPUT.sha256" ]]; then
  mv -f "$ROOT/dist/$OUTPUT.sha256" "$ROOT/dist/$ARCH_IN/$OUTPUT.sha256"
fi

log "Artifacts:"
ls -lh "$ROOT/dist/$ARCH_IN" || true
