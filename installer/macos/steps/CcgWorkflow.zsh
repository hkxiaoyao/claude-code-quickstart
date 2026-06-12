#!/usr/bin/env zsh
# CcgWorkflow.zsh - macOS CCG Workflow 安装步骤
# 功能: npx ccg-workflow init + 三分量检测（engine/rulesCleanup/envDefaults）+ MCP 快照保护

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
ccq_cg_settings_path() { printf '%s\n' "$(ccq_cg_dir)/settings.json"; }
ccq_cg_claude_json_path() { printf '%s\n' "${HOME}/.claude.json"; }
ccq_cg_rules_dir() { printf '%s\n' "$(ccq_cg_dir)/rules"; }

# ── 契约加载（contracts-first + inline fallback）──

ccq_cg_contracts_root() {
  local installer_root="${CCQ_INSTALLER_ROOT:-}"
  if [ -z "${installer_root}" ]; then
    installer_root="$(cd "${0:A:h}/../.." 2>/dev/null && pwd)"
  fi
  [ -d "${installer_root}/contracts" ] && printf '%s\n' "${installer_root}/contracts"
}

ccq_cg_contract_path() {
  if [ -n "${CCQ_CCGWORKFLOW_CONTRACT:-}" ]; then
    printf '%s\n' "${CCQ_CCGWORKFLOW_CONTRACT}"
    return 0
  fi
  local contracts_root
  contracts_root="$(ccq_cg_contracts_root)"
  [ -n "${contracts_root}" ] && printf '%s\n' "${contracts_root}/ccg-workflow.json"
}

ccq_cg_load_contract() {
  local contract_path
  contract_path="$(ccq_cg_contract_path)"
  [ -z "${contract_path}" ] || [ ! -f "${contract_path}" ] && return 1
  command -v node >/dev/null 2>&1 || return 1
  node -e '
    const fs = require("fs");
    try {
      const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      if (c && c.contract) process.stdout.write(JSON.stringify(c.contract));
      else process.exit(1);
    } catch (e) { process.exit(1); }
  ' "${contract_path}" 2>/dev/null
}

# CcgWorkflow 受管 env 默认值（仅补缺失，不覆盖用户已有配置）
ccq_cg_env_patch_fallback() {
  cat <<'EOF'
{
  "CODEAGENT_POST_MESSAGE_DELAY": "1",
  "CODEX_TIMEOUT": "7200",
  "BASH_DEFAULT_TIMEOUT_MS": "600000",
  "BASH_MAX_TIMEOUT_MS": "3600000"
}
EOF
}

ccq_cg_env_patch() {
  local contract
  contract="$(ccq_cg_load_contract 2>/dev/null)"
  if [ -n "${contract}" ] && command -v node >/dev/null 2>&1; then
    printf '%s\n' "${contract}" | node -e '
      const c = JSON.parse(require("fs").readFileSync(0, "utf8"));
      if (c.managedEnvDefaults) process.stdout.write(JSON.stringify(c.managedEnvDefaults));
      else process.exit(1);
    ' 2>/dev/null && return 0
  fi
  ccq_cg_env_patch_fallback
}

# 历史规则文件（已并入 ClaudeMd 主模板，此步骤只负责清理历史生成物）
ccq_cg_managed_rule_files_fallback() {
  printf '%s\n' "ccq-ccgworkflow.md" "ccq-multimodel.md" "ccq-tools.md" "ccq-workflow.md"
}

ccq_cg_managed_rule_files() {
  local contract
  contract="$(ccq_cg_load_contract 2>/dev/null)"
  if [ -n "${contract}" ] && command -v node >/dev/null 2>&1; then
    printf '%s\n' "${contract}" | node -e '
      const c = JSON.parse(require("fs").readFileSync(0, "utf8"));
      if (c.managedRuleFiles && Array.isArray(c.managedRuleFiles)) {
        c.managedRuleFiles.forEach(f => console.log(f));
      } else { process.exit(1); }
    ' 2>/dev/null && return 0
  fi
  ccq_cg_managed_rule_files_fallback
}

ccq_cg_version() {
  local config_toml
  config_toml="$(ccq_cg_config_toml)"
  [ -f "${config_toml}" ] || return 1
  awk -F'"' '/version[[:space:]]*=/ { print $2; found=1; exit } END { if (!found) exit 1 }' "${config_toml}" 2>/dev/null || true
}

# ─── 仅补缺失的 env 写入（不覆盖用户已有值，对齐 Windows 语义）──────────────
ccq_cg_write_env_defaults() {
  local settings_path
  settings_path="$(ccq_cg_settings_path)"
  command -v node >/dev/null 2>&1 || return 1

  local updated
  updated="$(ccq_cg_env_patch | SETTINGS_PATH="${settings_path}" node -e '
const fs = require("fs");
const defaults = JSON.parse(fs.readFileSync(0, "utf8"));
const settingsPath = process.env.SETTINGS_PATH;
let settings = {};
if (fs.existsSync(settingsPath)) {
  const raw = fs.readFileSync(settingsPath, "utf8").trim();
  if (raw) { try { settings = JSON.parse(raw); } catch (e) { process.exit(2); } }
}
if (!settings.env || typeof settings.env !== "object" || Array.isArray(settings.env)) settings.env = {};
let added = 0;
for (const [key, value] of Object.entries(defaults)) {
  if (settings.env[key] === undefined || settings.env[key] === null || String(settings.env[key]).trim() === "") {
    settings.env[key] = value;
    added++;
  }
}
if (added === 0) process.exit(10);
process.stdout.write(JSON.stringify(settings, null, 2) + "\n");
')"
  local rc=$?
  [ "${rc}" = "10" ] && return 0
  [ "${rc}" = "0" ] || return 1
  ccq_json_write_atomic "${settings_path}" "${updated}"
}

# ─── 清理历史规则文件 ───────────────────────────────────────────────────────
# 返回清理掉的文件名（每行一个），无清理则无输出
ccq_cg_cleanup_rules() {
  local rules_dir rule_file rule_path
  rules_dir="$(ccq_cg_rules_dir)"
  [ -d "${rules_dir}" ] || return 0
  for rule_file in $(ccq_cg_managed_rule_files); do
    rule_path="${rules_dir}/${rule_file}"
    if [ -f "${rule_path}" ]; then
      rm -f "${rule_path}" 2>/dev/null && printf '%s\n' "${rule_file}"
    fi
  done
}

# ─── 三分量检测：engine / rulesCleanup / envDefaults ────────────────────────
# 输出: EngineNeedUpdate / RulesNeedUpdate / EnvNeedUpdate / UpdateKind / LocalVersion（每行 key=value）
ccq_cg_update_components() {
  local local_version="" engine_need="false" rules_need="false" env_need="false"
  local rules_dir rule_file settings_path

  local_version="$(ccq_cg_version 2>/dev/null || true)"

  # 引擎分量：已安装但 config.toml 版本不可读 → 保守触发引擎更新
  if [ -z "${local_version}" ] && [ -d "$(ccq_cg_dir)/.ccg" ]; then
    engine_need="true"
  fi

  # 规则分量：存在任一历史规则文件 → 需清理
  rules_dir="$(ccq_cg_rules_dir)"
  if [ -d "${rules_dir}" ]; then
    for rule_file in $(ccq_cg_managed_rule_files); do
      if [ -f "${rules_dir}/${rule_file}" ]; then
        rules_need="true"
        break
      fi
    done
  fi

  # env 分量：受管默认值有缺失 → 需补
  settings_path="$(ccq_cg_settings_path)"
  if command -v node >/dev/null 2>&1; then
    if ccq_cg_env_patch | SETTINGS_PATH="${settings_path}" node -e '
const fs = require("fs");
const defaults = JSON.parse(fs.readFileSync(0, "utf8"));
const settingsPath = process.env.SETTINGS_PATH;
let env = {};
if (fs.existsSync(settingsPath)) {
  try { const s = JSON.parse(fs.readFileSync(settingsPath, "utf8") || "{}"); env = (s && s.env) || {}; }
  catch (e) { process.exit(0); }
}
for (const [key, value] of Object.entries(defaults)) {
  if (env[key] === undefined || env[key] === null || String(env[key]).trim() === "") process.exit(0);
}
process.exit(1);
' 2>/dev/null; then
      env_need="true"
    fi
  fi

  local update_kind="none"
  if [ "${engine_need}" = "true" ] && { [ "${rules_need}" = "true" ] || [ "${env_need}" = "true" ]; }; then
    update_kind="engine+rules"
  elif [ "${engine_need}" = "true" ]; then
    update_kind="engine-only"
  elif [ "${rules_need}" = "true" ] || [ "${env_need}" = "true" ]; then
    update_kind="rules-only"
  fi

  printf 'EngineNeedUpdate=%s\n' "${engine_need}"
  printf 'RulesNeedUpdate=%s\n' "${rules_need}"
  printf 'EnvNeedUpdate=%s\n' "${env_need}"
  printf 'UpdateKind=%s\n' "${update_kind}"
  printf 'LocalVersion=%s\n' "${local_version}"
}

# ─── MCP 快照（安装前后比对 mcpServers，检测被意外修改）──────────────────────
ccq_cg_mcp_snapshot() {
  local claude_json
  claude_json="$(ccq_cg_claude_json_path)"
  [ -f "${claude_json}" ] || { printf ''; return 0; }
  command -v node >/dev/null 2>&1 || { printf ''; return 0; }
  node -e '
const fs = require("fs");
try {
  const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8") || "{}");
  process.stdout.write(JSON.stringify(data.mcpServers || {}));
} catch (e) { process.stdout.write(""); }
' "${claude_json}" 2>/dev/null || printf ''
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
  local claude_dir version mcp_before mcp_after
  claude_dir="$(ccq_cg_dir)"
  mkdir -p "${claude_dir}"

  mcp_before="$(ccq_cg_mcp_snapshot)"

  if ! ccq_run_command_developer_or_silent --timeout 300 --retries 3 -- npx --yes ccg-workflow@latest init --skip-prompt --skip-mcp --lang zh-CN --install-dir "${claude_dir}"; then
    ccq_step_install_result false "" "CCG Workflow 初始化失败"
    return 1
  fi

  ccq_cg_cleanup_rules >/dev/null 2>&1 || true
  ccq_cg_write_env_defaults >/dev/null 2>&1 || true

  # MCP 快照比对：init 不应修改 mcpServers，若变更则告警
  mcp_after="$(ccq_cg_mcp_snapshot)"
  if [ -n "${mcp_before}" ] && [ "${mcp_before}" != "${mcp_after}" ]; then
    ccq_ui_warning "检测到 .claude.json 的 mcpServers 在 CCG 初始化过程中被修改，请手动检查" "developer"
  fi

  version="$(ccq_cg_version)"
  ccq_step_install_result true "${version:-unknown}" ""
}

Verify-CcgWorkflow() {
  local all_passed=1

  # 1. 命令模板验证
  local commands_dir="${HOME}/.claude/commands/ccg"
  local command_count=0
  if [ -d "${commands_dir}" ]; then
    command_count=$(find "${commands_dir}" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "${command_count}" -ge 20 ]; then
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - 命令模板: 已安装 ${command_count} 个 [PASS]" "developer"
  else
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - 命令模板: 仅 ${command_count} 个 (期望 >= 20) [FAIL]" "developer"
    all_passed=0
  fi

  # 2. Agent 模板验证
  local agents_dir="${HOME}/.claude/agents/ccg"
  local agent_count=0
  if [ -d "${agents_dir}" ]; then
    agent_count=$(find "${agents_dir}" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "${agent_count}" -ge 4 ]; then
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - Agent 模板: 已安装 ${agent_count} 个 [PASS]" "developer"
  else
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - Agent 模板: 仅 ${agent_count} 个 (期望 >= 4) [FAIL]" "developer"
    all_passed=0
  fi

  # 3. 配置文件验证
  local config_toml="${HOME}/.claude/.ccg/config.toml"
  if [ -f "${config_toml}" ]; then
    local pkg_version=""
    pkg_version=$(grep -E 'version\s*=\s*"[^"]+"' "${config_toml}" 2>/dev/null | sed -E 's/.*version\s*=\s*"([^"]+)".*/\1/')
    if [ -n "${pkg_version}" ]; then
      command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - 配置文件: config.toml 存在, ccg-workflow v${pkg_version} [PASS]" "developer"
    else
      command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - 配置文件: config.toml 存在 [PASS]" "developer"
    fi
  else
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - 配置文件: config.toml 不存在 [FAIL]" "developer"
    all_passed=0
  fi

  # 4. 二进制文件验证
  local wrapper_bin="${HOME}/.claude/bin/codeagent-wrapper"
  if [ -f "${wrapper_bin}" ]; then
    local wrapper_version=""
    wrapper_version=$(timeout 10 "${wrapper_bin}" --version 2>/dev/null | head -1 | tr -d '\n')
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - 二进制文件: codeagent-wrapper ${wrapper_version} [PASS]" "developer"
  else
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - 二进制文件: codeagent-wrapper 不存在 [FAIL]" "developer"
    all_passed=0
  fi

  # 5. PATH 可用性验证
  if ccq_command_exists codeagent-wrapper; then
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - PATH 可用性: codeagent-wrapper 在 PATH 中 [PASS]" "developer"
  else
    command -v ccq_ui_warning >/dev/null 2>&1 && ccq_ui_warning "  - PATH 可用性: codeagent-wrapper 不在 PATH 中 (可能需要重启终端) [SKIP]" "developer"
  fi

  # 6. CCG 环境变量验证
  local settings_path="${HOME}/.claude/settings.json"
  if [ -f "${settings_path}" ]; then
    local env_check
    env_check=$(node -e '
      const fs = require("fs");
      const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const required = ["CODEAGENT_POST_MESSAGE_DELAY", "CODEX_TIMEOUT", "BASH_DEFAULT_TIMEOUT_MS", "BASH_MAX_TIMEOUT_MS"];
      const missing = required.filter(k => !settings.env || !settings.env[k]);
      if (missing.length === 0) console.log("PASS");
      else console.log("FAIL:" + missing.join(","));
    ' "${settings_path}" 2>/dev/null || echo "FAIL:parse-error")

    if [ "${env_check}" = "PASS" ]; then
      command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - CCG 环境变量: 4 项已配置 [PASS]" "developer"
    else
      local missing="${env_check#FAIL:}"
      command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - CCG 环境变量: 缺少 ${missing} [FAIL]" "developer"
      all_passed=0
    fi
  else
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - CCG 环境变量: settings.json 不存在 [SKIP]" "developer"
  fi

  # 7. MCP 配置保护验证
  local claude_json="${HOME}/.claude.json"
  if [ -f "${claude_json}" ]; then
    if grep -q '"mcpServers"' "${claude_json}" 2>/dev/null; then
      command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - MCP 配置: 未被覆盖 [PASS]" "developer"
    else
      command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - MCP 配置: mcpServers 字段不存在 [SKIP]" "developer"
    fi
  else
    command -v ccq_ui_info >/dev/null 2>&1 && ccq_ui_info "  - MCP 配置: .claude.json 不存在 [SKIP]" "developer"
  fi

  # 最终判定
  if [ "${all_passed}" -eq 1 ]; then
    command -v ccq_ui_success >/dev/null 2>&1 && ccq_ui_success "CCG Workflow 验证通过" "developer"
    printf 'Success=true\nErrorMessage=\n'
    return 0
  else
    printf 'Success=false\nErrorMessage=CCG Workflow 部分验证项未通过，请检查上方详细信息\n'
    return 1
  fi
}

# ─── 分量级更新：仅处理需要更新的分量，避免无谓重装 ─────────────────────────
Update-CcgWorkflow() {
  local components update_kind cleaned env_items=() updated_items=()
  components="$(ccq_cg_update_components)"
  update_kind="$(ccq_result_field_from_text "${components}" UpdateKind 2>/dev/null || printf 'none')"

  case "${update_kind}" in
    none)
      ccq_step_update_result true "noop::CcgWorkflow::no-change" "$(ccq_cg_version)" ""
      return 0
      ;;
    engine-only|engine+rules)
      # 引擎需更新 → 完整重装（含 rules 清理 + env 补缺失 + MCP 快照保护）
      if Install-CcgWorkflow >/dev/null 2>&1; then
        ccq_step_update_result true "npx::ccg-workflow::latest" "$(ccq_cg_version)" ""
        return 0
      fi
      ccq_step_update_result false "" "" "CCG Workflow 引擎更新失败"
      return 1
      ;;
    rules-only)
      # 仅规则/env 更新 → 不重装引擎，只清理 rules + 补 env
      cleaned="$(ccq_cg_cleanup_rules)"
      for rule_file in ${(f)cleaned}; do
        [ -n "${rule_file}" ] && updated_items+=("rules::${rule_file}::removed")
      done
      ccq_cg_write_env_defaults >/dev/null 2>&1 && updated_items+=("env::defaults::synced")
      if [ "${#updated_items[@]}" -eq 0 ]; then
        ccq_step_update_result true "noop::CcgWorkflow::no-change" "$(ccq_cg_version)" ""
      else
        ccq_step_update_result true "$(printf '%s;' "${updated_items[@]}")" "$(ccq_cg_version)" ""
      fi
      return 0
      ;;
  esac
}
