#!/usr/bin/env zsh
# Profile.zsh - macOS Profile 安全编辑
# 功能: 托管标记块、子段写入、备份、原子替换和重复写入收敛

if [ -n "${CCQ_PROFILE_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_PROFILE_ZSH_LOADED=1

CCQ_MANAGED_BLOCK_START="# >>> Claude Code Quickstart >>>"
CCQ_MANAGED_BLOCK_END="# <<< Claude Code Quickstart <<<"
: "${CCQ_BACKUP_DIR:=${TMPDIR:-/tmp}/ccq-backups}"

# ── 契约加载（contracts-first + inline fallback）──

ccq_cleanup_policy_contracts_root() {
  local installer_root="${CCQ_INSTALLER_ROOT:-}"
  if [ -z "${installer_root}" ]; then
    installer_root="$(cd "${0:A:h}/../.." 2>/dev/null && pwd)"
  fi
  [ -d "${installer_root}/contracts" ] && printf '%s\n' "${installer_root}/contracts"
}

ccq_cleanup_policy_contract_path() {
  if [ -n "${CCQ_CLEANUP_POLICY_CONTRACT:-}" ]; then
    printf '%s\n' "${CCQ_CLEANUP_POLICY_CONTRACT}"
    return 0
  fi
  local contracts_root
  contracts_root="$(ccq_cleanup_policy_contracts_root)"
  [ -n "${contracts_root}" ] && printf '%s\n' "${contracts_root}/cleanup-policy.json"
}

ccq_cleanup_policy_contract() {
  local contract_path
  contract_path="$(ccq_cleanup_policy_contract_path)"
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

# ============ Subsection API（统一标记格式：# [CCQ:NAME:BEGIN/END]）============

ccq_test_subsection_markers_present() {
  local content="${1:-}"
  [ -z "${content}" ] && return 1
  printf '%s\n' "${content}" | grep -qE '^\s*#\s*\[CCQ:[A-Za-z0-9_-]+:(BEGIN|END)\]\s*$'
}

ccq_convert_legacy_block_to_subsection() {
  local content="${1:-}"
  local legacy_section="${2:-FNM}"
  printf '# [CCQ:%s:BEGIN]\n%s\n# [CCQ:%s:END]\n' "${legacy_section}" "${content%$'\n'}" "${legacy_section}"
}

ccq_remove_ccq_function_blocks() {
  local content="${1:-}"
  [ -z "${content}" ] && return 0

  printf '%s\n' "${content}" | awk '
    !skipping && /^[[:space:]]*function[[:space:]]+ccq[[:space:]]*\{[[:space:]]*$/ {
      skipping = 1
      brace_depth = 1
      next
    }
    skipping {
      brace_depth += gsub(/\{/, "&")
      brace_depth -= gsub(/\}/, "&")
      if (brace_depth <= 0) {
        skipping = 0
        brace_depth = 0
      }
      next
    }
    !skipping { print }
  '
}

ccq_migrate_to_subsections() {
  local file_path="${1:-}"
  [ ! -f "${file_path}" ] && return 1

  local block_content
  block_content="$(ccq_get_managed_block_content "${file_path}" 2>/dev/null || true)"
  [ -z "${block_content}" ] && return 1

  # 检查是否已有子段标记
  if ccq_test_subsection_markers_present "${block_content}"; then
    # 检查是否存在裸内容（不在任何子段内的非空行）
    local has_fnm_begin=0 has_fnm_end=0 has_bare_content=0
    local in_any_section=0

    while IFS= read -r line; do
      local trimmed="${line##*([[:space:]])}"
      trimmed="${trimmed%%*([[:space:]])}"

      [ "${trimmed}" = "# [CCQ:FNM:BEGIN]" ] && { has_fnm_begin=1; in_any_section=1; continue; }
      [ "${trimmed}" = "# [CCQ:FNM:END]" ] && { has_fnm_end=1; in_any_section=0; continue; }

      printf '%s\n' "${trimmed}" | grep -qE '^\s*#\s*\[CCQ:[A-Za-z0-9_-]+:BEGIN\]\s*$' && { in_any_section=1; continue; }
      printf '%s\n' "${trimmed}" | grep -qE '^\s*#\s*\[CCQ:[A-Za-z0-9_-]+:END\]\s*$' && { in_any_section=0; continue; }

      # 跳过损坏的空名称标记
      printf '%s\n' "${trimmed}" | grep -qE '^\s*#\s*\[CCQ:[^A-Za-z0-9_-]*\]\s*$' && continue

      # 不在任何子段内的非空行 = 裸内容
      [ ${in_any_section} -eq 0 ] && [ -n "${trimmed}" ] && { has_bare_content=1; break; }
    done <<< "${block_content}"

    # 存在裸内容且 FNM 标记不完整时，将裸内容收敛为 FNM 子段
    if [ ${has_bare_content} -eq 1 ] && { [ ${has_fnm_begin} -eq 0 ] || [ ${has_fnm_end} -eq 0 ]; }; then
      local fnm_lines=() other_lines=()
      in_any_section=0

      while IFS= read -r line; do
        local trimmed="${line##*([[:space:]])}"
        trimmed="${trimmed%%*([[:space:]])}"

        # 跳过残留的 FNM 标记
        [ "${trimmed}" = "# [CCQ:FNM:BEGIN]" ] || [ "${trimmed}" = "# [CCQ:FNM:END]" ] && continue

        # 跳过损坏的空名称标记
        printf '%s\n' "${trimmed}" | grep -qE '^\s*#\s*\[CCQ:[^A-Za-z0-9_-]*\]\s*$' && continue

        if printf '%s\n' "${trimmed}" | grep -qE '^\s*#\s*\[CCQ:[A-Za-z0-9_-]+:BEGIN\]\s*$'; then
          in_any_section=1
          other_lines+=("${line}")
          continue
        fi

        if printf '%s\n' "${trimmed}" | grep -qE '^\s*#\s*\[CCQ:[A-Za-z0-9_-]+:END\]\s*$'; then
          in_any_section=0
          other_lines+=("${line}")
          continue
        fi

        if [ ${in_any_section} -eq 1 ]; then
          other_lines+=("${line}")
        else
          fnm_lines+=("${line}")
        fi
      done <<< "${block_content}"

      local result="# [CCQ:FNM:BEGIN]"
      for l in "${fnm_lines[@]}"; do result="${result}"$'\n'"${l}"; done
      result="${result}"$'\n'"# [CCQ:FNM:END]"
      for l in "${other_lines[@]}"; do result="${result}"$'\n'"${l}"; done

      ccq_set_managed_block_in_file "${file_path}" "${result}"
      return $?
    fi

    # FNM 标记完整或无裸内容，幂等成功
    return 0
  fi

  # 旧块无子段标记，包装为 FNM 子段
  local migrated
  migrated="$(ccq_convert_legacy_block_to_subsection "${block_content}" "FNM")"
  ccq_set_managed_block_in_file "${file_path}" "${migrated}"
}

ccq_set_subsection() {
  local file_path="${1:-}"
  local section="${2:-}"
  local section_content="${3:-}"
  [ -z "${file_path}" ] || [ -z "${section}" ] && return 1

  local block_content
  block_content="$(ccq_get_managed_block_content "${file_path}" 2>/dev/null || true)"
  [ -z "${block_content}" ] && return 1

  local begin_marker="# [CCQ:${section}:BEGIN]"
  local end_marker="# [CCQ:${section}:END]"

  local begin_idx=-1 end_idx=-1 idx=0
  local lines_array=()

  while IFS= read -r line; do
    lines_array+=("${line}")
    local trimmed="${line##*([[:space:]])}"
    trimmed="${trimmed%%*([[:space:]])}"

    [ "${trimmed}" = "${begin_marker}" ] && begin_idx=${idx}
    [ "${trimmed}" = "${end_marker}" ] && { end_idx=${idx}; break; }
    idx=$((idx + 1))
  done <<< "${block_content}"

  local new_block=""

  if [ ${begin_idx} -ge 0 ] && [ ${end_idx} -gt ${begin_idx} ]; then
    # 子段存在，替换
    for ((i = 0; i < begin_idx; i++)); do
      new_block="${new_block}${lines_array[i]}"$'\n'
    done

    new_block="${new_block}${begin_marker}"$'\n'"${section_content%$'\n'}"$'\n'"${end_marker}"

    for ((i = end_idx + 1; i < ${#lines_array[@]}; i++)); do
      new_block="${new_block}"$'\n'"${lines_array[i]}"
    done
  else
    # 子段不存在，追加
    new_block="${block_content}"
    [ -n "${new_block%$'\n'}" ] && new_block="${new_block%$'\n'}"$'\n\n'
    new_block="${new_block}${begin_marker}"$'\n'"${section_content%$'\n'}"$'\n'"${end_marker}"
  fi

  ccq_set_managed_block_in_file "${file_path}" "${new_block}"
}

ccq_set_shortcut_subsection() {
  local file_path="${1:-}"
  local shortcut_content="${2:-}"
  [ -z "${file_path}" ] && return 1

  local block_content
  block_content="$(ccq_get_managed_block_content "${file_path}" 2>/dev/null || true)"
  [ -z "${block_content}" ] && return 1

  # 移除 ccq 函数定义
  local source_lines
  source_lines="$(ccq_remove_ccq_function_blocks "${block_content}")"

  # 移除旧的 SHORTCUTS 子段和损坏的空名称标记
  local normalized="" in_shortcuts=0

  while IFS= read -r line; do
    local trimmed="${line##*([[:space:]])}"
    trimmed="${trimmed%%*([[:space:]])}"

    # 跳过损坏的空名称标记
    printf '%s\n' "${trimmed}" | grep -qE '^\s*#\s*\[CCQ:\s*\]\s*$' && continue

    if [ ${in_shortcuts} -eq 1 ]; then
      if [ "${trimmed}" = "# [CCQ:SHORTCUTS:END]" ]; then
        in_shortcuts=0
        continue
      fi

      # 遇到其他子段标记，退出 SHORTCUTS
      if printf '%s\n' "${trimmed}" | grep -qE '^\s*#\s*\[CCQ:[A-Za-z0-9_-]+:(BEGIN|END)\]\s*$'; then
        [ "${trimmed}" != "# [CCQ:SHORTCUTS:BEGIN]" ] && [ "${trimmed}" != "# [CCQ:SHORTCUTS:END]" ] && in_shortcuts=0
      else
        continue
      fi
    fi

    [ "${trimmed}" = "# [CCQ:SHORTCUTS:BEGIN]" ] && { in_shortcuts=1; continue; }
    [ "${trimmed}" = "# [CCQ:SHORTCUTS:END]" ] && continue

    normalized="${normalized}${line}"$'\n'
  done <<< "${source_lines}"

  # 修剪尾部空行
  while [ -n "${normalized}" ] && [ "${normalized: -1}" = $'\n' ]; do
    local prev="${normalized%$'\n'}"
    [ -z "${prev##*([[:space:]])}" ] && normalized="${prev}" || break
  done

  [ -n "${normalized%$'\n'}" ] && normalized="${normalized%$'\n'}"$'\n\n'

  normalized="${normalized}# [CCQ:SHORTCUTS:BEGIN]"$'\n'"${shortcut_content%$'\n'}"$'\n'"# [CCQ:SHORTCUTS:END]"

  # 内容相等短路
  [ "${normalized%$'\n'}" = "${block_content%$'\n'}" ] && return 0

  ccq_set_managed_block_in_file "${file_path}" "${normalized}"
}

ccq_write_profile_subsection() {
  local file_path="${1:-}"
  local section="${2:-}"
  local section_content="${3:-}"
  [ -z "${file_path}" ] || [ -z "${section}" ] && return 1

  # 1. 迁移旧结构（幂等）
  [ -f "${file_path}" ] && ccq_migrate_to_subsections "${file_path}" 2>/dev/null || true

  # 2. 尝试子段 Upsert
  if ccq_set_subsection "${file_path}" "${section}" "${section_content}" 2>/dev/null; then
    return 0
  fi

  # 3. 降级：托管块不存在时创建新块
  local initial_content
  initial_content="# [CCQ:${section}:BEGIN]"$'\n'"${section_content%$'\n'}"$'\n'"# [CCQ:${section}:END]"
  ccq_set_managed_block_in_file "${file_path}" "${initial_content}"
}

ccq_remove_subsection() {
  local file_path="${1:-}"
  local section="${2:-}"
  [ -z "${file_path}" ] || [ -z "${section}" ] && return 1
  [ ! -f "${file_path}" ] && return 0

  # 迁移旧结构（幂等）
  ccq_migrate_to_subsections "${file_path}" 2>/dev/null || true

  local block_content
  block_content="$(ccq_get_managed_block_content "${file_path}" 2>/dev/null || true)"
  [ -z "${block_content}" ] && return 0

  local begin_marker="# [CCQ:${section}:BEGIN]"
  local end_marker="# [CCQ:${section}:END]"

  # 检测子段是否存在
  printf '%s\n' "${block_content}" | grep -qF "${begin_marker}" || return 0
  printf '%s\n' "${block_content}" | grep -qF "${end_marker}" || return 0

  # 剥离目标子段
  local new_lines="" in_target=0

  while IFS= read -r line; do
    local trimmed="${line##*([[:space:]])}"
    trimmed="${trimmed%%*([[:space:]])}"

    [ "${trimmed}" = "${begin_marker}" ] && { in_target=1; continue; }
    [ ${in_target} -eq 1 ] && [ "${trimmed}" = "${end_marker}" ] && { in_target=0; continue; }
    [ ${in_target} -eq 0 ] && new_lines="${new_lines}${line}"$'\n'
  done <<< "${block_content}"

  # 检查剩余内容是否有实质性内容
  local has_content=0
  while IFS= read -r remain_line; do
    local trimmed="${remain_line##*([[:space:]])}"
    trimmed="${trimmed%%*([[:space:]])}"
    [ -n "${trimmed}" ] && { has_content=1; break; }
  done <<< "${new_lines}"

  if [ ${has_content} -eq 0 ]; then
    # 无实质内容，移除整个托管块
    ccq_remove_managed_block_from_file "${file_path}"
    return $?
  fi

  # 修剪尾部空行
  while [ -n "${new_lines}" ] && [ "${new_lines: -1}" = $'\n' ]; do
    local prev="${new_lines%$'\n'}"
    [ -z "${prev##*([[:space:]])}" ] && new_lines="${prev}" || break
  done

  ccq_set_managed_block_in_file "${file_path}" "${new_lines}"
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
      file_timestamp="$(date -r "$(stat -f %m "${source_file}" 2>/dev/null || echo 0)" -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "${created_at}")"

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
      file_timestamp="$(date -r "$(stat -f %m "${rules_pattern}" 2>/dev/null || echo 0)" -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "${created_at}")"

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
  local snapshot_base="${CCQ_BACKUP_DIR}"

  [ ! -d "${snapshot_base}" ] && return 0

  # 从契约读取策略参数（contracts-first）
  local contract max_snapshots=5 max_age_days=30 recent_minutes_skip=5
  contract="$(ccq_cleanup_policy_contract 2>/dev/null)"
  if [ -n "${contract}" ] && command -v node >/dev/null 2>&1; then
    max_snapshots=$(printf '%s\n' "${contract}" | node -e 'const c=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(c.maxSnapshots||5);' 2>/dev/null || echo 5)
    max_age_days=$(printf '%s\n' "${contract}" | node -e 'const c=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(c.maxAgeInDays||30);' 2>/dev/null || echo 30)
    recent_minutes_skip=$(printf '%s\n' "${contract}" | node -e 'const c=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(c.recentMinutesSkip||5);' 2>/dev/null || echo 5)
  fi

  local snapshots=()
  local now_epoch cutoff_epoch recent_cutoff_epoch
  now_epoch="$(date '+%s')"
  cutoff_epoch=$((now_epoch - max_age_days * 86400))
  recent_cutoff_epoch=$((now_epoch - recent_minutes_skip * 60))

  # 收集所有 snapshot 目录
  for snapshot_dir in "${snapshot_base}"/update_*; do
    [ ! -d "${snapshot_dir}" ] && continue
    [ "${snapshot_dir}" = "${current_snapshot}" ] && continue

    local dir_mtime
    dir_mtime="$(stat -f '%m' "${snapshot_dir}" 2>/dev/null || echo 0)"

    # 跳过最近 N 分钟内创建的目录
    if [ "${dir_mtime}" -gt "${recent_cutoff_epoch}" ]; then
      continue
    fi

    # 删除超过 N 天的
    if [ "${dir_mtime}" -lt "${cutoff_epoch}" ]; then
      rm -rf "${snapshot_dir}" 2>/dev/null || true
      continue
    fi

    snapshots+=("${dir_mtime}:${snapshot_dir}")
  done

  # 保留最新 N 个
  if [ "${#snapshots[@]}" -gt "${max_snapshots}" ]; then
    local sorted_snapshots
    sorted_snapshots=($(printf '%s\n' "${snapshots[@]}" | sort -rn))

    local i=0
    for entry in "${sorted_snapshots[@]}"; do
      i=$((i + 1))
      if [ "${i}" -gt "${max_snapshots}" ]; then
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
