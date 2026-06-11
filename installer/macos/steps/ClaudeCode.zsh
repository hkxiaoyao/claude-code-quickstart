#!/usr/bin/env zsh
# ClaudeCode.zsh - macOS Claude Code npm 全局安装
# 功能: 通过 npm 安装/更新 @anthropic-ai/claude-code 并验证 claude --version

if [ -n "${CCQ_STEP_CLAUDECODE_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_CLAUDECODE_ZSH_LOADED=1

: "${CCQ_CLAUDE_CODE_PACKAGE:=@anthropic-ai/claude-code}"
: "${CCQ_MIN_NODE_MAJOR:=18}"

ccq_claude_code_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'Message=%s\n' "${3:-}"
}

ccq_claude_code_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'ErrorMessage=%s\n' "${3:-}"
}

ccq_claude_code_version() {
  claude --version 2>/dev/null | head -n 1 || true
}

ccq_claude_code_node_major() {
  local version="${1:-}"
  version="${version#v}"
  printf '%s' "${version%%.*}"
}

ccq_claude_code_node_ok() {
  if ! ccq_command_exists node || ! ccq_command_exists npm; then
    return 1
  fi
  local major
  major="$(ccq_claude_code_node_major "$(node --version 2>/dev/null || true)")"
  [ -n "${major}" ] && [ "${major}" -ge "${CCQ_MIN_NODE_MAJOR}" ]
}

ccq_claude_code_command_ok() {
  ccq_command_exists claude || return 1
  claude --version >/dev/null 2>&1 || return 1
}

Test-ClaudeCodeInstalled() {
  ccq_refresh_path
  if ccq_claude_code_command_ok; then
    ccq_claude_code_result true "$(ccq_claude_code_version)" "Claude Code 已安装"
    return 0
  fi
  ccq_claude_code_result false "" "Claude Code 未安装或不可用"
}

Install-ClaudeCode() {
  ccq_refresh_path
  if ! ccq_claude_code_node_ok; then
    ccq_claude_code_install_result false "" "Node.js 或 npm 不可用，或 Node.js 版本低于 v${CCQ_MIN_NODE_MAJOR}"
    return 1
  fi

  if ! ccq_run_command_developer_or_silent --timeout 300 --retries 3 -- npm install -g "${CCQ_CLAUDE_CODE_PACKAGE}@latest"; then
    ccq_run_command --timeout 60 --retries 0 --suppress-output -- npm cache clean --force >/dev/null 2>&1 || true
    if ! ccq_run_command_developer_or_silent --timeout 300 --retries 3 -- npm install -g "${CCQ_CLAUDE_CODE_PACKAGE}@latest"; then
      ccq_claude_code_install_result false "" "npm 全局安装 Claude Code 失败"
      return 1
    fi
  fi

  ccq_refresh_path
  if ! ccq_claude_code_command_ok; then
    ccq_claude_code_install_result false "" "Claude Code 安装后仍不可用，请重新打开终端后重试"
    return 1
  fi

  ccq_claude_code_install_result true "$(ccq_claude_code_version)" ""
}

Verify-ClaudeCode() {
  ccq_refresh_path
  if ccq_claude_code_command_ok; then
    printf 'Success=true\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\n'
  printf 'ErrorMessage=Claude Code 验证失败\n'
  return 1
}

Update-ClaudeCode() {
  # noop 判断：npm 远程无新版本时跳过重装
  if command -v ccq_npm_package_has_update >/dev/null 2>&1 && \
     [ "$(ccq_npm_package_has_update '@anthropic-ai/claude-code')" = "false" ]; then
    printf 'Success=true\n'
    printf 'UpdatedItems=noop::ClaudeCode::up-to-date\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  if Install-ClaudeCode >/dev/null 2>&1; then
    printf 'Success=true\n'
    printf 'UpdatedItems=npm::claude-code::latest\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\n'
  printf 'UpdatedItems=\n'
  printf 'ErrorMessage=Claude Code 更新失败\n'
  return 1
}
