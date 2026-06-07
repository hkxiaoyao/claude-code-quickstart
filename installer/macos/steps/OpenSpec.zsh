#!/usr/bin/env zsh
# OpenSpec.zsh - macOS OpenSpec CLI npm 全局安装
# 功能: 安装/更新 @fission-ai/openspec 并验证 openspec 命令

if [ -n "${CCQ_STEP_OPENSPEC_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_OPENSPEC_ZSH_LOADED=1

: "${CCQ_OPENSPEC_PACKAGE:=@fission-ai/openspec}"

ccq_source_npm_common() {
  if command -v ccq_npm_tool_require_npm >/dev/null 2>&1; then return 0; fi
  local common_path="${CCQ_INSTALLER_ROOT:-$(cd "${0:A:h}/../.." && pwd)}/macos/steps/_NpmToolCommon.zsh"
  [ -f "${common_path}" ] && source "${common_path}"
}
ccq_source_npm_common

ccq_openspec_version() {
  local version
  version="$(ccq_npm_tool_version_from_npm_list "${CCQ_OPENSPEC_PACKAGE}" 2>/dev/null || true)"
  [ -n "${version}" ] && { printf '%s\n' "${version}"; return 0; }
  ccq_npm_tool_version_from_command openspec 2>/dev/null || true
}

Test-OpenSpecInstalled() {
  ccq_source_npm_common
  local version
  version="$(ccq_openspec_version)"
  if [ -n "${version}" ]; then
    ccq_step_result true "${version}" "OpenSpec CLI 已安装"
  else
    ccq_step_result false "" "OpenSpec CLI 未安装"
  fi
}

Install-OpenSpec() {
  ccq_source_npm_common
  if ! ccq_npm_tool_install_latest "${CCQ_OPENSPEC_PACKAGE}"; then
    ccq_step_install_result false "" "${CCQ_NPM_TOOL_ERROR:-OpenSpec CLI 安装失败}"
    return 1
  fi
  local version
  version="$(ccq_openspec_version)"
  [ -n "${version}" ] || { ccq_step_install_result false "" "OpenSpec CLI 安装后验证失败"; return 1; }
  ccq_step_install_result true "${version}" ""
}

Verify-OpenSpec() {
  local version
  version="$(ccq_openspec_version)"
  if [ -n "${version}" ]; then
    printf 'Success=true\nErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\nErrorMessage=OpenSpec CLI 验证失败\n'
  return 1
}

Update-OpenSpec() {
  if Install-OpenSpec >/dev/null 2>&1; then
    ccq_step_update_result true "npm::openspec-cli::latest" "$(ccq_openspec_version)" ""
    return 0
  fi
  ccq_step_update_result false "" "" "OpenSpec CLI 更新失败"
  return 1
}
