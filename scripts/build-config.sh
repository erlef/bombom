#!/usr/bin/env bash
# Shared build configuration functions
# This script is designed to be sourced, not executed directly

# Maps input architecture to BM_ARCH, OUT_ARCH, and NEEDLE_ARCH
# Usage: map_architecture <arch_in>
# Sets: BM_ARCH, OUT_ARCH, NEEDLE_ARCH
map_architecture() {
  local arch_in="$1"
  case "$arch_in" in
    amd64)
      BM_ARCH="x86_64"
      OUT_ARCH="amd64"
      NEEDLE_ARCH="x86_64"
      ;;
    arm64)
      BM_ARCH="aarch64"
      OUT_ARCH="arm64"
      NEEDLE_ARCH="aarch64"
      ;;
    *)
      echo "Unsupported arch: $arch_in (use amd64 or arm64)" >&2
      exit 1
      ;;
  esac
}

# Builds the OTP tarball URL from parameters
# Usage: build_otp_tarball_url <otp_version> <bm_arch> <openssl_version> <musl_version> <otp_cdn_base_url>
# Output: URL string (should be captured or assigned)
build_otp_tarball_url() {
  local otp="$1"
  local bm_arch="$2"
  local openssl="$3"
  local muslver="$4"
  local otp_base="$5"
  echo "${otp_base}/OTP-${otp}/linux/${bm_arch}/any/otp_${otp}_linux_any_${bm_arch}.tar.gz?openssl=${openssl}&musl=${muslver}"
}

# Resolves the musl runtime URL by scraping the beammachine page
# Usage: resolve_musl_runtime_url <beammachine_home_url> <needle_arch>
# Output: URL string (should be captured or assigned)
# Exits with non-zero status if URL cannot be found or validated
resolve_musl_runtime_url() {
  local home_url="$1"
  local needle_arch="$2"
  
  # Determine the directory where this script is located
  # Since this script is sourced, use BASH_SOURCE[0] to get the script path
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local python_script="${script_dir}/resolve-musl-runtime.py"
  
  # Verify Python script exists
  if [[ ! -f "$python_script" ]]; then
    echo "Python script not found: $python_script" >&2
    exit 1
  fi
  
  # Fetch the HTML page
  local html
  html=$(curl -fsSL --max-time 20 --retry 3 --retry-delay 2 --retry-all-errors "$home_url") || {
    echo "Failed to fetch beammachine home page: $home_url" >&2
    exit 1
  }
  
  # Export variables for Python script
  export HOME_URL="$home_url"
  export NEEDLE_ARCH="$needle_arch"
  
  # Run Python script to find the musl runtime URL
  # Pass HTML via stdin and HOME_URL/NEEDLE_ARCH via environment variables
  local musl_url
  musl_url=$(echo "$html" | python3 "$python_script") || {
    echo "Could not find musl runtime URL for arch: $needle_arch" >&2
    exit 1
  }
  
  # Validate URL is reachable
  curl -fsSI --max-time 20 "$musl_url" >/dev/null || {
    echo "musl runtime URL not reachable: $musl_url" >&2
    exit 1
  }
  
  echo "$musl_url"
}

# Builds the output filename from architecture
# Usage: build_output_filename <out_arch>
# Output: filename string (should be captured or assigned)
build_output_filename() {
  local out_arch="$1"
  echo "bombom-linux-${out_arch}.bin"
}
