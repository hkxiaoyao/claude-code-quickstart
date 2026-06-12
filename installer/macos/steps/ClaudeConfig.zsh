#!/usr/bin/env zsh
# ClaudeConfig.zsh - macOS Claude Code 常用配置步骤
# 功能: 按 contracts ClaudeConfig 契约补齐受管配置并保护用户自定义字段

if [ -n "${CCQ_STEP_CLAUDECONFIG_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_CLAUDECONFIG_ZSH_LOADED=1

: "${CCQ_CLAUDE_CONFIG_CONTRACT:=${CCQ_CONTRACTS_DIR:-${CCQ_INSTALLER_ROOT}/contracts}/claude-config.json}"

ccq_claude_settings_path() { printf '%s\n' "${HOME}/.claude/settings.json"; }

ccq_claude_config_drift_script_path() {
  printf '%s\n' "${CCQ_CONTRACTS_DIR:-${CCQ_INSTALLER_ROOT}/contracts}/scripts/claude-config-drift.js"
}

ccq_claude_config_contract_ready() {
  command -v node >/dev/null 2>&1 || return 1
  [ -f "${CCQ_CLAUDE_CONFIG_CONTRACT}" ] || return 1
}

ccq_claude_config_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=\n'
  printf 'Message=%s\n' "${2:-}"
}

ccq_claude_config_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'ErrorMessage=%s\n' "${2:-}"
  if [ -n "${3:-}" ]; then
    printf 'UpdatedItems=%s\n' "${3}"
  fi
}

ccq_claude_config_analyze_json() {
  local settings_path script_path
  settings_path="$(ccq_claude_settings_path)"
  script_path="$(ccq_claude_config_drift_script_path)"

  ccq_claude_config_contract_ready || return 1
  [ -f "${script_path}" ] || return 1

  node "${script_path}" --contract-path "${CCQ_CLAUDE_CONFIG_CONTRACT}" --settings-path "${settings_path}" --mode analyze
}

ccq_claude_config_compare_drift() {
  ccq_claude_config_analyze_json
}

ccq_claude_config_apply() {
  local mode="${1:-install}"
  local settings_path script_path result_json new_settings updated_items
  settings_path="$(ccq_claude_settings_path)"
  script_path="$(ccq_claude_config_drift_script_path)"

  ccq_claude_config_contract_ready || return 1
  [ -f "${script_path}" ] || return 1

  result_json="$(node "${script_path}" --contract-path "${CCQ_CLAUDE_CONFIG_CONTRACT}" --settings-path "${settings_path}" --mode "${mode}" 2>/dev/null)" || return 1

  # 提取 newSettings 并写入
  new_settings="$(printf '%s' "${result_json}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(JSON.stringify(v.applied.newSettings, null, 2));' 2>/dev/null)" || return 1
  ccq_json_write_atomic "${settings_path}" "${new_settings}" || return 1

  # 提取 updatedItems
  updated_items="$(printf '%s' "${result_json}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write((v.applied.updatedItems || []).join(";"));' 2>/dev/null)" || updated_items="noop::ClaudeConfig::no-change"
  CCQ_CLAUDE_CONFIG_UPDATED_ITEMS="${updated_items}"
}

Test-ClaudeConfigInstalled() {
  local analysis needs_install parse_error
  analysis="$(ccq_claude_config_analyze_json 2>/dev/null || true)"
  if [ -z "${analysis}" ]; then
    ccq_claude_config_result false "ClaudeConfig 契约或 Node.js 不可用"
    return 0
  fi
  parse_error="$(printf '%s' "${analysis}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.details.parseError || "");' 2>/dev/null || true)"
  if [ -n "${parse_error}" ]; then
    ccq_claude_config_result false "settings.json 无法解析"
    return 0
  fi
  needs_install="$(printf '%s' "${analysis}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.needsInstallCompletion ? "true" : "false");' 2>/dev/null || printf 'true')"
  if [ "${needs_install}" = "false" ]; then
    ccq_claude_config_result true "Claude Code 常用配置已安装"
  else
    ccq_claude_config_result false "Claude Code 常用配置未完整安装"
  fi
}

Install-ClaudeConfig() {
  if ! ccq_claude_config_apply install; then
    ccq_claude_config_install_result false "ClaudeConfig 写入失败" ""
    return 1
  fi
  ccq_claude_config_install_result true "" "${CCQ_CLAUDE_CONFIG_UPDATED_ITEMS:-noop::ClaudeConfig::no-change}"
}

Verify-ClaudeConfig() {
  local analysis needs_install
  analysis="$(ccq_claude_config_analyze_json 2>/dev/null || true)"
  needs_install="$(printf '%s' "${analysis}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.needsInstallCompletion ? "true" : "false");' 2>/dev/null || printf 'true')"
  if [ "${needs_install}" = "false" ]; then
    printf 'Success=true\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\n'
  printf 'ErrorMessage=ClaudeConfig 验证失败\n'
  return 1
}

Update-ClaudeConfig() {
  if ! ccq_claude_config_apply update; then
    ccq_claude_config_install_result false "ClaudeConfig 更新失败" ""
    return 1
  fi
  ccq_claude_config_install_result true "" "${CCQ_CLAUDE_CONFIG_UPDATED_ITEMS:-noop::ClaudeConfig::no-change}"
}
