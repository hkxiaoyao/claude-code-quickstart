#!/usr/bin/env zsh
# Skills.zsh - macOS Skills 安装步骤
# 功能: source 单选、集合子 Skills 多选、copy 模式和官方 skills update

if [ -n "${CCQ_STEP_SKILLS_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_SKILLS_ZSH_LOADED=1

ccq_source_npm_common() {
  if command -v ccq_npm_tool_require_npx >/dev/null 2>&1; then return 0; fi
  local common_path="${CCQ_INSTALLER_ROOT:-$(cd "${0:A:h}/../.." && pwd)}/macos/steps/_NpmToolCommon.zsh"
  [ -f "${common_path}" ] && source "${common_path}"
}
ccq_source_npm_common

: "${CCQ_SKILLS_COPY:=0}"

ccq_skills_catalogue() {
  cat <<'EOF'
find-skills	find-skills	vercel-labs/skills	find-skills	Skills 发现辅助技能	true
anthropics-skills	官方 Skills	anthropics/skills		Anthropic 官方 Skills 集合	false
vercel-agent-skills	Vercel Agent Skills	vercel-labs/agent-skills		Vercel Agent Skills 集合	false
vue-skills	Vue Skills	vuejs-ai/skills		Vue 开发 Skills 集合	false
ui-ux-pro-max	UI UX Pro Max	nextlevelbuilder/ui-ux-pro-max-skill		UI/UX 设计与前端体验技能	false
shadcn-ui-skills	shadcn/ui Skills	shadcn/ui		shadcn/ui 组件开发 Skills 集合	false
fastapi-skills	FastAPI Skills	https://github.com/fastapi/fastapi	fastapi	FastAPI 开发 Skills	false
langchain-skills	LangChain Skills	langchain-ai/langchain-skills		LangChain 开发 Skills 集合	false
ppt-master	PPT Master	hugohe3/ppt-master	ppt-master	PPT 生成与演示文稿技能	false	ppt-master
EOF
}

ccq_skills_tty() { [ -r /dev/tty ] && [ -w /dev/tty ]; }

ccq_join_by_comma() {
  local first=1 item
  for item in "$@"; do
    if [ "${first}" = "1" ]; then
      printf '%s' "${item}"
      first=0
    else
      printf ',%s' "${item}"
    fi
  done
}

ccq_skills_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'Message=%s\n' "${3:-}"
}

ccq_skills_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'Installed=%s\n' "${2:-}"
  printf 'ErrorMessage=%s\n' "${3:-}"
}

ccq_skills_installed_json() {
  ccq_npm_tool_require_npx || return 1
  npx --yes skills list -g -a claude-code --json 2>/dev/null || printf '[]\n'
}

ccq_skills_installed_names() {
  ccq_skills_installed_json | node -e '
const fs = require("fs");
const raw = fs.readFileSync(0, "utf8").trim() || "[]";
let items = [];
try { items = JSON.parse(raw); } catch { items = []; }
for (const item of items) if (item && item.name) console.log(item.name);
' 2>/dev/null || true
}

ccq_skills_known_static_names() {
  local line id name source skill desc default static_name
  while IFS=$'\t' read -r id name source skill desc default static_name; do
    if [ -n "${static_name}" ]; then
      printf '%s\n' "${static_name}"
    elif [ -n "${skill}" ]; then
      printf '%s\n' "${skill}"
    fi
  done <<EOF
$(ccq_skills_catalogue)
EOF
}

ccq_skills_any_known_installed() {
  local installed known name
  installed="$(ccq_skills_installed_names)"
  known="$(ccq_skills_known_static_names)"
  for name in ${known}; do
    printf '%s\n' "${installed}" | grep -qi "^${name}$" && return 0
  done
  [ -n "${installed}" ]
}

ccq_skills_source_list() {
  local source="${1:-}"
  local skill="${2:-}"
  local args=(--yes skills add "${source}" --list -g --agent claude-code)
  [ -n "${skill}" ] && args+=(--skill "${skill}")
  ccq_npm_tool_require_npx || return 1
  npx "${args[@]}" 2>/dev/null | node -e '
const fs = require("fs");
const text = fs.readFileSync(0, "utf8").replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "");
const names = new Set();
for (const raw of text.split(/\r?\n/)) {
  const line = raw.trim().replace(/^│/, "").trim();
  if (/^[A-Za-z0-9][A-Za-z0-9:_-]{0,79}$/.test(line)) names.add(line);
}
for (const name of names) console.log(name);
' || true
}

ccq_skills_select_source() {
  ccq_skills_tty || return 1
  local lines line id name source skill desc default static_name options=() records=() choice i=1
  lines="$(ccq_skills_catalogue)"
  while IFS=$'\t' read -r id name source skill desc default static_name; do
    [ -n "${id}" ] || continue
    options+=("${name} - ${desc}")
    records+=("${id}	${name}	${source}	${skill}	${desc}	${default}	${static_name}")
  done <<EOF
${lines}
EOF
  printf '%s\n' "请选择 Skills source" >/dev/tty
  for line in "${options[@]}"; do
    printf '  %s) %s\n' "${i}" "${line}" >/dev/tty
    i=$((i + 1))
  done
  while true; do
    printf '请输入编号 [1-%s]，或 q 取消: ' "${#options[@]}" >/dev/tty
    IFS= read -r choice </dev/tty || return 1
    case "${choice}" in
      q|Q) return 1 ;;
      ''|*[!0-9]*) printf '%s\n' "请输入有效编号" >/dev/tty ;;
      *)
        if [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#options[@]}" ]; then
          printf '%s\n' "${records[$choice]}"
          return 0
        fi
        printf '%s\n' "编号超出范围" >/dev/tty
        ;;
    esac
  done
}

ccq_skills_select_children() {
  local source="${1:-}"
  local skill="${2:-}"
  local names choice item selected=()
  names="$(ccq_skills_source_list "${source}" "${skill}")"
  [ -n "${names}" ] || return 0
  local options=(${names})
  [ "${#options[@]}" -gt 1 ] || { printf '%s\n' "${options[@]}"; return 0; }
  ccq_skills_tty || { printf '%s\n' "${options[@]}"; return 0; }
  printf '%s\n' "请选择要安装的子 Skills（多个用空格分隔，回车默认全选）" >/dev/tty
  local i=1
  for item in "${options[@]}"; do
    printf '  %s) %s\n' "${i}" "${item}" >/dev/tty
    i=$((i + 1))
  done
  printf '请输入编号，或 q 取消: ' >/dev/tty
  IFS= read -r choice </dev/tty || return 1
  case "${choice}" in
    q|Q) return 1 ;;
    '') printf '%s\n' "${options[@]}"; return 0 ;;
  esac
  for item in ${choice}; do
    case "${item}" in
      ''|*[!0-9]*) ;;
      *)
        if [ "${item}" -ge 1 ] && [ "${item}" -le "${#options[@]}" ]; then
          selected+=("${options[$item]}")
        fi
        ;;
    esac
  done
  printf '%s\n' "${selected[@]}"
}

ccq_skills_install_one() {
  local source="${1:-}"
  local skill="${2:-}"
  local args=(--yes skills add "${source}" --yes --agent claude-code -g)
  [ -n "${skill}" ] && args+=(--skill "${skill}")
  [ "${CCQ_SKILLS_COPY}" = "1" ] && args+=(--copy)
  ccq_run_command --timeout 300 --retries 1 -- npx "${args[@]}"
}

Test-SkillsInstalled() {
  ccq_source_npm_common
  if ccq_skills_any_known_installed; then
    ccq_skills_result true "" "已检测到 Claude Code 全局 Skills"
  else
    ccq_skills_result false "" "未检测到已知 Skills"
  fi
}

Install-Skills() {
  ccq_source_npm_common
  if ! ccq_npm_tool_require_npx; then
    ccq_skills_install_result false "" "${CCQ_NPM_TOOL_ERROR:-npx 不可用}"
    return 1
  fi
  if ! ccq_command_exists claude; then
    ccq_skills_install_result false "" "Claude Code 不可用，请先完成 ClaudeCode 步骤"
    return 1
  fi
  local record id name source skill desc default static_name selected_names installed=() failures=() child
  record="$(ccq_skills_select_source)" || { ccq_skills_install_result false "" "用户取消 Skills source 选择"; return 1; }
  IFS=$'\t' read -r id name source skill desc default static_name <<EOF
${record}
EOF
  selected_names="$(ccq_skills_select_children "${source}" "${skill}" || true)"
  if [ -z "${selected_names}" ] && [ -n "${skill}" ]; then
    selected_names="${skill}"
  fi
  if [ -z "${selected_names}" ]; then
    if ccq_skills_install_one "${source}" "" >/dev/null 2>&1; then
      installed+=("${id}")
    else
      failures+=("${id}")
    fi
  else
    for child in ${selected_names}; do
      if ccq_skills_install_one "${source}" "${child}" >/dev/null 2>&1; then
        installed+=("${child}")
      else
        failures+=("${child}")
      fi
    done
  fi
  if [ "${#failures[@]}" -gt 0 ]; then
    ccq_skills_install_result false "$(ccq_join_by_comma "${installed[@]}")" "安装失败: $(ccq_join_by_comma "${failures[@]}")"
    return 1
  fi
  ccq_skills_install_result true "$(ccq_join_by_comma "${installed[@]}")" ""
}

Verify-Skills() {
  if ccq_skills_any_known_installed; then
    printf 'Success=true\nErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\nErrorMessage=Skills 验证失败\n'
  return 1
}

Update-Skills() {
  ccq_source_npm_common
  if ! ccq_npm_tool_require_npx; then
    ccq_step_update_result false "" "" "${CCQ_NPM_TOOL_ERROR:-npx 不可用}"
    return 1
  fi
  if ccq_run_command --timeout 300 --retries 1 -- npx --yes skills update -g -y >/dev/null 2>&1; then
    ccq_step_update_result true "npx::skills::update" "" ""
    return 0
  fi
  ccq_step_update_result false "" "" "Skills 官方 update 失败"
  return 1
}

ccq_skills_remove_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'Removed=%s\n' "${2:-}"
  printf 'ErrorMessage=%s\n' "${3:-}"
}

ccq_skills_select_installed_names() {
  local names name options=() choice item selected=()
  names="$(ccq_skills_installed_names)"
  [ -n "${names}" ] || return 1
  for name in ${names}; do
    options+=("${name}")
  done

  if [ "${#options[@]}" -eq 1 ]; then
    printf '%s\n' "${options[1]}"
    return 0
  fi

  ccq_skills_tty || { printf '%s\n' "${options[@]}"; return 0; }
  printf '%s\n' "请选择要卸载的 Skills（多个用空格分隔，回车取消）" >/dev/tty
  local i=1
  for item in "${options[@]}"; do
    printf '  %s) %s\n' "${i}" "${item}" >/dev/tty
    i=$((i + 1))
  done
  printf '请输入编号，或 q 取消: ' >/dev/tty
  IFS= read -r choice </dev/tty || return 1
  case "${choice}" in
    q|Q|'') return 1 ;;
  esac
  for item in ${choice}; do
    case "${item}" in
      ''|*[!0-9]*) ;;
      *)
        if [ "${item}" -ge 1 ] && [ "${item}" -le "${#options[@]}" ]; then
          selected+=("${options[$item]}")
        fi
        ;;
    esac
  done
  [ "${#selected[@]}" -gt 0 ] || return 1
  printf '%s\n' "${selected[@]}"
}

Uninstall-Skills() {
  ccq_source_npm_common
  if ! ccq_npm_tool_require_npx; then
    ccq_skills_remove_result false "" "${CCQ_NPM_TOOL_ERROR:-npx 不可用}"
    return 1
  fi

  local selected names_arg=() name removed=() confirm
  selected="$(ccq_skills_select_installed_names)" || {
    ccq_skills_remove_result true "" ""
    return 0
  }
  for name in ${selected}; do
    names_arg+=("${name}")
  done

  if ccq_skills_tty; then
    printf '确认卸载这些 Skills：%s ? [y/N] ' "$(ccq_join_by_comma "${names_arg[@]}")" >/dev/tty
    IFS= read -r confirm </dev/tty || confirm=""
    case "${confirm}" in
      y|Y|yes|YES) ;;
      *) ccq_skills_remove_result true "" ""; return 0 ;;
    esac
  fi

  if ccq_run_command --timeout 300 --retries 1 -- npx --yes skills remove "${names_arg[@]}" -g -a claude-code --yes >/dev/null 2>&1; then
    for name in "${names_arg[@]}"; do
      removed+=("${name}")
    done
    ccq_skills_remove_result true "$(ccq_join_by_comma "${removed[@]}")" ""
    return 0
  fi
  ccq_skills_remove_result false "" "Skills 卸载失败"
  return 1
}

ccq_skills_show_status() {
  local names
  names="$(ccq_skills_installed_names)"
  ccq_ui_primary "Skills 状态："
  if [ -n "${names}" ]; then
    printf '%s\n' "${names}" | while IFS= read -r name; do
      [ -n "${name}" ] && ccq_ui_info "  - ${name}"
    done
  else
    ccq_ui_warning "  尚未检测到 Claude Code 全局 Skills"
  fi
}

ccq_skills_manage_menu() {
  local choice
  while true; do
    ccq_skills_show_status
    ccq_skills_tty || return 0
    printf '\nSkills 管理：1) 安装 2) 更新 3) 卸载 q) 返回: ' >/dev/tty
    IFS= read -r choice </dev/tty || return 1
    case "${choice}" in
      q|Q) return 0 ;;
      1) Install-Skills >/dev/null || ccq_ui_warning "Skills 安装失败" ;;
      2) Update-Skills >/dev/null || ccq_ui_warning "Skills 更新失败" ;;
      3) Uninstall-Skills >/dev/null || ccq_ui_warning "Skills 卸载失败" ;;
      *) ccq_ui_warning "未知选项" ;;
    esac
  done
}
