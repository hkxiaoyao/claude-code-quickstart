#!/usr/bin/env zsh
# Platform.zsh - macOS 平台能力检测
# 功能: macOS 版本、架构、zsh、HOME、PATH 分隔符和可执行解析能力检测

if [ -n "${CCQ_PLATFORM_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_PLATFORM_ZSH_LOADED=1

ccq_is_macos() {
  [ "$(uname -s 2>/dev/null)" = "Darwin" ]
}

ccq_macos_version() {
  sw_vers -productVersion 2>/dev/null || true
}

ccq_version_major() {
  local version="${1:-}"
  printf '%s' "${version%%.*}"
}

ccq_compare_versions_ge() {
  local actual="${1:-0}"
  local required="${2:-0}"
  local actual_major required_major
  actual_major="$(ccq_version_major "${actual}")"
  required_major="$(ccq_version_major "${required}")"
  [ "${actual_major:-0}" -ge "${required_major:-0}" ]
}

ccq_assert_macos_supported() {
  local min_version="${1:-12}"
  if ! ccq_is_macos; then
    CCQ_LAST_PLATFORM_ERROR="当前系统不是 macOS"
    return 1
  fi
  local version
  version="$(ccq_macos_version)"
  if [ -z "${version}" ] || ! ccq_compare_versions_ge "${version}" "${min_version}"; then
    CCQ_LAST_PLATFORM_ERROR="macOS 版本过低: ${version:-unknown}，需要 ${min_version}+"
    return 1
  fi
  return 0
}

ccq_arch() {
  uname -m 2>/dev/null || true
}

ccq_is_apple_silicon() {
  [ "$(ccq_arch)" = "arm64" ]
}

ccq_default_brew_prefix() {
  if ccq_is_apple_silicon; then
    printf '%s\n' '/opt/homebrew'
  else
    printf '%s\n' '/usr/local'
  fi
}

ccq_current_shell() {
  printf '%s\n' "${SHELL:-}"
}

ccq_is_zsh_shell() {
  case "$(basename "${SHELL:-}")" in
    zsh) return 0 ;;
    *) return 1 ;;
  esac
}

ccq_home_dir() {
  printf '%s\n' "${HOME}"
}

ccq_path_separator() {
  printf ':'
}

ccq_executable_suffix() {
  printf ''
}

ccq_resolve_executable() {
  command -v "$1" 2>/dev/null || true
}

ccq_platform_summary() {
  printf 'os=macOS\n'
  printf 'version=%s\n' "$(ccq_macos_version)"
  printf 'arch=%s\n' "$(ccq_arch)"
  printf 'shell=%s\n' "$(ccq_current_shell)"
  printf 'home=%s\n' "$(ccq_home_dir)"
  printf 'pathSeparator=:\n'
  printf 'executableSuffix=\n'
}
