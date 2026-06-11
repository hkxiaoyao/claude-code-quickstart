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

# ============ Update Manifest 管理 ============

ccq_update_manifest_path() {
  printf '%s/.ccq/update-manifest.json\n' "${HOME}"
}

ccq_read_update_manifest() {
  local manifest_path
  manifest_path="$(ccq_update_manifest_path)"

  if [ ! -f "${manifest_path}" ]; then
    printf '{"schemaVersion":1,"steps":{}}\n'
    return 0
  fi

  cat "${manifest_path}"
}

ccq_write_update_manifest() {
  local content="${1:-}"
  local manifest_path
  manifest_path="$(ccq_update_manifest_path)"

  ccq_ensure_dir "$(dirname "${manifest_path}")"

  # 自动追加 updatedAt 时间戳
  local updated_content
  updated_content="$(node -e "
    const data = JSON.parse(process.argv[1]);
    data.updatedAt = new Date().toISOString();
    console.log(JSON.stringify(data, null, 2));
  " "${content}" 2>/dev/null || printf '%s' "${content}")"

  ccq_write_file_atomic "${manifest_path}" "${updated_content}"
}

# ============ Update Snapshot 管理 ============

ccq_create_update_snapshot() {
  local snapshot_base="${TMPDIR:-/tmp}/ccq-backups"
  local timestamp pid rand8 snapshot_dir

  timestamp="$(date '+%Y%m%d_%H%M%S')"
  pid="$$"
  rand8="$(openssl rand -hex 4 2>/dev/null || printf '%08x' $RANDOM$RANDOM)"
  snapshot_dir="${snapshot_base}/update_${timestamp}_${pid}_${rand8}"

  ccq_ensure_dir "${snapshot_dir}" || return 1

  # 备份文件列表
  local files_to_backup=(
    "${HOME}/.claude/settings.json"
    "${HOME}/.claude.json"
    "${HOME}/.claude/CLAUDE.md"
    "${HOME}/.ccq/mcp-meta.json"
  )

  local created_at files_array=()
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # 备份每个文件
  for source_file in "${files_to_backup[@]}"; do
    if [ -f "${source_file}" ]; then
      local relative_path hash file_timestamp backup_dest
      relative_path="${source_file#${HOME}/}"
      backup_dest="${snapshot_dir}/${relative_path}"

      ccq_ensure_dir "$(dirname "${backup_dest}")"
      cp "${source_file}" "${backup_dest}" 2>/dev/null || continue

      hash="$(ccq_string_fingerprint "$(cat "${source_file}" 2>/dev/null || true)")"
      file_timestamp="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "${source_file}" 2>/dev/null || echo "${created_at}")"

      files_array+=("{\"source\":\"${source_file}\",\"relative\":\"${relative_path}\",\"hash\":\"${hash}\",\"timestamp\":\"${file_timestamp}\"}")
    fi
  done

  # 备份 ccq-*.md 和 ccg-*.md rules
  for rules_pattern in "${HOME}/.claude/rules/ccq-"*.md "${HOME}/.claude/rules/ccg-"*.md; do
    if [ -f "${rules_pattern}" ]; then
      local relative_path hash file_timestamp backup_dest
      relative_path="${rules_pattern#${HOME}/}"
      backup_dest="${snapshot_dir}/${relative_path}"

      ccq_ensure_dir "$(dirname "${backup_dest}")"
      cp "${rules_pattern}" "${backup_dest}" 2>/dev/null || continue

      hash="$(ccq_string_fingerprint "$(cat "${rules_pattern}" 2>/dev/null || true)")"
      file_timestamp="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "${rules_pattern}" 2>/dev/null || echo "${created_at}")"

      files_array+=("{\"source\":\"${rules_pattern}\",\"relative\":\"${relative_path}\",\"hash\":\"${hash}\",\"timestamp\":\"${file_timestamp}\"}")
    fi
  done

  # 生成 manifest.json
  local manifest_content
  manifest_content="$(printf '{"createdAt":"%s","files":[%s]}' "${created_at}" "$(IFS=,; printf '%s' "${files_array[*]}")")"

  printf '%s' "${manifest_content}" | node -e "
    const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    console.log(JSON.stringify(data, null, 2));
  " > "${snapshot_dir}/manifest.json" 2>/dev/null || true

  printf '%s\n' "${snapshot_dir}"
}

ccq_cleanup_old_snapshots() {
  local current_snapshot="${1:-}"
  local snapshot_base="${TMPDIR:-/tmp}/ccq-backups"

  [ ! -d "${snapshot_base}" ] && return 0

  local snapshots=()
  local now_epoch cutoff_epoch
  now_epoch="$(date '+%s')"
  cutoff_epoch=$((now_epoch - 30 * 86400))  # 30 天前

  # 收集所有 snapshot 目录
  for snapshot_dir in "${snapshot_base}"/update_*; do
    [ ! -d "${snapshot_dir}" ] && continue
    [ "${snapshot_dir}" = "${current_snapshot}" ] && continue

    local dir_mtime
    dir_mtime="$(stat -f '%m' "${snapshot_dir}" 2>/dev/null || echo 0)"

    # 删除超过 30 天的
    if [ "${dir_mtime}" -lt "${cutoff_epoch}" ]; then
      rm -rf "${snapshot_dir}" 2>/dev/null || true
      continue
    fi

    snapshots+=("${dir_mtime}:${snapshot_dir}")
  done

  # 保留最新 5 个
  if [ "${#snapshots[@]}" -gt 5 ]; then
    local sorted_snapshots
    sorted_snapshots=($(printf '%s\n' "${snapshots[@]}" | sort -rn))

    local i=0
    for entry in "${sorted_snapshots[@]}"; do
      i=$((i + 1))
      if [ "${i}" -gt 5 ]; then
        local snapshot_path="${entry#*:}"
        rm -rf "${snapshot_path}" 2>/dev/null || true
      fi
    done
  fi
}

# ============ SHA-256 指纹计算 ============

ccq_string_fingerprint() {
  local input="${1:-}"
  local hash=""

  # 优先使用 shasum
  if command -v shasum >/dev/null 2>&1; then
    hash="$(printf '%s' "${input}" | shasum -a 256 | awk '{print $1}')"
  elif command -v openssl >/dev/null 2>&1; then
    hash="$(printf '%s' "${input}" | openssl dgst -sha256 | awk '{print $NF}')"
  else
    return 1
  fi

  printf '%s\n' "${hash}"
}

# ============ 备份清理 ============

ccq_cleanup_old_backups() {
  local max_days="${1:-7}"
  local max_count="${2:-5}"

  [ ! -d "${CCQ_BACKUP_DIR}" ] && return 0

  local now_epoch cutoff_epoch
  now_epoch="$(date '+%s')"
  cutoff_epoch=$((now_epoch - max_days * 86400))

  # 按文件基名分组
  local base_files=()
  for backup_file in "${CCQ_BACKUP_DIR}"/*.bak; do
    [ ! -f "${backup_file}" ] && continue

    local file_mtime base_name
    file_mtime="$(stat -f '%m' "${backup_file}" 2>/dev/null || echo 0)"
    base_name="$(basename "${backup_file}" | sed 's/\.[^.]*\.[0-9_]*\.bak$//')"

    # 删除超过 max_days 天的
    if [ "${file_mtime}" -lt "${cutoff_epoch}" ]; then
      rm -f "${backup_file}" 2>/dev/null || true
      continue
    fi

    base_files+=("${file_mtime}:${base_name}:${backup_file}")
  done

  # 按基名分组，保留每组最新 max_count 个
  local processed_bases=()
  for entry in $(printf '%s\n' "${base_files[@]}" | sort -t: -k2,2 -k1,1rn); do
    local base_name="${entry#*:}"; base_name="${base_name%:*}"
    local backup_file="${entry##*:}"

    # 统计该 base_name 已保留的数量
    local count=0
    for pb in "${processed_bases[@]}"; do
      [ "${pb}" = "${base_name}" ] && count=$((count + 1))
    done

    if [ "${count}" -ge "${max_count}" ]; then
      rm -f "${backup_file}" 2>/dev/null || true
    else
      processed_bases+=("${base_name}")
    fi
  done
}
