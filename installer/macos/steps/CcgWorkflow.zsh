#!/usr/bin/env zsh
# CcgWorkflow.zsh - macOS CCG Workflow 安装步骤
# 功能: 执行 ccg-workflow init 并补齐受管 env 默认值

if [ -n "${CCQ_STEP_CCGWORKFLOW_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_CCGWORKFLOW_ZSH_LOADED=1

ccq_source_npm_common() {
  if command -v ccq_npm_tool_require_npx >/dev/null 2>&1; then return 0; fi
  local common_path="${CCQ_INSTALLER_ROOT:-$(cd "${0:A:h}/../.." && pwd)}/macos/steps/_NpmToolCommon.zsh"
  [ -f "${common_path}" ] && source "${common_path}"
}
ccq_source_npm_common

ccq_cg_dir() { printf '%s\n' "${HOME}/.claude"; }
ccq_cg_config_toml() { printf '%s\n' "$(ccq_cg_dir)/.ccg/config.toml"; }

ccq_cg_version() {
  local config_toml
  config_toml="$(ccq_cg_config_toml)"
  [ -f "${config_toml}" ] || return 1
  awk -F'"' '/version[[:space:]]*=/ { print $2; found=1; exit } END { if (!found) exit 1 }' "${config_toml}" 2>/dev/null || true
}

ccq_cg_env_patch() {
  cat <<'EOF'
{
  "env": {
    "CODEAGENT_POST_MESSAGE_DELAY": "1",
    "CODEX_TIMEOUT": "7200",
    "BASH_DEFAULT_TIMEOUT_MS": "600000",
    "BASH_MAX_TIMEOUT_MS": "3600000"
  }
}
EOF
}

ccq_cg_write_env_defaults() {
  local settings_path
  settings_path="$(ccq_cg_dir)/settings.json"
  ccq_json_merge_file "${settings_path}" "$(ccq_cg_env_patch)"
}

Test-CcgWorkflowInstalled() {
  local claude_dir version
  claude_dir="$(ccq_cg_dir)"
  version="$(ccq_cg_version)"
  if [ -d "${claude_dir}/commands/ccg" ] && [ -d "${claude_dir}/agents/ccg" ] && [ -d "${claude_dir}/.ccg" ]; then
    ccq_step_result true "${version:-unknown}" "CCG Workflow 已安装"
  else
    ccq_step_result false "" "CCG Workflow 未安装"
  fi
}

Install-CcgWorkflow() {
  ccq_source_npm_common
  if ! ccq_npm_tool_require_npx; then
    ccq_step_install_result false "" "${CCQ_NPM_TOOL_ERROR:-npx 不可用}"
    return 1
  fi
  local claude_dir version
  claude_dir="$(ccq_cg_dir)"
  mkdir -p "${claude_dir}"
  if ! ccq_run_command_developer_or_silent --timeout 300 --retries 3 -- npx --yes ccg-workflow@latest init --skip-prompt --skip-mcp --lang zh-CN --install-dir "${claude_dir}"; then
    ccq_step_install_result false "" "CCG Workflow 初始化失败"
    return 1
  fi
  ccq_cg_write_env_defaults >/dev/null 2>&1 || true
  version="$(ccq_cg_version)"
  ccq_step_install_result true "${version:-unknown}" ""
}

Verify-CcgWorkflow() {
  if ccq_result_is_installed "$(Test-CcgWorkflowInstalled)"; then
    printf 'Success=true\nErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\nErrorMessage=CCG Workflow 验证失败\n'
  return 1
}

Update-CcgWorkflow() {
  if Install-CcgWorkflow >/dev/null 2>&1; then
    ccq_step_update_result true "npx::ccg-workflow::latest" "$(ccq_cg_version)" ""
    return 0
  fi
  ccq_step_update_result false "" "" "CCG Workflow 更新失败"
  return 1
}
