#!/usr/bin/env zsh
# McpManager.zsh - MCP Server 管理核心模块
# 功能: 承载 MCP 状态查看、禁用/启用/删除、管理菜单逻辑，供 Manage.zsh 复用
# 依赖: Ui.zsh, Json.zsh（须在本模块之前加载）

if [ -n "${CCQ_MCP_MANAGER_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_MCP_MANAGER_ZSH_LOADED=1

: "${CCQ_MCP_CONTRACT:=${CCQ_CONTRACTS_DIR:-${CCQ_INSTALLER_ROOT}/contracts}/mcp-servers.json}"

# ─── 路径助手 ───────────────────────────────────────────────────────────────

ccq_mcp_claude_json_path() { printf '%s\n' "${HOME}/.claude.json"; }
ccq_mcp_meta_path() { printf '%s\n' "${HOME}/.ccq/mcp-meta.json"; }

ccq_mcp_tty() { [ -r /dev/tty ] && [ -w /dev/tty ]; }

ccq_mcp_prompt_text() {
  local prompt="${1:-请输入}"
  local value=""
  ccq_mcp_tty || return 1
  printf '%s: ' "${prompt}" >/dev/tty
  IFS= read -r value </dev/tty || return 1
  printf '%s' "${value}"
}

# ─── 状态查看 ───────────────────────────────────────────────────────────────

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

# ─── 状态更新封装 ───────────────────────────────────────────────────────────

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

# ─── CRUD ───────────────────────────────────────────────────────────────────

ccq_mcp_disable_server() {
  ccq_mcp_write_state_update disable "${1:-}"
}

ccq_mcp_enable_server() {
  ccq_mcp_write_state_update enable "${1:-}"
}

ccq_mcp_remove_server() {
  ccq_mcp_write_state_update remove "${1:-}"
}

# ─── 交互管理菜单 ───────────────────────────────────────────────────────────

ccq_mcp_manage_menu() {
  local choice server_id
  while true; do
    ccq_mcp_show_status
    [ -r /dev/tty ] || return 0
    choice="$(ccq_show_single_select_menu "MCP 管理 - 选择操作" 0 "启用" "禁用" "删除" "返回")" || return 0
    case "${choice}" in
      0) server_id="$(ccq_mcp_prompt_text "要启用的 ServerId")" && ccq_mcp_enable_server "${server_id}" || ccq_ui_warning "启用失败" ;;
      1) server_id="$(ccq_mcp_prompt_text "要禁用的 ServerId")" && ccq_mcp_disable_server "${server_id}" || ccq_ui_warning "禁用失败" ;;
      2) server_id="$(ccq_mcp_prompt_text "要删除的 ServerId")" && ccq_mcp_remove_server "${server_id}" || ccq_ui_warning "删除失败" ;;
      3) return 0 ;;
      *) ccq_ui_warning "未知选项" ;;
    esac
  done
}
