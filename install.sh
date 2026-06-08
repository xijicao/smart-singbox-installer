#!/usr/bin/env sh
set -eu

# Change this after uploading the folder to GitHub.
REPO_RAW_BASE_DEFAULT="https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main"
REPO_RAW_BASE="${REPO_RAW_BASE:-${REPO_RAW_BASE_DEFAULT}}"

TMP_DIR=""

cleanup() {
  if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
    rm -rf "${TMP_DIR}"
  fi
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "Please run as root."
  fi
}

detect_os_id() {
  if [ ! -r /etc/os-release ]; then
    die "Cannot read /etc/os-release."
  fi

  OS_ID="$(. /etc/os-release && printf '%s' "${ID}")"
  case "${OS_ID}" in
    debian|ubuntu)
      OS_FAMILY="debian"
      ;;
    alpine)
      OS_FAMILY="alpine"
      ;;
    *)
      die "Unsupported OS: ${OS_ID}. Supported: Debian/Ubuntu/Alpine."
      ;;
  esac
}

fetch_file() {
  src="$1"
  dst="$2"
  curl -fsSL "${REPO_RAW_BASE}/${src}" -o "${dst}"
}

prepare_bundle() {
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P || printf '.')"

  if [ -r "${SCRIPT_DIR}/lib/common.sh" ] && [ -d "${SCRIPT_DIR}/profiles" ]; then
    BUNDLE_DIR="${SCRIPT_DIR}"
    return
  fi

  case "${REPO_RAW_BASE}" in
    *YOUR_GITHUB_USERNAME*|*YOUR_REPO_NAME*)
      die "Please edit REPO_RAW_BASE_DEFAULT in install.sh, or run with REPO_RAW_BASE=https://raw.githubusercontent.com/user/repo/main"
      ;;
  esac

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT INT TERM
  mkdir -p "${TMP_DIR}/lib" "${TMP_DIR}/profiles"
  BUNDLE_DIR="${TMP_DIR}"

  fetch_file "lib/common.sh" "${BUNDLE_DIR}/lib/common.sh"
  fetch_file "profiles/dmit-debian.sh" "${BUNDLE_DIR}/profiles/dmit-debian.sh"
  fetch_file "profiles/hk-debian.sh" "${BUNDLE_DIR}/profiles/hk-debian.sh"
  fetch_file "profiles/home-debian.sh" "${BUNDLE_DIR}/profiles/home-debian.sh"
  fetch_file "profiles/home-alpine.sh" "${BUNDLE_DIR}/profiles/home-alpine.sh"
}

print_menu() {
  echo
  echo "Detected OS: ${OS_ID} (${OS_FAMILY})"
  echo "Choose profile:"

  if [ "${OS_FAMILY}" = "debian" ]; then
    echo "  1) dmit-debian    DMIT main Reality entry + ss:// relay importer"
    echo "  2) hk-debian      HK main Reality entry + ss:// relay importer"
    echo "  3) home-debian    landing/transit machine: ss2022/reality/both"
  else
    echo "  1) home-alpine    landing/transit machine: ss2022/reality/both"
  fi
  echo
}

read_choice() {
  if [ -r /dev/tty ]; then
    print_menu > /dev/tty
    printf "Enter choice: " > /dev/tty
    read -r choice < /dev/tty
  else
    die "No interactive TTY found. Please set PROFILE=..."
  fi
}

choose_profile() {
  if [ -n "${PROFILE:-}" ]; then
    PROFILE_ID="${PROFILE}"
  else
    read_choice
    if [ "${OS_FAMILY}" = "debian" ]; then
      case "${choice}" in
        1) PROFILE_ID="dmit-debian" ;;
        2) PROFILE_ID="hk-debian" ;;
        3) PROFILE_ID="home-debian" ;;
        *) die "Invalid choice: ${choice}" ;;
      esac
    else
      case "${choice}" in
        1) PROFILE_ID="home-alpine" ;;
        *) die "Invalid choice: ${choice}" ;;
      esac
    fi
  fi

  case "${PROFILE_ID}" in
    dmit-debian|hk-debian|home-debian)
      [ "${OS_FAMILY}" = "debian" ] || die "${PROFILE_ID} requires Debian/Ubuntu."
      ;;
    home-alpine)
      [ "${OS_FAMILY}" = "alpine" ] || die "${PROFILE_ID} requires Alpine."
      ;;
    *)
      die "Unknown profile: ${PROFILE_ID}"
      ;;
  esac
}

main() {
  need_root
  detect_os_id
  prepare_bundle
  choose_profile

  . "${BUNDLE_DIR}/lib/common.sh"
  . "${BUNDLE_DIR}/profiles/${PROFILE_ID}.sh"

  echo
  echo "Installing profile: ${PROFILE_ID}"
  profile_main
}

main "$@"