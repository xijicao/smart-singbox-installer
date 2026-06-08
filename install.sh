#!/usr/bin/env sh
set -eu

# Change this after uploading the folder to GitHub.
REPO_RAW_BASE_DEFAULT="https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main"
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
  url="${REPO_RAW_BASE}/${src}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" -o "${dst}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${dst}" "${url}"
  else
    die "curl or wget is required to fetch installer files."
  fi
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
  echo "Choose what to install:"
  echo "  1) DMIT entry machine"
  echo "  2) HK entry machine"
  echo "  3) Home/landing machine - SS2022 only"
  echo "  4) Home/landing machine - Reality + SS2022"
  echo
}

read_choice() {
  if [ -r /dev/tty ]; then
    print_menu > /dev/tty
    printf "Enter choice: " > /dev/tty
    read -r choice < /dev/tty
  else
    die "No interactive TTY found. Please run this one-command installer from an interactive SSH terminal."
  fi
}

choose_profile() {
  if [ -n "${PROFILE:-}" ]; then
    PROFILE_ID="${PROFILE}"
  else
    read_choice
    case "${choice}" in
      1)
        [ "${OS_FAMILY}" = "debian" ] || die "DMIT entry machine requires Debian/Ubuntu. Current OS: ${OS_ID}."
        PROFILE_ID="dmit-debian"
        ;;
      2)
        [ "${OS_FAMILY}" = "debian" ] || die "HK entry machine requires Debian/Ubuntu. Current OS: ${OS_ID}."
        PROFILE_ID="hk-debian"
        ;;
      3)
        case "${OS_FAMILY}" in
          debian) PROFILE_ID="home-debian" ;;
          alpine) PROFILE_ID="home-alpine" ;;
          *) die "Home/landing machine requires Debian/Ubuntu/Alpine. Current OS: ${OS_ID}." ;;
        esac
        HOME_MODE="${HOME_MODE:-ss2022}"
        ;;
      4)
        case "${OS_FAMILY}" in
          debian) PROFILE_ID="home-debian" ;;
          alpine) PROFILE_ID="home-alpine" ;;
          *) die "Home/landing machine requires Debian/Ubuntu/Alpine. Current OS: ${OS_ID}." ;;
        esac
        HOME_MODE="${HOME_MODE:-both}"
        ;;
      *) die "Invalid choice: ${choice}" ;;
    esac
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
