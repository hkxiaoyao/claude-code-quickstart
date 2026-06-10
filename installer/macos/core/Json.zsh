#!/usr/bin/env zsh
# Json.zsh - macOS JSON 读写助手
# 功能: Node.js helper 进行 JSON 读取、合并、数组去重、敏感字段掩码和原子写入；plutil 作为早期兜底

if [ -n "${CCQ_JSON_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_JSON_ZSH_LOADED=1

ccq_json_validate() {
  local file_path="${1:-}"
  [ -f "${file_path}" ] || return 1
  if command -v node >/dev/null 2>&1; then
    node -e 'const fs=require("fs"); JSON.parse(fs.readFileSync(process.argv[1],"utf8"));' "${file_path}" >/dev/null
    return $?
  fi
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "${file_path}" >/dev/null
    return $?
  fi
  return 1
}

ccq_json_read() {
  local file_path="${1:-}"
  [ -f "${file_path}" ] || { printf '{}\n'; return 0; }
  ccq_json_validate "${file_path}" || return 1
  cat "${file_path}"
}

ccq_json_write_atomic() {
  local file_path="${1:-}"
  local json_content="${2}"
  [ -z "${json_content}" ] && json_content="{}"
  local dir temp_path
  [ -z "${file_path}" ] && return 1
  dir="$(dirname "${file_path}")"
  mkdir -p "${dir}"

  temp_path="$(mktemp "${dir}/.ccq-json.XXXXXX")" || return 1
  printf '%s' "${json_content}" >"${temp_path}"
  ccq_json_validate "${temp_path}" || { rm -f "${temp_path}"; return 1; }
  mv "${temp_path}" "${file_path}"
}

ccq_json_merge_file() {
  local file_path="${1:-}"
  local patch_json="${2}"
  [ -z "${patch_json}" ] && patch_json="{}"
  [ -z "${file_path}" ] && return 1

  if ! command -v node >/dev/null 2>&1; then
    CCQ_LAST_JSON_ERROR="Node.js 不可用，无法执行复杂 JSON merge"
    return 1
  fi

  local merged
  merged="$(node -e '
const fs = require("fs");
const target = process.argv[1];
const patch = JSON.parse(process.argv[2] || "{}");
function isObject(v) { return v && typeof v === "object" && !Array.isArray(v); }
function merge(a, b) {
  const out = isObject(a) ? {...a} : {};
  for (const [key, value] of Object.entries(b)) {
    if (value === null) { delete out[key]; continue; }
    if (Array.isArray(value)) {
      const current = Array.isArray(out[key]) ? out[key] : [];
      out[key] = [...new Set([...current, ...value])];
      continue;
    }
    if (isObject(value)) { out[key] = merge(out[key], value); continue; }
    out[key] = value;
  }
  return out;
}
let base = {};
if (fs.existsSync(target)) {
  const raw = fs.readFileSync(target, "utf8").trim();
  if (raw) base = JSON.parse(raw);
}
process.stdout.write(JSON.stringify(merge(base, patch), null, 2) + "\n");
' "${file_path}" "${patch_json}")" || return 1

  ccq_json_write_atomic "${file_path}" "${merged}"
}

ccq_json_get() {
  local file_path="${1:-}"
  local path_expr="${2:-}"
  [ -z "${file_path}" ] || [ -z "${path_expr}" ] && return 1
  command -v node >/dev/null 2>&1 || return 1
  node -e '
const fs = require("fs");
const target = process.argv[1];
const path = process.argv[2].split(".").filter(Boolean);
let value = {};
if (fs.existsSync(target)) value = JSON.parse(fs.readFileSync(target, "utf8") || "{}");
for (const key of path) {
  if (value == null || !Object.prototype.hasOwnProperty.call(value, key)) process.exit(1);
  value = value[key];
}
if (typeof value === "object") process.stdout.write(JSON.stringify(value));
else process.stdout.write(String(value));
' "${file_path}" "${path_expr}"
}

ccq_mask_secret_value() {
  local value="${1:-}"
  local length="${#value}"
  if [ "${length}" -eq 0 ]; then
    printf '-'
  elif [ "${length}" -le 8 ]; then
    printf '***'
  else
    printf '%s...%s' "${value:0:4}" "${value: -2}"
  fi
}

ccq_json_mask_sensitive() {
  command -v node >/dev/null 2>&1 || { cat; return 0; }
  node -e '
const fs = require("fs");
const secretPattern = /(token|key|secret|password|credential)/i;
function mask(v) {
  if (Array.isArray(v)) return v.map(mask);
  if (v && typeof v === "object") {
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = secretPattern.test(k) ? "***" : mask(val);
    return out;
  }
  return v;
}
const input = fs.readFileSync(0, "utf8");
process.stdout.write(JSON.stringify(mask(JSON.parse(input || "{}")), null, 2) + "\n");
'
}

ccq_json_ensure_object_file() {
  local file_path="${1:-}"
  [ -z "${file_path}" ] && return 1
  if [ -f "${file_path}" ]; then
    ccq_json_validate "${file_path}"
    return $?
  fi
  ccq_json_write_atomic "${file_path}" '{}
'
}
