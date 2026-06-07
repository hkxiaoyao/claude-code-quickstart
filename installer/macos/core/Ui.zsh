#!/usr/bin/env zsh
# Ui.zsh - macOS 终端 UI 组件
# 功能: 语义输出、状态标签、单选/多选菜单与非 ANSI 降级

if [ -n "${CCQ_UI_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_UI_ZSH_LOADED=1

: "${CCQ_OUTPUT_MODE:=normal}"
: "${CCQ_SUPPORTS_ANSI:=auto}"

ccq_detect_ansi() {
  if [ "${CCQ_SUPPORTS_ANSI}" = "0" ] || [ "${NO_COLOR:-}" != "" ]; then
    return 1
  fi
  if [ "${CCQ_SUPPORTS_ANSI}" = "1" ]; then
    return 0
  fi
  [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]
}

if ccq_detect_ansi; then
  CCQ_ANSI_RESET='\033[0m'
  CCQ_ANSI_SUCCESS='\033[92m'
  CCQ_ANSI_PRIMARY='\033[38;2;217;119;87m'
  CCQ_ANSI_WARNING='\033[93m'
  CCQ_ANSI_DANGER='\033[91m'
  CCQ_ANSI_INFO='\033[97m'
  CCQ_ANSI_DIM='\033[90m'
else
  CCQ_ANSI_RESET=''
  CCQ_ANSI_SUCCESS=''
  CCQ_ANSI_PRIMARY=''
  CCQ_ANSI_WARNING=''
  CCQ_ANSI_DANGER=''
  CCQ_ANSI_INFO=''
  CCQ_ANSI_DIM=''
fi

ccq_set_output_mode() {
  case "${1:-normal}" in
    normal|developer) CCQ_OUTPUT_MODE="$1" ;;
    *) CCQ_OUTPUT_MODE="normal" ;;
  esac
}

ccq_should_print_level() {
  local level="${1:-essential}"
  if [ "${CCQ_OUTPUT_MODE}" = "developer" ]; then
    return 0
  fi
  [ "${level}" = "essential" ]
}

ccq_ui_write() {
  local type="${1:-info}"
  local message="${2:-}"
  local level="${3:-essential}"
  local newline="${4:-1}"
  local color="${CCQ_ANSI_INFO}"

  ccq_should_print_level "${level}" || return 0

  case "${type}" in
    success) color="${CCQ_ANSI_SUCCESS}" ;;
    primary) color="${CCQ_ANSI_PRIMARY}" ;;
    warning) color="${CCQ_ANSI_WARNING}" ;;
    danger) color="${CCQ_ANSI_DANGER}" ;;
    dim) color="${CCQ_ANSI_DIM}" ;;
    info|*) color="${CCQ_ANSI_INFO}" ;;
  esac

  if [ "${newline}" = "0" ]; then
    printf "%b%s%b" "${color}" "${message}" "${CCQ_ANSI_RESET}"
  else
    printf "%b%s%b\n" "${color}" "${message}" "${CCQ_ANSI_RESET}"
  fi
}

ccq_ui_success() { ccq_ui_write success "${1:-}" "${2:-essential}" "${3:-1}"; }
ccq_ui_primary() { ccq_ui_write primary "${1:-}" "${2:-essential}" "${3:-1}"; }
ccq_ui_warning() { ccq_ui_write warning "${1:-}" "${2:-essential}" "${3:-1}"; }
ccq_ui_danger() { ccq_ui_write danger "${1:-}" "${2:-essential}" "${3:-1}"; }
ccq_ui_info() { ccq_ui_write info "${1:-}" "${2:-essential}" "${3:-1}"; }
ccq_ui_dim() { ccq_ui_write dim "${1:-}" "${2:-essential}" "${3:-1}"; }

ccq_status_label() {
  case "${1:-}" in
    Success|success|PASS|pass) printf '[PASS]' ;;
    Failed|failed|FAIL|fail) printf '[FAIL]' ;;
    Skipped|skipped|SKIP|skip) printf '[SKIP]' ;;
    Unsupported|unsupported) printf '[UNSUPPORTED]' ;;
    ManualRequired|manual|required) printf '[MANUAL]' ;;
    Running|running) printf '[RUN]' ;;
    Pending|pending) printf '[PENDING]' ;;
    *) printf '[INFO]' ;;
  esac
}

ccq_show_step_progress() {
  local step_name="${1:-}"
  local status="${2:-Info}"
  local message="${3:-}"
  local label
  label="$(ccq_status_label "${status}")"
  case "${status}" in
    Success|success|PASS|pass) ccq_ui_success "${label} ${step_name} ${message}" ;;
    Failed|failed|FAIL|fail) ccq_ui_danger "${label} ${step_name} ${message}" ;;
    Skipped|skipped|SKIP|skip|Unsupported|unsupported|ManualRequired|manual|required) ccq_ui_warning "${label} ${step_name} ${message}" ;;
    *) ccq_ui_info "${label} ${step_name} ${message}" ;;
  esac
}

ccq_string_display_width() {
  # macOS core 先使用字符数近似，后续入口可按需要替换为 CJK-aware 实现。
  local text="${1:-}"
  printf '%s' "${#text}"
}

ccq_display_pad() {
  local text="${1:-}"
  local width="${2:-0}"
  local current padding
  current="$(ccq_string_display_width "${text}")"
  if [ "${current}" -ge "${width}" ]; then
    printf '%s' "${text}"
    return 0
  fi
  padding=$((width - current))
  printf '%s%*s' "${text}" "${padding}" ''
}

ccq_show_banner() {
  local title="${1:-Claude Code Quickstart}"
  local width=72
  local title_len pad_left pad_right
  title_len=${#title}
  if [ "${title_len}" -gt 66 ]; then
    title="${title:0:66}"
    title_len=${#title}
  fi
  pad_left=$(((width - title_len) / 2))
  pad_right=$((width - title_len - pad_left))
  ccq_ui_primary "+$(printf '%*s' "${width}" '' | tr ' ' '-')+"
  ccq_ui_primary "|$(printf '%*s' "${pad_left}" '')${title}$(printf '%*s' "${pad_right}" '')|"
  ccq_ui_primary "+$(printf '%*s' "${width}" '' | tr ' ' '-')+"
}

ccq_select_single() {
  local title="${1:-请选择}"
  shift || true
  local options=("$@")
  local count="${#options[@]}"
  local choice

  if [ "${count}" -eq 0 ]; then
    return 1
  fi

  ccq_ui_primary "${title}"
  local i=1
  for option in "${options[@]}"; do
    ccq_ui_info "  ${i}) ${option}"
    i=$((i + 1))
  done

  while true; do
    printf '请输入编号 [1-%s]，或 q 取消: ' "${count}"
    IFS= read -r choice || return 1
    case "${choice}" in
      q|Q) return 1 ;;
      ''|*[!0-9]*) ccq_ui_warning "请输入有效编号" ;;
      *)
        if [ "${choice}" -ge 1 ] && [ "${choice}" -le "${count}" ]; then
          printf '%s\n' $((choice - 1))
          return 0
        fi
        ccq_ui_warning "编号超出范围"
        ;;
    esac
  done
}

ccq_select_multi() {
  local title="${1:-请选择}"
  shift || true
  local options=("$@")
  local count="${#options[@]}"
  local choice

  if [ "${count}" -eq 0 ]; then
    return 1
  fi

  ccq_ui_primary "${title}"
  local i=1
  for option in "${options[@]}"; do
    ccq_ui_info "  ${i}) ${option}"
    i=$((i + 1))
  done
  printf '请输入编号，多个用空格分隔，或 q 取消: '
  IFS= read -r choice || return 1
  case "${choice}" in
    q|Q|'') return 1 ;;
  esac

  local selected=()
  local item
  for item in ${choice}; do
    case "${item}" in
      ''|*[!0-9]*) continue ;;
      *)
        if [ "${item}" -ge 1 ] && [ "${item}" -le "${count}" ]; then
          selected+=("$((item - 1))")
        fi
        ;;
    esac
  done

  if [ "${#selected[@]}" -eq 0 ]; then
    return 1
  fi
  printf '%s\n' "${selected[@]}"
}
