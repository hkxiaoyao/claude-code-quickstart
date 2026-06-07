#!/usr/bin/env zsh
# CodexCli.zsh - macOS Codex CLI npm 全局安装
# 功能: 安装/更新 @openai/codex 并验证 codex 命令

if [ -n "${CCQ_STEP_CODEXCLI_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_CODEXCLI_ZSH_LOADED=1

: "${CCQ_CODEX_PACKAGE:=@openai/codex}"

ccq_source_npm_common() {
  if command -v ccq_npm_tool_require_npm >/dev/null 2>&1; then return 0; fi
  local common_path="${CCQ_INSTALLER_ROOT:-$(cd "${0:A:h}/../.." && pwd)}/macos/steps/_NpmToolCommon.zsh"
  [ -f "${common_path}" ] && source "${common_path}"
}
ccq_source_npm_common

ccq_codex_version() {
  local version
  version="$(ccq_npm_tool_version_from_command codex 2>/dev/null || true)"
  [ -n "${version}" ] && { printf '%s\n' "${version}"; return 0; }
  ccq_npm_tool_version_from_npm_list "${CCQ_CODEX_PACKAGE}" 2>/dev/null || true
}

Test-CodexCliInstalled() {
  ccq_source_npm_common
  if ccq_npm_tool_command_installed codex; then
    ccq_step_result true "$(ccq_codex_version)" "Codex CLI 已安装"
  else
    ccq_step_result false "" "Codex CLI 未安装"
  fi
}

Install-CodexCli() {
  ccq_source_npm_common
  if ! ccq_npm_tool_install_latest "${CCQ_CODEX_PACKAGE}"; then
    ccq_step_install_result false "" "${CCQ_NPM_TOOL_ERROR:-Codex CLI 安装失败}"
    return 1
  fi
  if ! ccq_npm_tool_command_installed codex; then
    ccq_step_install_result false "" "Codex CLI 安装后仍不可用"
    return 1
  fi
  ccq_step_install_result true "$(ccq_codex_version)" ""
}

Verify-CodexCli() {
  if ccq_npm_tool_command_installed codex; then
    printf 'Success=true\nErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\nErrorMessage=Codex CLI 验证失败\n'
  return 1
}

Update-CodexCli() {
  if Install-CodexCli >/dev/null 2>&1; then
    ccq_step_update_result true "npm::codex-cli::latest" "$(ccq_codex_version)" ""
    return 0
  fi
  ccq_step_update_result false "" "" "Codex CLI 更新失败"
  return 1
}
