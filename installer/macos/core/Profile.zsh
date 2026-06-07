#!/usr/bin/env zsh
# Profile.zsh - macOS Profile 安全编辑
# 功能: 托管标记块、子段写入、备份、原子替换和重复写入收敛

if [ -n "${CCQ_PROFILE_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_PROFILE_ZSH_LOADED=1

CCQ_MANAGED_BLOCK_START="# >>> Claude Code Quickstart >>>"
CCQ_MANAGED_BLOCK_END="# <<< Claude Code Quickstart <<<"
: "${CCQ_BACKUP_DIR:=${TMPDIR:-/tmp}/ClaudeEnvInstaller/Backups}"

ccq_user_home() {
  printf '%s\n' "${HOME}"
}

ccq_ensure_dir() {
  local dir="${1:-}"
  [ -z "${dir}" ] && return 1
  mkdir -p "${dir}"
}

ccq_backup_file() {
  local file_path="${1:-}"
  local reason="${2:-edit}"
  [ -f "${file_path}" ] || return 0
  ccq_ensure_dir "${CCQ_BACKUP_DIR}"
  local base timestamp backup_path
  base="$(basename "${file_path}")"
  timestamp="$(date '+%Y%m%d_%H%M%S')"
  backup_path="${CCQ_BACKUP_DIR}/${base}.${reason}.${timestamp}.bak"
  cp "${file_path}" "${backup_path}"
  printf '%s\n' "${backup_path}"
}

ccq_write_file_atomic() {
  local file_path="${1:-}"
  local content="${2:-}"
  local dir temp_path
  [ -z "${file_path}" ] && return 1
  dir="$(dirname "${file_path}")"
  ccq_ensure_dir "${dir}"
  temp_path="$(mktemp "${dir}/.ccq.tmp.XXXXXX")" || return 1
  printf '%s' "${content}" >"${temp_path}"
  mv "${temp_path}" "${file_path}"
}

ccq_get_managed_block_content() {
  local file_path="${1:-}"
  [ -f "${file_path}" ] || return 1

  awk -v start="${CCQ_MANAGED_BLOCK_START}" -v end="${CCQ_MANAGED_BLOCK_END}" '
    $0 == start { in_block = 1; found = 1; next }
    $0 == end { in_block = 0; next }
    in_block { print }
    END { if (!found) exit 1 }
  ' "${file_path}"
}

ccq_remove_managed_block_stream() {
  local file_path="${1:-}"
  if [ ! -f "${file_path}" ]; then
    return 0
  fi

  awk -v start="${CCQ_MANAGED_BLOCK_START}" -v end="${CCQ_MANAGED_BLOCK_END}" '
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    !in_block { print }
  ' "${file_path}"
}

ccq_set_managed_block_in_file() {
  local file_path="${1:-}"
  local block_content="${2:-}"
  local existing_without_block new_content trimmed_existing

  [ -z "${file_path}" ] && return 1
  existing_without_block="$(ccq_remove_managed_block_stream "${file_path}" 2>/dev/null || true)"
  trimmed_existing="${existing_without_block%$'\n'}"

  if [ -n "${trimmed_existing}" ]; then
    new_content="${trimmed_existing}

${CCQ_MANAGED_BLOCK_START}
${block_content%$'\n'}
${CCQ_MANAGED_BLOCK_END}
"
  else
    new_content="${CCQ_MANAGED_BLOCK_START}
${block_content%$'\n'}
${CCQ_MANAGED_BLOCK_END}
"
  fi

  if [ -f "${file_path}" ]; then
    local current
    current="$(cat "${file_path}")"
    if [ "${current%$'\n'}" = "${new_content%$'\n'}" ]; then
      return 0
    fi
    ccq_backup_file "${file_path}" "managed_block" >/dev/null || true
  fi

  ccq_write_file_atomic "${file_path}" "${new_content}"
}

ccq_get_subsection() {
  local file_path="${1:-}"
  local section="${2:-}"
  [ -z "${section}" ] && return 1
  ccq_get_managed_block_content "${file_path}" | awk -v begin="# --- CCQ ${section} ---" -v end="# --- CCQ ${section} END ---" '
    $0 == begin { in_section = 1; found = 1; next }
    $0 == end { in_section = 0; next }
    in_section { print }
    END { if (!found) exit 1 }
  '
}

ccq_set_profile_subsection() {
  local file_path="${1:-}"
  local section="${2:-}"
  local section_content="${3:-}"
  [ -z "${file_path}" ] || [ -z "${section}" ] && return 1

  local existing_block filtered_block new_block
  existing_block="$(ccq_get_managed_block_content "${file_path}" 2>/dev/null || true)"
  filtered_block="$(printf '%s\n' "${existing_block}" | awk -v begin="# --- CCQ ${section} ---" -v end="# --- CCQ ${section} END ---" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' | sed '/^[[:space:]]*$/N;/^\n$/D')"

  if [ -n "${filtered_block%$'\n'}" ]; then
    new_block="${filtered_block%$'\n'}

# --- CCQ ${section} ---
${section_content%$'\n'}
# --- CCQ ${section} END ---"
  else
    new_block="# --- CCQ ${section} ---
${section_content%$'\n'}
# --- CCQ ${section} END ---"
  fi

  ccq_set_managed_block_in_file "${file_path}" "${new_block}"
}

ccq_remove_managed_block_from_file() {
  local file_path="${1:-}"
  [ -f "${file_path}" ] || return 0
  local new_content
  new_content="$(ccq_remove_managed_block_stream "${file_path}")"
  ccq_backup_file "${file_path}" "remove_managed_block" >/dev/null || true
  ccq_write_file_atomic "${file_path}" "${new_content%$'\n'}
"
}

ccq_zprofile_path() { printf '%s\n' "${HOME}/.zprofile"; }
ccq_zshrc_path() { printf '%s\n' "${HOME}/.zshrc"; }
