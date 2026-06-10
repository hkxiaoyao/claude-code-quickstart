#!/usr/bin/env zsh
# Mcp.zsh - macOS MCP Server 配置步骤
# 功能: 写入 .claude.json MCP 配置并复用 ~/.ccq/mcp-meta.json vault schema

if [ -n "${CCQ_STEP_MCP_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_MCP_ZSH_LOADED=1

: "${CCQ_MCP_CONTRACT:=${CCQ_CONTRACTS_DIR:-${CCQ_INSTALLER_ROOT}/contracts}/mcp-servers.json}"

ccq_mcp_claude_json_path() { printf '%s\n' "${HOME}/.claude.json"; }
ccq_mcp_settings_path() { printf '%s\n' "${HOME}/.claude/settings.json"; }
ccq_mcp_meta_path() { printf '%s\n' "${HOME}/.ccq/mcp-meta.json"; }

ccq_mcp_contract_ready() {
  command -v node >/dev/null 2>&1 || return 1
  [ -f "${CCQ_MCP_CONTRACT}" ] || return 1
}

ccq_mcp_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=\n'
  printf 'Message=%s\n' "${2:-}"
}

ccq_mcp_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'ConfiguredServers=%s\n' "${2:-0}"
  printf 'ErrorMessage=%s\n' "${3:-}"
}

ccq_mcp_tty() { [ -r /dev/tty ] && [ -w /dev/tty ]; }

ccq_mcp_prompt_text() {
  local prompt="${1:-请输入}"
  local value=""
  ccq_mcp_tty || return 1
  printf '%s: ' "${prompt}" >/dev/tty
  IFS= read -r value </dev/tty || return 1
  printf '%s' "${value}"
}

ccq_mcp_prompt_secret() {
  local prompt="${1:-凭据}"
  local value=""
  ccq_mcp_tty || return 1
  printf '%s: ' "${prompt}" >/dev/tty
  IFS= read -r -s value </dev/tty || return 1
  printf '\n' >/dev/tty
  printf '%s' "${value}"
}

ccq_mcp_recommended_ids() {
  ccq_mcp_contract_ready || return 1
  node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const servers = c.McpServers || {};
Object.entries(servers)
  .filter(([, server]) => server.Recommended)
  .sort((a, b) => (a[1].Priority || 9999) - (b[1].Priority || 9999))
  .forEach(([id]) => console.log(id));
' "${CCQ_MCP_CONTRACT}"
}

ccq_mcp_all_lines() {
  ccq_mcp_contract_ready || return 1
  node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const servers = c.McpServers || {};
Object.entries(servers)
  .sort((a, b) => (a[1].Priority || 9999) - (b[1].Priority || 9999))
  .forEach(([id, server]) => console.log([id, server.Name || id, server.Description || "", server.Recommended ? "recommended" : "optional"].join("\t")));
' "${CCQ_MCP_CONTRACT}"
}

ccq_mcp_select_servers() {
  local lines line id name desc tag options=() ids=() default_indices=() i
  lines="$(ccq_mcp_all_lines)" || return 1
  if ! ccq_mcp_tty; then
    ccq_mcp_recommended_ids
    return 0
  fi

  if ! command -v ccq_show_multi_select_menu >/dev/null 2>&1; then
    ccq_mcp_recommended_ids
    return 0
  fi

  i=0
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    id="${line%%$'\t'*}"
    local rest="${line#*$'\t'}"
    name="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    desc="${rest%%$'\t'*}"
    tag="${rest#*$'\t'}"
    ids+=("${id}")
    options+=("${name} [$tag] - ${desc}")
    [ "${tag}" = "recommended" ] && default_indices+=("${i}")
    i=$((i + 1))
  done <<EOF
${lines}
EOF

  local selected_indices
  selected_indices="$(ccq_show_multi_select_menu "请选择要配置的 MCP Server（空格切换，Enter 确认）" "${default_indices[*]}" "${options[@]}")" || {
    ccq_mcp_recommended_ids
    return 0
  }

  for i in ${selected_indices}; do
    case "${i}" in
      ''|*[!0-9]*) ;;
      *) [ "${i}" -ge 0 ] && [ "${i}" -lt "${#ids[@]}" ] && printf '%s\n' "${ids[$((i + 1))]}" ;;
    esac
  done
}

ccq_mcp_collect_credentials_json() {
  local server_id="${1:-}"
  ccq_mcp_contract_ready || return 1
  local fields field name label secret required value json="{}"
  fields="$(node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const s = (c.McpServers || {})[process.argv[2]] || {};
const out = [];
for (const item of s.Credentials || []) out.push({name:item.Name,label:item.Label || item.Name,secret:!!item.Secret,required:item.Required !== false});
for (const item of s.ArgsCredentials || []) out.push({name:item.ArgName,label:item.Label || item.ArgName,secret:!!item.Secret,required:item.Required !== false});
if (s.TokenArg) out.push({name:s.TokenArg,label:s.TokenLabel || s.TokenArg,secret:true,required:true});
process.stdout.write(JSON.stringify(out));
' "${CCQ_MCP_CONTRACT}" "${server_id}")" || return 1

  while IFS= read -r field; do
    [ -n "${field}" ] || continue
    name="$(printf '%s' "${field}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.name || "");')"
    label="$(printf '%s' "${field}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.label || v.name || "");')"
    secret="$(printf '%s' "${field}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.secret ? "true" : "false");')"
    required="$(printf '%s' "${field}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.required ? "true" : "false");')"
    if [ "${secret}" = "true" ]; then
      value="$(ccq_mcp_prompt_secret "${label}（输入不会显示）")" || value=""
    else
      value="$(ccq_mcp_prompt_text "${label}")" || value=""
    fi
    if [ -z "${value}" ] && [ "${required}" = "true" ]; then
      CCQ_MCP_CREDENTIAL_ERROR="${label} 不能为空"
      return 1
    fi
    if [ -n "${value}" ]; then
      json="$(printf '%s' "${value}" | CRED_JSON="${json}" CRED_NAME="${name}" node -e '
const fs = require("fs");
const data = JSON.parse(process.env.CRED_JSON || "{}");
data[process.env.CRED_NAME] = fs.readFileSync(0, "utf8");
process.stdout.write(JSON.stringify(data));
')"
    fi
    value=""
  done <<EOF
$(printf '%s' "${fields}" | node -e 'const fs=require("fs"); const arr=JSON.parse(fs.readFileSync(0,"utf8") || "[]"); for (const item of arr) console.log(JSON.stringify(item));')
EOF
  printf '%s\n' "${json}"
}

ccq_mcp_build_server_entry_json() {
  local server_id="${1:-}"
  local credentials_json="${2:-{}}"
  ccq_mcp_contract_ready || return 1
  CREDENTIALS_JSON="${credentials_json}" node -e '
const fs = require("fs");
const crypto = require("crypto");
const contract = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const id = process.argv[2];
const server = (contract.McpServers || {})[id];
if (!server) process.exit(1);
const credentials = JSON.parse(process.env.CREDENTIALS_JSON || "{}");
function replacePlaceholders(text) {
  return String(text).replace(/\{([A-Za-z0-9_\-]+)\}/g, (_, key) => credentials[key] || "");
}
function buildConfig() {
  if (server.McpType === "http") {
    const url = server.UrlTemplate ? replacePlaceholders(server.UrlTemplate) : server.Url;
    return { type: "http", url };
  }
  const config = { command: server.Command, args: [...(server.Args || [])] };
  if (server.CredentialType === "single-key" && server.ApiKeyName && credentials[server.ApiKeyName]) {
    config.env = { [server.ApiKeyName]: credentials[server.ApiKeyName] };
  }
  if (server.CredentialType === "args-multi") {
    for (const item of server.ArgsCredentials || []) {
      if (credentials[item.ArgName]) config.args.push(item.ArgName, credentials[item.ArgName]);
    }
  }
  if (server.CredentialType === "args-token" && server.TokenArg && credentials[server.TokenArg]) {
    config.args.push(`${server.TokenArg}=${credentials[server.TokenArg]}`);
  }
  return config;
}
const config = buildConfig();
const definitionHash = crypto.createHash("sha256").update(JSON.stringify(server)).digest("hex").slice(0, 8);
process.stdout.write(JSON.stringify({ config, meta: { disabled: false, credentials: { values: credentials, envFileValues: {} }, config, definitionHash, updatedAt: new Date().toISOString() } }, null, 2));
' "${CCQ_MCP_CONTRACT}" "${server_id}"
}

ccq_mcp_apply_server_json() {
  local server_id="${1:-}"
  local entry_json="${2:-}"
  local claude_json meta_path settings_path updated_claude updated_meta updated_settings
  claude_json="$(ccq_mcp_claude_json_path)"
  meta_path="$(ccq_mcp_meta_path)"
  settings_path="$(ccq_mcp_settings_path)"

  updated_claude="$(ENTRY_JSON="${entry_json}" CLAUDE_JSON="${claude_json}" node -e '
const fs = require("fs");
const id = process.argv[1];
const entry = JSON.parse(process.env.ENTRY_JSON);
const target = process.env.CLAUDE_JSON;
let data = {};
if (fs.existsSync(target)) { const raw = fs.readFileSync(target, "utf8").trim(); if (raw) data = JSON.parse(raw); }
if (!data.mcpServers || typeof data.mcpServers !== "object") data.mcpServers = {};
data.mcpServers[id] = entry.config;
process.stdout.write(JSON.stringify(data, null, 2) + "\n");
' "${server_id}")" || return 1
  ccq_json_write_atomic "${claude_json}" "${updated_claude}" || return 1

  updated_meta="$(ENTRY_JSON="${entry_json}" META_PATH="${meta_path}" node -e '
const fs = require("fs");
const id = process.argv[1];
const entry = JSON.parse(process.env.ENTRY_JSON);
const target = process.env.META_PATH;
let data = { schemaVersion: 1, createdAt: new Date().toISOString(), servers: {} };
if (fs.existsSync(target)) { const raw = fs.readFileSync(target, "utf8").trim(); if (raw) data = JSON.parse(raw); }
if (!data.servers || typeof data.servers !== "object") data.servers = {};
data.schemaVersion = data.schemaVersion || 1;
data.updatedAt = new Date().toISOString();
data.servers[id] = entry.meta;
process.stdout.write(JSON.stringify(data, null, 2) + "\n");
' "${server_id}")" || return 1
  ccq_json_write_atomic "${meta_path}" "${updated_meta}" || return 1

  updated_settings="$(SETTINGS_PATH="${settings_path}" node -e '
const fs = require("fs");
const id = process.argv[1];
const target = process.env.SETTINGS_PATH;
let data = {};
if (fs.existsSync(target)) { const raw = fs.readFileSync(target, "utf8").trim(); if (raw) data = JSON.parse(raw); }
if (!data.permissions || typeof data.permissions !== "object") data.permissions = {};
if (!Array.isArray(data.permissions.allow)) data.permissions.allow = [];
const perm = `mcp__${id}`;
if (!data.permissions.allow.includes(perm)) data.permissions.allow.push(perm);
process.stdout.write(JSON.stringify(data, null, 2) + "\n");
' "${server_id}")" || return 1
  ccq_json_write_atomic "${settings_path}" "${updated_settings}" || return 1
}

ccq_mcp_install_server() {
  local server_id="${1:-}"
  local credentials_json entry_json
  credentials_json="$(ccq_mcp_collect_credentials_json "${server_id}")" || return 1
  entry_json="$(ccq_mcp_build_server_entry_json "${server_id}" "${credentials_json}")" || return 1
  ccq_mcp_apply_server_json "${server_id}" "${entry_json}"
}

ccq_mcp_configured_count() {
  local claude_json
  claude_json="$(ccq_mcp_claude_json_path)"
  [ -f "${claude_json}" ] || { printf '0'; return 0; }
  node -e 'const fs=require("fs"); const data=JSON.parse(fs.readFileSync(process.argv[1],"utf8") || "{}"); process.stdout.write(String(Object.keys(data.mcpServers || {}).length));' "${claude_json}" 2>/dev/null || printf '0'
}

Test-McpInstalled() {
  local count
  count="$(ccq_mcp_configured_count)"
  if [ "${count}" -gt 0 ]; then
    ccq_mcp_result true "已配置 ${count} 个 MCP Server"
  else
    ccq_mcp_result false "尚未配置 MCP Server"
  fi
}

Install-Mcp() {
  local ids server_id count=0
  ids="$(ccq_mcp_select_servers)" || {
    ccq_mcp_install_result false 0 "未选择 MCP Server"
    return 1
  }
  for server_id in ${ids}; do
    if ccq_mcp_install_server "${server_id}"; then
      count=$((count + 1))
    else
      ccq_ui_warning "MCP Server 配置失败或跳过: ${server_id}"
    fi
  done
  if [ "${count}" -eq 0 ]; then
    ccq_mcp_install_result false 0 "没有成功配置任何 MCP Server"
    return 1
  fi
  ccq_mcp_install_result true "${count}" ""
}

Verify-Mcp() {
  local count
  count="$(ccq_mcp_configured_count)"
  if [ "${count}" -gt 0 ]; then
    printf 'Success=true\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\n'
  printf 'ErrorMessage=MCP Server 配置验证失败\n'
  return 1
}

ccq_mcp_show_status() {
  local claude_json meta_path
  claude_json="$(ccq_mcp_claude_json_path)"
  meta_path="$(ccq_mcp_meta_path)"
  ccq_ui_primary "MCP Server 状态："
  node -e '
const fs = require("fs");
const claudePath = process.argv[1];
const metaPath = process.argv[2];
const claude = fs.existsSync(claudePath) ? JSON.parse(fs.readFileSync(claudePath, "utf8") || "{}") : {};
const meta = fs.existsSync(metaPath) ? JSON.parse(fs.readFileSync(metaPath, "utf8") || "{}") : {};
const ids = new Set([...Object.keys(claude.mcpServers || {}), ...Object.keys(meta.servers || {})]);
if (!ids.size) { console.log("  尚未配置 MCP Server"); process.exit(0); }
for (const id of ids) {
  const active = !!(claude.mcpServers || {})[id];
  const disabled = !!((meta.servers || {})[id]?.disabled);
  const status = active ? "Active" : (disabled ? "Disabled" : "Missing");
  console.log(`  - ${id}: ${status}`);
}
' "${claude_json}" "${meta_path}"
}

ccq_mcp_state_update_json() {
  local action="${1:-}"
  local server_id="${2:-}"
  local claude_path meta_path
  [ -n "${action}" ] && [ -n "${server_id}" ] || return 1
  claude_path="$(ccq_mcp_claude_json_path)"
  meta_path="$(ccq_mcp_meta_path)"
  ACTION="${action}" node -e '
const fs = require("fs");
const id = process.argv[1];
const claudePath = process.argv[2];
const metaPath = process.argv[3];
const action = process.env.ACTION;
let claude = fs.existsSync(claudePath) ? JSON.parse(fs.readFileSync(claudePath, "utf8") || "{}") : {};
let meta = fs.existsSync(metaPath) ? JSON.parse(fs.readFileSync(metaPath, "utf8") || "{}") : { schemaVersion: 1, servers: {} };
if (!meta.servers || typeof meta.servers !== "object") meta.servers = {};
if (action === "disable") {
  const config = claude.mcpServers?.[id] || meta.servers[id]?.config;
  if (!config) process.exit(1);
  if (!meta.servers[id]) meta.servers[id] = { credentials: { values: {}, envFileValues: {} } };
  meta.servers[id].config = config;
  meta.servers[id].disabled = true;
  meta.servers[id].updatedAt = new Date().toISOString();
  if (claude.mcpServers) delete claude.mcpServers[id];
} else if (action === "enable") {
  const entry = meta.servers[id];
  if (!entry || !entry.config) process.exit(1);
  if (!claude.mcpServers || typeof claude.mcpServers !== "object") claude.mcpServers = {};
  claude.mcpServers[id] = entry.config;
  entry.disabled = false;
  entry.updatedAt = new Date().toISOString();
} else if (action === "remove") {
  if (claude.mcpServers) delete claude.mcpServers[id];
  if (meta.servers) delete meta.servers[id];
} else {
  process.exit(1);
}
process.stdout.write(JSON.stringify({ claude, meta }, null, 2) + "\n");
' "${server_id}" "${claude_path}" "${meta_path}"
}

ccq_mcp_write_state_update() {
  local action="${1:-}"
  local server_id="${2:-}"
  local envelope claude_json meta_json
  envelope="$(ccq_mcp_state_update_json "${action}" "${server_id}")" || return 1
  claude_json="$(printf '%s' "${envelope}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(JSON.stringify(v.claude, null, 2) + "\n");')" || return 1
  meta_json="$(printf '%s' "${envelope}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(JSON.stringify(v.meta, null, 2) + "\n");')" || return 1
  ccq_json_write_atomic "$(ccq_mcp_claude_json_path)" "${claude_json}" || return 1
  ccq_json_write_atomic "$(ccq_mcp_meta_path)" "${meta_json}" || return 1
}

ccq_mcp_disable_server() {
  ccq_mcp_write_state_update disable "${1:-}"
}

ccq_mcp_enable_server() {
  ccq_mcp_write_state_update enable "${1:-}"
}

ccq_mcp_remove_server() {
  ccq_mcp_write_state_update remove "${1:-}"
}

ccq_mcp_manage_menu() {
  local choice server_id
  while true; do
    ccq_mcp_show_status
    [ -r /dev/tty ] || return 0
    choice="$(ccq_show_single_select_menu "MCP 管理 - 选择操作" 0 "启用" "禁用" "删除" "安装/添加" "返回")" || return 0
    case "${choice}" in
      0) server_id="$(ccq_mcp_prompt_text "要启用的 ServerId")" && ccq_mcp_enable_server "${server_id}" || ccq_ui_warning "启用失败" ;;
      1) server_id="$(ccq_mcp_prompt_text "要禁用的 ServerId")" && ccq_mcp_disable_server "${server_id}" || ccq_ui_warning "禁用失败" ;;
      2) server_id="$(ccq_mcp_prompt_text "要删除的 ServerId")" && ccq_mcp_remove_server "${server_id}" || ccq_ui_warning "删除失败" ;;
      3) Install-Mcp >/dev/null || ccq_ui_warning "安装/添加失败" ;;
      4) return 0 ;;
      *) ccq_ui_warning "未知选项" ;;
    esac
  done
}
