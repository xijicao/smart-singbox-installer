#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_file() {
  [ -f "${ROOT_DIR}/$1" ] || fail "Missing file: $1"
}

need_file "install.sh"
need_file "lib/common.sh"
need_file "profiles/dmit-debian.sh"
need_file "profiles/hk-debian.sh"
need_file "profiles/home-debian.sh"
need_file "profiles/home-alpine.sh"
need_file "README.md"
need_file "README-快速命令.md"
need_file "GITHUB-部署步骤.md"
need_file "VERSION"
need_file "tools/self-check.sh"
need_file ".github/workflows/self-check.yml"

if command -v sh >/dev/null 2>&1; then
  sh -n "${ROOT_DIR}/install.sh"
  sh -n "${ROOT_DIR}/lib/common.sh"
  sh -n "${ROOT_DIR}/profiles/dmit-debian.sh"
  sh -n "${ROOT_DIR}/profiles/hk-debian.sh"
  sh -n "${ROOT_DIR}/profiles/home-debian.sh"
  sh -n "${ROOT_DIR}/profiles/home-alpine.sh"
fi

if command -v grep >/dev/null 2>&1; then
  if grep -R "rotate-reality\|全量轮换 Reality\|SNI/key for all Reality" \
    "${ROOT_DIR}/install.sh" \
    "${ROOT_DIR}/lib" \
    "${ROOT_DIR}/profiles" \
    "${ROOT_DIR}/README.md" \
    "${ROOT_DIR}/README-快速命令.md" \
    "${ROOT_DIR}/GITHUB-部署步骤.md" \
    "${ROOT_DIR}/思维导图.md" \
    "${ROOT_DIR}/详细架构树状图.svg" \
    "${ROOT_DIR}/架构树状图.svg" \
    "${ROOT_DIR}/VERSION"; then
    fail "Deprecated Reality rotation text found."
  fi

  if grep -R "192\.0\.2\.10\|b7jzs1CyjWrmj65VEuKwh65G1llu2pprkElq6DmDD2s=" \
    "${ROOT_DIR}/install.sh" \
    "${ROOT_DIR}/lib" \
    "${ROOT_DIR}/profiles" \
    "${ROOT_DIR}/README.md" \
    "${ROOT_DIR}/README-快速命令.md" \
    "${ROOT_DIR}/GITHUB-部署步骤.md"; then
    fail "Example secret/IP leaked into active files."
  fi
fi

printf '%s\n' "self-check passed"
