#!/usr/bin/env zsh
# Ccline.zsh - macOS CCometixLine 安装步骤
# 功能: 安装 @cometix/ccline、写入 statusLine、定位 Claude Code cli.js 并执行 patch

if [ -n "${CCQ_STEP_CCLINE_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_CCLINE_ZSH_LOADED=1

: "${CCQ_CCLINE_PACKAGE:=@cometix/ccline}"

ccq_source_npm_common() {
  if command -v ccq_npm_tool_require_npm >/dev/null 2>&1; then return 0; fi
  local common_path="${CCQ_INSTALLER_ROOT:-$(cd "${0:A:h}/../.." && pwd)}/macos/steps/_NpmToolCommon.zsh"
  [ -f "${common_path}" ] && source "${common_path}"
}
ccq_source_npm_common

ccq_ccline_settings_path() { printf '%s\n' "${HOME}/.claude/settings.json"; }

ccq_ccline_version() {
  ccq_npm_tool_version_from_command ccline 2>/dev/null || true
}

ccq_ccline_statusline_ok() {
  local settings_path
  settings_path="$(ccq_ccline_settings_path)"
  [ -f "${settings_path}" ] || return 1
  [ "$(ccq_json_get "${settings_path}" "statusLine.type" 2>/dev/null || true)" = "command" ] || return 1
  [ "$(ccq_json_get "${settings_path}" "statusLine.command" 2>/dev/null || true)" = "ccline" ]
}

ccq_ccline_write_statusline() {
  local settings_path patch
  settings_path="$(ccq_ccline_settings_path)"
  patch='{"statusLine":{"type":"command","command":"ccline","padding":0}}'
  ccq_json_merge_file "${settings_path}" "${patch}"
}

ccq_ccline_claude_cli_path() {
  local npm_root cli_path
  ccq_npm_tool_require_npm || return 1
  npm_root="$(npm root -g 2>/dev/null | head -n 1 || true)"
  [ -n "${npm_root}" ] || return 1
  cli_path="${npm_root}/@anthropic-ai/claude-code/cli.js"
  [ -f "${cli_path}" ] || return 1
  printf '%s\n' "${cli_path}"
}

ccq_ccline_patch() {
  local cli_path
  ccq_command_exists ccline || return 1
  cli_path="$(ccq_ccline_claude_cli_path 2>/dev/null || true)"
  [ -n "${cli_path}" ] || return 1
  ccq_run_command --timeout 30 --retries 0 --suppress-output -- ccline --patch "${cli_path}" >/dev/null 2>&1
}

Test-CclineInstalled() {
  ccq_source_npm_common
  if ccq_npm_tool_command_installed ccline && ccq_ccline_statusline_ok; then
    ccq_step_result true "$(ccq_ccline_version)" "CCometixLine 已安装并配置 statusLine"
  else
    ccq_step_result false "$(ccq_ccline_version)" "CCometixLine 未安装或 statusLine 未配置"
  fi
}

Install-Ccline() {
  ccq_source_npm_common
  if ! ccq_command_exists claude; then
    ccq_step_install_result false "" "Claude Code 不可用，请先完成 ClaudeCode 步骤"
    return 1
  fi
  if ! ccq_npm_tool_install_latest "${CCQ_CCLINE_PACKAGE}"; then
    ccq_step_install_result false "" "${CCQ_NPM_TOOL_ERROR:-CCometixLine 安装失败}"
    return 1
  fi
  if ! ccq_npm_tool_command_installed ccline; then
    ccq_step_install_result false "" "ccline 安装后仍不可用"
    return 1
  fi
  if ! ccq_ccline_write_statusline; then
    ccq_step_install_result false "$(ccq_ccline_version)" "statusLine 写入失败"
    return 1
  fi
  ccq_ccline_patch >/dev/null 2>&1 || true
  ccq_step_install_result true "$(ccq_ccline_version)" ""
}

Verify-Ccline() {
  if ccq_npm_tool_command_installed ccline && ccq_ccline_statusline_ok; then
    printf 'Success=true\nErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\nErrorMessage=CCometixLine 验证失败\n'
  return 1
}

Update-Ccline() {
  if Install-Ccline >/dev/null 2>&1; then
    ccq_step_update_result true "npm::ccline::latest" "$(ccq_ccline_version)" ""
    return 0
  fi
  ccq_step_update_result false "" "" "CCometixLine 更新失败"
  return 1
}
