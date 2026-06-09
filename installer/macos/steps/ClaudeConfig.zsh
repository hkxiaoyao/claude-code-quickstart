#!/usr/bin/env zsh
# ClaudeConfig.zsh - macOS Claude Code 常用配置步骤
# 功能: 按 contracts ClaudeConfig 契约补齐受管配置并保护用户自定义字段

if [ -n "${CCQ_STEP_CLAUDECONFIG_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_CLAUDECONFIG_ZSH_LOADED=1

: "${CCQ_CLAUDE_CONFIG_CONTRACT:=${CCQ_CONTRACTS_DIR:-${CCQ_INSTALLER_ROOT}/contracts}/claude-config.json}"

ccq_claude_settings_path() { printf '%s\n' "${HOME}/.claude/settings.json"; }

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
  local settings_path
  settings_path="$(ccq_claude_settings_path)"
  ccq_claude_config_contract_ready || return 1
  node -e '
const fs = require("fs");
const contract = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const settingsPath = process.argv[2];
let settings = {};
let parseError = "";
if (fs.existsSync(settingsPath)) {
  try {
    const raw = fs.readFileSync(settingsPath, "utf8").trim();
    if (raw) settings = JSON.parse(raw);
  } catch (error) {
    parseError = error.message;
  }
}
const missing = [];
const env = settings.env && typeof settings.env === "object" && !Array.isArray(settings.env) ? settings.env : {};
for (const [key, value] of Object.entries(contract.ClaudeConfigEnvDefaults || {})) {
  if (!env[key] || !String(env[key]).trim()) missing.push(`env.${key}`);
}
for (const [key, value] of Object.entries(contract.TopLevelDefaults || {})) {
  if (key === "attribution") {
    if (!settings.attribution || typeof settings.attribution !== "object") missing.push("attribution");
    continue;
  }
  if (settings[key] === undefined || settings[key] === null || String(settings[key]).trim() === "") missing.push(key);
}
const permissions = settings.permissions && typeof settings.permissions === "object" ? settings.permissions : {};
const allow = Array.isArray(permissions.allow) ? permissions.allow : [];
for (const perm of contract.ClaudeConfigBasePermissions || []) {
  if (!allow.includes(perm)) missing.push(`permissions.allow.${perm}`);
}
process.stdout.write(JSON.stringify({ installed: !parseError && missing.length === 0, parseError, missing }, null, 2));
' "${CCQ_CLAUDE_CONFIG_CONTRACT}" "${settings_path}"
}

ccq_claude_config_apply() {
  local mode="${1:-install}"
  local settings_path out_file items_file updated_json updated_items
  settings_path="$(ccq_claude_settings_path)"
  out_file="$(mktemp "${TMPDIR:-/tmp}/ccq-claude-config.XXXXXX")" || return 1
  items_file="$(mktemp "${TMPDIR:-/tmp}/ccq-claude-config-items.XXXXXX")" || { rm -f "${out_file}"; return 1; }

  ccq_claude_config_contract_ready || { rm -f "${out_file}" "${items_file}"; return 1; }
  node -e '
const fs = require("fs");
const contract = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const settingsPath = process.argv[2];
const mode = process.argv[3];
const outFile = process.argv[4];
const itemsFile = process.argv[5];
let settings = {};
if (fs.existsSync(settingsPath)) {
  const raw = fs.readFileSync(settingsPath, "utf8").trim();
  if (raw) settings = JSON.parse(raw);
}
const items = [];
function isObject(v) { return v && typeof v === "object" && !Array.isArray(v); }
if (!isObject(settings.env)) { settings.env = {}; items.push("config::env::section-added"); }
for (const [key, value] of Object.entries(contract.ClaudeConfigEnvDefaults || {})) {
  if (mode === "update") {
    if (settings.env[key] !== String(value)) {
      items.push(settings.env[key] === undefined ? `config::env.${key}::added` : `config::env.${key}::updated`);
      settings.env[key] = String(value);
    }
  } else if (settings.env[key] === undefined || settings.env[key] === null || !String(settings.env[key]).trim()) {
    settings.env[key] = String(value);
    items.push(`config::env.${key}::added`);
  }
}
for (const key of contract.ClaudeConfigDeprecatedEnvKeys || []) {
  if (Object.prototype.hasOwnProperty.call(settings.env, key)) {
    delete settings.env[key];
    items.push(`config::env.${key}::removed`);
  }
}
for (const [key, value] of Object.entries(contract.TopLevelDefaults || {})) {
  if (key === "attribution") {
    if (!isObject(settings.attribution)) {
      settings.attribution = value;
      items.push("config::attribution::added");
    }
    continue;
  }
  const missing = settings[key] === undefined || settings[key] === null || (typeof settings[key] === "string" && !settings[key].trim());
  if (missing || (mode === "update" && key === "plansDirectory" && settings[key] !== value)) {
    settings[key] = value;
    items.push(`config::${key}::${missing ? "added" : "updated"}`);
  }
}
if (!isObject(settings.permissions)) { settings.permissions = {}; items.push("config::permissions::section-added"); }
if (!Array.isArray(settings.permissions.allow)) { settings.permissions.allow = []; items.push("config::permissions.allow::section-added"); }
const allow = [];
for (const perm of settings.permissions.allow) {
  if (typeof perm === "string" && perm.trim() && !allow.includes(perm)) allow.push(perm);
}
for (const perm of contract.ClaudeConfigBasePermissions || []) {
  if (!allow.includes(perm)) {
    allow.push(perm);
    items.push(`config::permissions.allow.${perm}::added`);
  }
}
settings.permissions.allow = allow;
if (!Array.isArray(settings.permissions.deny)) settings.permissions.deny = [];
fs.writeFileSync(outFile, JSON.stringify(settings, null, 2) + "\n");
fs.writeFileSync(itemsFile, items.length ? items.join(";") : "noop::ClaudeConfig::no-change");
' "${CCQ_CLAUDE_CONFIG_CONTRACT}" "${settings_path}" "${mode}" "${out_file}" "${items_file}" || {
    rm -f "${out_file}" "${items_file}"
    return 1
  }

  updated_json="$(cat "${out_file}")"
  updated_items="$(cat "${items_file}")"
  rm -f "${out_file}" "${items_file}"
  ccq_json_write_atomic "${settings_path}" "${updated_json}" || return 1
  CCQ_CLAUDE_CONFIG_UPDATED_ITEMS="${updated_items}"
}

Test-ClaudeConfigInstalled() {
  local analysis missing_count parse_error
  analysis="$(ccq_claude_config_analyze_json 2>/dev/null || true)"
  if [ -z "${analysis}" ]; then
    ccq_claude_config_result false "ClaudeConfig 契约或 Node.js 不可用"
    return 0
  fi
  parse_error="$(printf '%s' "${analysis}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.parseError || "");' 2>/dev/null || true)"
  if [ -n "${parse_error}" ]; then
    ccq_claude_config_result false "settings.json 无法解析"
    return 0
  fi
  missing_count="$(printf '%s' "${analysis}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(String((v.missing || []).length));' 2>/dev/null || printf '1')"
  if [ "${missing_count}" -eq 0 ]; then
    ccq_claude_config_result true "Claude Code 常用配置已安装"
  else
    ccq_claude_config_result false "Claude Code 常用配置缺少 ${missing_count} 项"
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
  local analysis installed
  analysis="$(ccq_claude_config_analyze_json 2>/dev/null || true)"
  installed="$(printf '%s' "${analysis}" | node -e 'const fs=require("fs"); const v=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(v.installed ? "true" : "false");' 2>/dev/null || printf 'false')"
  if [ "${installed}" = "true" ]; then
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
