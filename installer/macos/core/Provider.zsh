#!/usr/bin/env zsh
# Provider.zsh - 供应商管理核心模块（CRUD + 同步 + 切换 + 交互菜单）
# 功能: 承载全部供应商业务逻辑，供 steps/ApiKey.zsh 安装与 Manage.zsh 管理复用
# 依赖: Ui.zsh, Json.zsh（须在本模块之前加载）

if [ -n "${CCQ_PROVIDER_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_PROVIDER_ZSH_LOADED=1

: "${CCQ_PROVIDER_CONTRACT:=${CCQ_CONTRACTS_DIR:-${CCQ_INSTALLER_ROOT}/contracts}/providers.json}"

# ─── 路径助手 ───────────────────────────────────────────────────────────────

ccq_provider_settings_path() { printf '%s\n' "${HOME}/.claude/settings.json"; }
ccq_provider_profiles_dir() { printf '%s\n' "${HOME}/.claude/providers"; }
ccq_claude_json_path() { printf '%s\n' "${HOME}/.claude.json"; }

ccq_provider_profile_path() {
  local key="${1:-}"
  printf '%s/%s.json\n' "$(ccq_provider_profiles_dir)" "${key}"
}

# ─── 契约访问 ───────────────────────────────────────────────────────────────

ccq_provider_contract_node() {
  command -v node >/dev/null 2>&1 || return 1
  [ -f "${CCQ_PROVIDER_CONTRACT}" ] || return 1
}

ccq_provider_builtin_lines() {
  ccq_provider_contract_node || return 1
  node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const [key, p] of Object.entries(c.BuiltinProviders || {})) {
  console.log([key, p.Name || key, p.Description || ""].join("\t"));
}
' "${CCQ_PROVIDER_CONTRACT}"
}

ccq_provider_get_builtin_field() {
  local key="${1:-}"
  local field="${2:-}"
  node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const p = (c.BuiltinProviders || {})[process.argv[2]] || {};
const value = p[process.argv[3]] || "";
process.stdout.write(String(value));
' "${CCQ_PROVIDER_CONTRACT}" "${key}" "${field}"
}

ccq_provider_requires_model_config() {
  local key="${1:-}"
  node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const p = (c.BuiltinProviders || {})[process.argv[2]] || {};
process.exit(p.RequireModelConfig ? 0 : 1);
' "${CCQ_PROVIDER_CONTRACT}" "${key}"
}

ccq_provider_match_builtin_key() {
  local base_url="${1:-}"
  ccq_provider_contract_node || return 1
  BASE_URL="${base_url}" node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const norm = (v) => String(v || "").trim().replace(/\/+$/, "");
const target = norm(process.env.BASE_URL);
for (const [k, p] of Object.entries(c.BuiltinProviders || {})) {
  const b = norm(p.BaseUrl);
  if (b && (b === target || target.startsWith(b + "/"))) { process.stdout.write(k); return; }
}
process.stdout.write("custom");
' "${CCQ_PROVIDER_CONTRACT}"
}

# ─── TTY 与输入 ─────────────────────────────────────────────────────────────

ccq_provider_tty() {
  [ -r /dev/tty ] && [ -w /dev/tty ]
}

ccq_provider_prompt_secret() {
  local prompt="${1:-API Key}"
  local value=""
  ccq_provider_tty || return 1
  printf '%s: ' "${prompt}" >/dev/tty
  IFS= read -r -s value </dev/tty || return 1
  printf '\n' >/dev/tty
  printf '%s' "${value}"
}

ccq_provider_prompt_text() {
  local prompt="${1:-请输入}"
  local default_value="${2:-}"
  local value=""
  ccq_provider_tty || return 1
  if [ -n "${default_value}" ]; then
    printf '%s [%s]: ' "${prompt}" "${default_value}" >/dev/tty
    IFS= read -r value </dev/tty || return 1
    printf '%s' "${value:-${default_value}}"
  else
    printf '%s: ' "${prompt}" >/dev/tty
    IFS= read -r value </dev/tty || return 1
    printf '%s' "${value}"
  fi
}

ccq_provider_read_model_env() {
  ccq_provider_contract_node || return 1
  local output=""
  output="$(node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const labels = c.ManagedEnv.ProviderModelEnvLabels || {};
for (const key of c.ManagedEnv.ProviderManagedModelEnvKeys || []) {
  console.log([key, labels[key] || key].join("\t"));
}
' "${CCQ_PROVIDER_CONTRACT}")" || return 1

  local patch="{}" line key label value
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    key="${line%%$'\t'*}"
    label="${line#*$'\t'}"
    value="$(ccq_provider_prompt_text "${label} (${key})，留空跳过" "")"
    if [ -n "${value}" ]; then
      patch="$(MODEL_KEY="${key}" MODEL_VALUE="${value}" PATCH_JSON="${patch}" node -e '
const patch = JSON.parse(process.env.PATCH_JSON || "{}");
patch[process.env.MODEL_KEY] = process.env.MODEL_VALUE;
console.log(JSON.stringify(patch));
')" || return 1
    fi
  done <<EOF
${output}
EOF
  printf '%s\n' "${patch}"
}

# ─── Profile 构建与切换 ─────────────────────────────────────────────────────

ccq_provider_build_profile_json() {
  local key="${1:-}"
  local provider_name="${2:-}"
  local base_url="${3:-}"
  local api_key="${4:-}"
  local model_env_json="${5}"
  [ -z "${model_env_json}" ] && model_env_json="{}"
  ccq_provider_contract_node || return 1
  printf '%s' "${api_key}" | PROVIDER_KEY="${key}" PROVIDER_NAME="${provider_name}" PROVIDER_BASE_URL="${base_url}" MODEL_ENV_JSON="${model_env_json}" node -e '
const fs = require("fs");
const apiKey = fs.readFileSync(0, "utf8");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const key = process.env.PROVIDER_KEY;
const builtin = (c.BuiltinProviders || {})[key] || {};
const modelEnv = JSON.parse(process.env.MODEL_ENV_JSON || "{}");
const profile = {
  _meta: {
    provider: process.env.PROVIDER_NAME,
    key,
    baseUrl: process.env.PROVIDER_BASE_URL,
    configuredAt: new Date().toISOString()
  },
  env: {
    ANTHROPIC_AUTH_TOKEN: apiKey,
    ANTHROPIC_BASE_URL: process.env.PROVIDER_BASE_URL
  }
};
for (const [k, v] of Object.entries(builtin.ExtraEnv || {})) {
  if (v !== undefined && v !== null && String(v).trim()) profile.env[k] = String(v);
}
const finalModelEnv = Object.keys(modelEnv).length ? modelEnv : (builtin.ModelEnv || {});
if (Object.keys(finalModelEnv).length) profile.modelEnv = finalModelEnv;
process.stdout.write(JSON.stringify(profile, null, 2) + "\n");
' "${CCQ_PROVIDER_CONTRACT}"
}

ccq_provider_switch_profile() {
  local profile_path="${1:-}"
  local settings_path merged_json
  settings_path="$(ccq_provider_settings_path)"
  ccq_provider_contract_node || return 1
  merged_json="$(SETTINGS_PATH="${settings_path}" PROFILE_PATH="${profile_path}" node -e '
const fs = require("fs");
const settingsPath = process.env.SETTINGS_PATH;
const profilePath = process.env.PROFILE_PATH;
const contract = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const profile = JSON.parse(fs.readFileSync(profilePath, "utf8"));
let settings = {};
if (fs.existsSync(settingsPath)) {
  const raw = fs.readFileSync(settingsPath, "utf8").trim();
  if (raw) settings = JSON.parse(raw);
}
if (!settings.env || typeof settings.env !== "object" || Array.isArray(settings.env)) settings.env = {};
const env = settings.env;
const keys = [
  contract.ManagedEnv.AuthTokenKey,
  contract.ManagedEnv.BaseUrlKey,
  ...(contract.ManagedEnv.ProviderManagedModelEnvKeys || []),
  ...(contract.ManagedEnv.ProviderManagedExtraEnvKeys || [])
];
for (const key of keys) delete env[key];
for (const [key, value] of Object.entries(profile.env || {})) {
  if (value !== undefined && value !== null && String(value).trim()) env[key] = String(value);
}
for (const [key, value] of Object.entries(profile.modelEnv || {})) {
  if (value !== undefined && value !== null && String(value).trim()) env[key] = String(value);
}
process.stdout.write(JSON.stringify(settings, null, 2) + "\n");
' "${CCQ_PROVIDER_CONTRACT}")" || return 1
  ccq_json_write_atomic "${settings_path}" "${merged_json}"
}

ccq_provider_write_onboarding() {
  local claude_json_path merged_json
  claude_json_path="$(ccq_claude_json_path)"
  merged_json="$(node -e '
const fs = require("fs");
const target = process.argv[1];
let data = {};
if (fs.existsSync(target)) {
  const raw = fs.readFileSync(target, "utf8").trim();
  if (raw) data = JSON.parse(raw);
}
data.hasCompletedOnboarding = true;
process.stdout.write(JSON.stringify(data, null, 2) + "\n");
' "${claude_json_path}")" || return 1
  ccq_json_write_atomic "${claude_json_path}" "${merged_json}"
}

# ─── 选择与匹配 ─────────────────────────────────────────────────────────────

ccq_provider_select_builtin() {
  local lines line key name desc options=() keys=()
  ccq_provider_tty || return 1
  lines="$(ccq_provider_builtin_lines)" || return 1
  for line in ${(f)lines}; do
    key="${line%%$'\t'*}"
    local rest="${line#*$'\t'}"
    name="${rest%%$'\t'*}"
    desc="${rest#*$'\t'}"
    keys+=("${key}")
    options+=("${name} - ${desc}")
  done

  local selected_index
  selected_index="$(ccq_show_single_select_menu "请选择第三方供应商" 0 "${options[@]}")" || return 1
  printf '%s\n' "${keys[$((selected_index + 1))]}"
}

ccq_provider_env_value_exists() {
  local file_path="${1:-}"
  local path_expr="${2:-}"
  local value
  value="$(ccq_json_get "${file_path}" "${path_expr}" 2>/dev/null || true)"
  [ -n "${value}" ]
}

ccq_provider_base_url_matches() {
  local settings_base="${1:-}"
  local profile_base="${2:-}"
  node -e '
const normalize = (value) => String(value || "").trim().replace(/\/+$/, "");
const settingsBase = normalize(process.argv[1]);
const profileBase = normalize(process.argv[2]);
process.exit(settingsBase && profileBase && (settingsBase === profileBase || settingsBase.startsWith(`${profileBase}/`)) ? 0 : 1);
' "${settings_base}" "${profile_base}" 2>/dev/null
}

ccq_provider_auth_token_matches() {
  local settings_token="${1:-}"
  local profile_token="${2:-}"
  [ -n "${settings_token}" ] && [ -n "${profile_token}" ] && [ "${settings_token}" = "${profile_token}" ]
}

# ─── 活跃供应商解析 ─────────────────────────────────────────────────────────

ccq_provider_active_base_url() {
  local settings_path
  settings_path="$(ccq_provider_settings_path)"
  ccq_json_get "${settings_path}" "env.ANTHROPIC_BASE_URL" 2>/dev/null || true
}

ccq_provider_active_auth_token() {
  local settings_path
  settings_path="$(ccq_provider_settings_path)"
  ccq_json_get "${settings_path}" "env.ANTHROPIC_AUTH_TOKEN" 2>/dev/null || true
}

ccq_provider_profile_field() {
  local profile_path="${1:-}"
  local field="${2:-provider}"
  [ -f "${profile_path}" ] || return 1
  node -e '
const fs = require("fs");
const profile = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const field = process.argv[2];
const meta = profile._meta || {};
if (field === "key") process.stdout.write(meta.key || "");
else if (field === "provider") process.stdout.write(meta.provider || "");
else if (field === "baseUrl") process.stdout.write(meta.baseUrl || profile.env?.ANTHROPIC_BASE_URL || "");
else if (field === "authToken") process.stdout.write(profile.env?.ANTHROPIC_AUTH_TOKEN || "");
else process.stdout.write("");
' "${profile_path}" "${field}"
}

ccq_provider_resolve_active_key() {
  local profiles_dir active_base active_token file key base_url profile_token
  local first_base_key="" token_match_key="" has_profile_token=0
  profiles_dir="$(ccq_provider_profiles_dir)"
  active_base="$(ccq_provider_active_base_url)"
  active_token="$(ccq_provider_active_auth_token)"
  [ -d "${profiles_dir}" ] && [ -n "${active_base}" ] || return 0

  for file in "${profiles_dir}"/*.json; do
    [ -f "${file}" ] || continue
    base_url="$(ccq_provider_profile_field "${file}" baseUrl)"
    ccq_provider_base_url_matches "${active_base}" "${base_url}" || continue
    key="$(basename "${file}" .json)"
    [ -z "${first_base_key}" ] && first_base_key="${key}"
    profile_token="$(ccq_provider_profile_field "${file}" authToken)"
    if [ -n "${profile_token}" ]; then
      has_profile_token=1
      if ccq_provider_auth_token_matches "${active_token}" "${profile_token}"; then
        token_match_key="${key}"
        break
      fi
    fi
  done

  if [ -n "${token_match_key}" ]; then
    printf '%s' "${token_match_key}"
  elif [ -z "${active_token}" ] || [ "${has_profile_token}" = "0" ]; then
    printf '%s' "${first_base_key}"
  fi
}

# ─── 从 settings.json 同步迁移（旧用户）─────────────────────────────────────

ccq_provider_sync_from_settings() {
  local settings_path active_base active_token key name profile_json profile_path
  settings_path="$(ccq_provider_settings_path)"
  [ -f "${settings_path}" ] || return 0
  active_base="$(ccq_provider_active_base_url)"
  active_token="$(ccq_provider_active_auth_token)"
  [ -n "${active_base}" ] && [ -n "${active_token}" ] || return 0
  [ -z "$(ccq_provider_resolve_active_key)" ] || return 0
  ccq_provider_contract_node || return 0

  key="$(ccq_provider_match_builtin_key "${active_base}")"
  [ -n "${key}" ] || key="custom"
  if [ "${key}" = "custom" ]; then
    name="自定义供应商"
  else
    name="$(ccq_provider_get_builtin_field "${key}" Name)"
  fi

  profile_path="$(ccq_provider_profile_path "${key}")"
  [ -f "${profile_path}" ] && return 0
  profile_json="$(ccq_provider_build_profile_json "${key}" "${name}" "${active_base}" "${active_token}" "{}")" || return 0
  ccq_json_write_atomic "${profile_path}" "${profile_json}" >/dev/null 2>&1 || return 0
}

# ─── 状态展示 ───────────────────────────────────────────────────────────────

ccq_provider_show_status() {
  local profiles_dir file key name base_url active_key active_tag
  profiles_dir="$(ccq_provider_profiles_dir)"
  active_key="$(ccq_provider_resolve_active_key)"
  ccq_ui_primary "供应商状态："
  if [ ! -d "${profiles_dir}" ]; then
    ccq_ui_warning "  尚未发现 provider profile 目录"
    return 0
  fi
  local found=0
  for file in "${profiles_dir}"/*.json; do
    [ -f "${file}" ] || continue
    found=1
    key="$(basename "${file}" .json)"
    name="$(ccq_provider_profile_field "${file}" provider)"
    base_url="$(ccq_provider_profile_field "${file}" baseUrl)"
    active_tag=""
    [ -n "${active_key}" ] && [ "${key}" = "${active_key}" ] && active_tag=" [active]"
    ccq_ui_info "  - ${key}: ${name:-未知供应商}${active_tag} / Base URL: $(ccq_mask_secret_value "${base_url}")"
  done
  [ "${found}" = "1" ] || ccq_ui_warning "  尚未配置任何供应商"
}

# ─── CRUD ───────────────────────────────────────────────────────────────────

ccq_provider_switch_key() {
  local key="${1:-}"
  local profile_path
  [ -n "${key}" ] || return 1
  profile_path="$(ccq_provider_profile_path "${key}")"
  [ -f "${profile_path}" ] || return 1
  ccq_provider_switch_profile "${profile_path}"
}

ccq_provider_remove_key() {
  local key="${1:-}"
  local profile_path active_key
  [ -n "${key}" ] || return 1
  profile_path="$(ccq_provider_profile_path "${key}")"
  [ -f "${profile_path}" ] || return 1
  active_key="$(ccq_provider_resolve_active_key)"
  if [ -n "${active_key}" ] && [ "${key}" = "${active_key}" ]; then
    CCQ_PROVIDER_ERROR="不能删除当前活跃供应商"
    return 1
  fi
  rm -f "${profile_path}"
}

ccq_provider_edit_key() {
  local key="${1:-}"
  local profile_path choice new_value updated_json was_active
  [ -n "${key}" ] || return 1
  profile_path="$(ccq_provider_profile_path "${key}")"
  [ -f "${profile_path}" ] || return 1
  ccq_provider_tty || return 1

  choice="$(ccq_show_single_select_menu "编辑供应商 ${key} - 选择修改项" 0 "API Key" "Base URL" "名称")" || return 0
  case "${choice}" in
    0) new_value="$(ccq_provider_prompt_secret "新的 API Key（输入不会显示）")" || return 1; choice=1 ;;
    1) new_value="$(ccq_provider_prompt_text "新的 Base URL")" || return 1; choice=2 ;;
    2) new_value="$(ccq_provider_prompt_text "新的供应商名称")" || return 1; choice=3 ;;
    *) CCQ_PROVIDER_ERROR="未知编辑选项"; return 1 ;;
  esac
  [ -n "${new_value}" ] || { CCQ_PROVIDER_ERROR="新值不能为空"; return 1; }

  was_active=0
  if [ "${key}" = "$(ccq_provider_resolve_active_key)" ]; then
    was_active=1
  fi

  updated_json="$(CHOICE="${choice}" NEW_VALUE="${new_value}" node -e '
const fs = require("fs");
const profile = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!profile._meta) profile._meta = {};
if (!profile.env) profile.env = {};
if (process.env.CHOICE === "1") profile.env.ANTHROPIC_AUTH_TOKEN = process.env.NEW_VALUE;
if (process.env.CHOICE === "2") { profile._meta.baseUrl = process.env.NEW_VALUE; profile.env.ANTHROPIC_BASE_URL = process.env.NEW_VALUE; }
if (process.env.CHOICE === "3") profile._meta.provider = process.env.NEW_VALUE;
profile._meta.configuredAt = profile._meta.configuredAt || new Date().toISOString();
profile._meta.updatedAt = new Date().toISOString();
process.stdout.write(JSON.stringify(profile, null, 2) + "\n");
' "${profile_path}")" || return 1
  new_value=""
  ccq_json_write_atomic "${profile_path}" "${updated_json}" || return 1

  if [ "${was_active}" = "1" ]; then
    ccq_provider_switch_profile "${profile_path}" || return 1
  fi
}

# ─── 交互安装流程（供 steps/ApiKey.zsh 与管理菜单复用）─────────────────────
# 成功: 设置 CCQ_PROVIDER_LAST_NAME，返回 0
# 失败: 设置 CCQ_PROVIDER_ERROR / CCQ_PROVIDER_LAST_BASEURL_OK，返回 1

ccq_provider_interactive_install() {
  CCQ_PROVIDER_ERROR=""
  CCQ_PROVIDER_LAST_NAME=""
  CCQ_PROVIDER_LAST_BASEURL_OK="false"

  local selected_key provider_name base_url api_key model_env_json profile_json profile_path
  selected_key="$(ccq_provider_select_builtin)" || {
    CCQ_PROVIDER_ERROR="用户取消供应商选择"
    return 1
  }
  provider_name="$(ccq_provider_get_builtin_field "${selected_key}" Name)"
  base_url="$(ccq_provider_get_builtin_field "${selected_key}" BaseUrl)"

  if [ "${selected_key}" = "custom" ]; then
    provider_name="$(ccq_provider_prompt_text "供应商名称" "自定义供应商")"
    base_url="$(ccq_provider_prompt_text "Base URL" "")"
  else
    base_url="$(ccq_provider_prompt_text "Base URL" "${base_url}")"
  fi

  if [ -z "${provider_name}" ] || [ -z "${base_url}" ]; then
    CCQ_PROVIDER_LAST_NAME="${provider_name}"
    CCQ_PROVIDER_ERROR="供应商名称或 Base URL 为空"
    return 1
  fi
  CCQ_PROVIDER_LAST_NAME="${provider_name}"
  CCQ_PROVIDER_LAST_BASEURL_OK="true"

  api_key="$(ccq_provider_prompt_secret "API Key（输入不会显示）")"
  if [ -z "${api_key}" ]; then
    CCQ_PROVIDER_ERROR="API Key 为空"
    return 1
  fi

  model_env_json="{}"
  if [ "${selected_key}" = "custom" ] || ccq_provider_requires_model_config "${selected_key}"; then
    local ask_index
    ask_index="$(ccq_show_single_select_menu "是否配置模型环境键？(可选，大多数供应商不需要)" 0 "跳过" "配置模型")" || ask_index=0
    if [ "${ask_index}" = "1" ]; then
      ccq_ui_primary "将写入 settings.env 的 3 个模型键；留空表示不设置该键" "essential"
      model_env_json="$(ccq_provider_read_model_env 2>/dev/null || printf '{}')"
    fi
  fi

  profile_json="$(ccq_provider_build_profile_json "${selected_key}" "${provider_name}" "${base_url}" "${api_key}" "${model_env_json}")" || {
    api_key=""
    CCQ_PROVIDER_ERROR="供应商 Profile 构建失败"
    return 1
  }
  api_key=""

  profile_path="$(ccq_provider_profile_path "${selected_key}")"
  if ! ccq_json_write_atomic "${profile_path}" "${profile_json}"; then
    CCQ_PROVIDER_ERROR="供应商 Profile 写入失败"
    return 1
  fi

  if ! ccq_provider_switch_profile "${profile_path}"; then
    CCQ_PROVIDER_ERROR="settings.json 激活供应商失败"
    return 1
  fi

  ccq_provider_write_onboarding >/dev/null 2>&1 || true
  return 0
}

# ─── 交互管理菜单 ───────────────────────────────────────────────────────────

ccq_provider_manage_menu() {
  local choice key
  ccq_provider_sync_from_settings
  while true; do
    ccq_provider_show_status
    [ -r /dev/tty ] || return 0
    choice="$(ccq_show_single_select_menu "供应商管理 - 选择操作" 0 "添加" "编辑" "删除" "切换" "返回")" || return 0
    case "${choice}" in
      0) ccq_provider_interactive_install || ccq_ui_warning "添加供应商失败: ${CCQ_PROVIDER_ERROR:-已取消}" ;;
      1) key="$(ccq_provider_prompt_text "要编辑的供应商 key")" && ccq_provider_edit_key "${key}" || ccq_ui_warning "编辑失败: ${CCQ_PROVIDER_ERROR:-未知错误}" ;;
      2) key="$(ccq_provider_prompt_text "要删除的供应商 key")" && ccq_provider_remove_key "${key}" || ccq_ui_warning "删除失败: ${CCQ_PROVIDER_ERROR:-未知错误}" ;;
      3) key="$(ccq_provider_prompt_text "要切换的供应商 key")" && ccq_provider_switch_key "${key}" || ccq_ui_warning "切换失败" ;;
      4) return 0 ;;
      *) ccq_ui_warning "未知选项" ;;
    esac
  done
}
