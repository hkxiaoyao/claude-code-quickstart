#!/usr/bin/env zsh
# AntigravityCli.zsh - macOS Antigravity CLI 安装步骤
# 功能: 通过官方 install.sh 安装、检测、验证和更新 agy

if [ -n "${CCQ_STEP_ANTIGRAVITYCLI_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_ANTIGRAVITYCLI_ZSH_LOADED=1

: "${CCQ_ANTIGRAVITY_INSTALL_URL:=https://antigravity.google/cli/install.sh}"
: "${CCQ_ANTIGRAVITY_BIN:=${HOME}/.local/bin/agy}"

ccq_antigravity_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'Message=%s\n' "${3:-}"
}

ccq_antigravity_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'ErrorMessage=%s\n' "${3:-}"
  if [ -n "${4:-}" ]; then
    printf 'Status=%s\n' "${4}"
  fi
}

ccq_antigravity_update_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'UpdatedItems=%s\n' "${2:-}"
  printf 'Version=%s\n' "${3:-}"
  printf 'ErrorMessage=%s\n' "${4:-}"
  if [ -n "${5:-}" ]; then
    printf 'Status=%s\n' "${5}"
  fi
}

ccq_antigravity_version() {
  ccq_refresh_path
  if ! ccq_command_exists agy; then
    if [ -x "${CCQ_ANTIGRAVITY_BIN}" ]; then
      "${CCQ_ANTIGRAVITY_BIN}" --version 2>/dev/null | head -n 1 || true
      return 0
    fi
    return 1
  fi
  agy --version 2>/dev/null | head -n 1 || true
}

ccq_antigravity_path_hint() {
  cat <<'EOF'
Antigravity CLI macOS/Linux 官方安装路径为 ~/.local/bin/agy。
若安装后命令不可用，请确保 PATH 包含：
  export PATH="$HOME/.local/bin:$PATH"
EOF
}

ccq_antigravity_manual_hint() {
  cat <<'EOF'
Antigravity CLI macOS 官方安装命令：
  curl -fsSL https://antigravity.google/cli/install.sh | bash
安装后验证：
  command -v agy
  agy --version
EOF
}

ccq_antigravity_ensure_local_bin_path() {
  case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) PATH="${HOME}/.local/bin:${PATH}" ;;
  esac
  export PATH
}

ccq_antigravity_run_installer() {
  if ! ccq_command_exists curl; then
    CCQ_ANTIGRAVITY_ERROR="curl 不可用，无法下载 Antigravity CLI 官方安装脚本"
    return 1
  fi

  local installer_path
  installer_path="$(mktemp "${TMPDIR:-/tmp}/ccq-antigravity-install.XXXXXX")" || return 1
  if ! curl -fsSL "${CCQ_ANTIGRAVITY_INSTALL_URL}" -o "${installer_path}"; then
    rm -f "${installer_path}"
    CCQ_ANTIGRAVITY_ERROR="下载 Antigravity CLI 官方安装脚本失败"
    return 1
  fi

  if ! ccq_run_native_command bash "${installer_path}"; then
    rm -f "${installer_path}"
    CCQ_ANTIGRAVITY_ERROR="Antigravity CLI 官方安装脚本执行失败"
    return 1
  fi
  rm -f "${installer_path}"
  ccq_antigravity_ensure_local_bin_path
}

Test-AntigravityCliInstalled() {
  local version
  version="$(ccq_antigravity_version 2>/dev/null || true)"
  if [ -n "${version}" ]; then
    ccq_antigravity_result true "${version}" "Antigravity CLI 已安装"
    return 0
  fi
  ccq_antigravity_result false "" "Antigravity CLI 未安装"
}

Install-AntigravityCli() {
  if ! ccq_antigravity_run_installer; then
    ccq_antigravity_manual_hint >&2
    ccq_antigravity_install_result false "" "${CCQ_ANTIGRAVITY_ERROR:-Antigravity CLI 安装失败，请按手动指引处理}" "ManualRequired"
    return 1
  fi

  local version
  version="$(ccq_antigravity_version 2>/dev/null || true)"
  if [ -z "${version}" ]; then
    ccq_antigravity_path_hint >&2
    ccq_antigravity_install_result false "" "安装完成但未检测到 agy，请检查 ~/.local/bin 是否在 PATH 中" "ManualRequired"
    return 1
  fi

  ccq_antigravity_install_result true "${version}" ""
}

Verify-AntigravityCli() {
  local version
  version="$(ccq_antigravity_version 2>/dev/null || true)"
  if [ -n "${version}" ]; then
    printf 'Success=true\nErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\nErrorMessage=Antigravity CLI 验证失败\n'
  return 1
}

Update-AntigravityCli() {
  local old_version new_version item
  old_version="$(ccq_antigravity_version 2>/dev/null || true)"

  if ccq_command_exists agy; then
    ccq_run_native_command agy update || true
  fi

  if ! ccq_antigravity_run_installer; then
    ccq_antigravity_manual_hint >&2
    ccq_antigravity_update_result false "" "${old_version}" "${CCQ_ANTIGRAVITY_ERROR:-Antigravity CLI 更新失败，请按手动指引处理}" "ManualRequired"
    return 1
  fi

  new_version="$(ccq_antigravity_version 2>/dev/null || true)"
  if [ -z "${new_version}" ]; then
    ccq_antigravity_path_hint >&2
    ccq_antigravity_update_result false "" "" "更新后未检测到 agy，请检查 PATH" "ManualRequired"
    return 1
  fi

  if [ -n "${old_version}" ] && [ "${old_version}" != "${new_version}" ]; then
    item="agy::antigravity-cli::${old_version}->${new_version}"
  elif [ -z "${old_version}" ]; then
    item="agy::antigravity-cli::installed"
  else
    item="noop::AntigravityCli::no-change"
  fi

  ccq_antigravity_update_result true "${item}" "${new_version}" ""
}
