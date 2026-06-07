#!/usr/bin/env zsh
# Bootstrap.zsh - macOS 步骤生命周期调度
# 功能: 实时检测生命周期、依赖检查、拓扑排序和 Success/Failed/Skipped/Unsupported/ManualRequired 状态

if [ -n "${CCQ_BOOTSTRAP_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_BOOTSTRAP_ZSH_LOADED=1

CCQ_STEP_STATUS_PENDING="Pending"
CCQ_STEP_STATUS_RUNNING="Running"
CCQ_STEP_STATUS_SUCCESS="Success"
CCQ_STEP_STATUS_FAILED="Failed"
CCQ_STEP_STATUS_SKIPPED="Skipped"
CCQ_STEP_STATUS_UNSUPPORTED="Unsupported"
CCQ_STEP_STATUS_MANUAL_REQUIRED="ManualRequired"

CCQ_STATE_STEP_IDS=()
CCQ_STATE_STEP_STATUSES=()
CCQ_STATE_STEP_MESSAGES=()
CCQ_STATE_STEP_DATA=()

ccq_state_index_of() {
  local step_id="${1:-}"
  local i=1
  while [ "${i}" -le "${#CCQ_STATE_STEP_IDS[@]}" ]; do
    if [ "${CCQ_STATE_STEP_IDS[$i]}" = "${step_id}" ]; then
      printf '%s\n' "${i}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

ccq_state_set_step() {
  local step_id="${1:-}"
  local status="${2:-Pending}"
  local message="${3:-}"
  local data="${4:-}"
  local idx
  idx="$(ccq_state_index_of "${step_id}" 2>/dev/null || true)"
  if [ -z "${idx}" ]; then
    CCQ_STATE_STEP_IDS+=("${step_id}")
    CCQ_STATE_STEP_STATUSES+=("${status}")
    CCQ_STATE_STEP_MESSAGES+=("${message}")
    CCQ_STATE_STEP_DATA+=("${data}")
  else
    CCQ_STATE_STEP_STATUSES[$idx]="${status}"
    CCQ_STATE_STEP_MESSAGES[$idx]="${message}"
    CCQ_STATE_STEP_DATA[$idx]="${data}"
  fi
}

ccq_state_get_status() {
  local idx
  idx="$(ccq_state_index_of "${1:-}" 2>/dev/null || true)"
  [ -n "${idx}" ] || return 1
  printf '%s\n' "${CCQ_STATE_STEP_STATUSES[$idx]}"
}

ccq_normalize_success() {
  local value="${1:-}"
  case "${value}" in
    true|True|TRUE|1|yes|Yes|success|Success) return 0 ;;
    *) return 1 ;;
  esac
}

ccq_call_step_function() {
  local function_name="${1:-}"
  [ -n "${function_name}" ] || return 1
  if ! command -v "${function_name}" >/dev/null 2>&1; then
    CCQ_LAST_STEP_MESSAGE="函数不存在: ${function_name}"
    return 127
  fi
  "${function_name}"
}

ccq_parse_result_field() {
  local result="${1:-}"
  local field="${2:-}"
  printf '%s\n' "${result}" | awk -F= -v key="${field}" '$1 == key { sub(/^[^=]*=/, ""); print; found=1 } END { if (!found) exit 1 }'
}

ccq_result_is_installed() {
  local result="${1:-}"
  local value
  value="$(ccq_parse_result_field "${result}" "IsInstalled" 2>/dev/null || true)"
  ccq_normalize_success "${value}"
}

ccq_result_is_success() {
  local result="${1:-}"
  local value
  value="$(ccq_parse_result_field "${result}" "Success" 2>/dev/null || true)"
  ccq_normalize_success "${value}"
}

ccq_test_step_dependencies() {
  local step_id="${1:-}"
  local deps dep dep_status dep_test dep_result
  deps="$(ccq_get_step_field "${step_id}" Dependencies 2>/dev/null || true)"
  [ -z "${deps}" ] && return 0

  for dep in ${deps}; do
    dep_status="$(ccq_state_get_status "${dep}" 2>/dev/null || true)"
    case "${dep_status}" in
      "${CCQ_STEP_STATUS_SUCCESS}"|"${CCQ_STEP_STATUS_SKIPPED}") continue ;;
      "${CCQ_STEP_STATUS_FAILED}"|"${CCQ_STEP_STATUS_UNSUPPORTED}"|"${CCQ_STEP_STATUS_MANUAL_REQUIRED}")
        CCQ_LAST_STEP_MESSAGE="依赖 ${dep} 状态为 ${dep_status}"
        return 1
        ;;
    esac

    dep_test="$(ccq_get_step_field "${dep}" TestFunction 2>/dev/null || true)"
    if [ -n "${dep_test}" ] && command -v "${dep_test}" >/dev/null 2>&1; then
      dep_result="$(${dep_test} 2>/dev/null || true)"
      if ccq_result_is_installed "${dep_result}"; then
        continue
      fi
    fi
    CCQ_LAST_STEP_MESSAGE="依赖未满足: ${dep}"
    return 1
  done
  return 0
}

ccq_invoke_step_lifecycle() {
  local step_id="${1:-}"
  [ -z "${step_id}" ] && return 1

  local step_name test_function install_function verify_function skip_if_installed
  step_name="$(ccq_get_step_field "${step_id}" StepName 2>/dev/null || printf '%s' "${step_id}")"
  test_function="$(ccq_get_step_field "${step_id}" TestFunction 2>/dev/null || true)"
  install_function="$(ccq_get_step_field "${step_id}" InstallFunction 2>/dev/null || true)"
  verify_function="$(ccq_get_step_field "${step_id}" VerifyFunction 2>/dev/null || true)"
  skip_if_installed="$(ccq_get_step_field "${step_id}" SkipIfInstalled 2>/dev/null || printf 'false')"

  ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_RUNNING}" ""

  if ! ccq_test_step_dependencies "${step_id}"; then
    ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_SKIPPED}" "${CCQ_LAST_STEP_MESSAGE:-依赖未满足}"
    command -v ccq_show_step_progress >/dev/null 2>&1 && ccq_show_step_progress "${step_name}" "Skipped" "${CCQ_LAST_STEP_MESSAGE:-依赖未满足}"
    return 0
  fi

  local test_result=""
  if [ -n "${test_function}" ] && command -v "${test_function}" >/dev/null 2>&1; then
    test_result="$(${test_function} 2>/dev/null || true)"
    if ccq_result_is_installed "${test_result}" && ccq_normalize_success "${skip_if_installed}"; then
      ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_SKIPPED}" "组件已安装，跳过安装" "${test_result}"
      command -v ccq_show_step_progress >/dev/null 2>&1 && ccq_show_step_progress "${step_name}" "Skipped" "组件已安装，跳过安装"
      return 0
    fi
  fi

  if [ -z "${install_function}" ] || ! command -v "${install_function}" >/dev/null 2>&1; then
    ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_MANUAL_REQUIRED}" "安装函数不存在: ${install_function}"
    command -v ccq_show_step_progress >/dev/null 2>&1 && ccq_show_step_progress "${step_name}" "ManualRequired" "安装函数不存在"
    return 0
  fi

  local install_result
  install_result="$(${install_function} 2>&1)"
  if ! ccq_result_is_success "${install_result}"; then
    local status
    status="$(ccq_parse_result_field "${install_result}" "Status" 2>/dev/null || true)"
    case "${status}" in
      Unsupported) ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_UNSUPPORTED}" "${install_result}" ;;
      ManualRequired) ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_MANUAL_REQUIRED}" "${install_result}" ;;
      *) ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_FAILED}" "${install_result}" ;;
    esac
    command -v ccq_show_step_progress >/dev/null 2>&1 && ccq_show_step_progress "${step_name}" "$(ccq_state_get_status "${step_id}")" "安装未完成"
    return 1
  fi

  if [ -n "${verify_function}" ] && command -v "${verify_function}" >/dev/null 2>&1; then
    local verify_result
    verify_result="$(${verify_function} 2>&1)"
    if ! ccq_result_is_success "${verify_result}"; then
      ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_FAILED}" "${verify_result}"
      command -v ccq_show_step_progress >/dev/null 2>&1 && ccq_show_step_progress "${step_name}" "Failed" "验证失败"
      return 1
    fi
  fi

  ccq_state_set_step "${step_id}" "${CCQ_STEP_STATUS_SUCCESS}" "步骤安装成功" "${install_result}"
  command -v ccq_show_step_progress >/dev/null 2>&1 && ccq_show_step_progress "${step_name}" "Success" "步骤安装成功"
}

ccq_run_steps() {
  local ordered
  ordered="$(ccq_get_execution_order "$@")" || return 1
  local step_id
  for step_id in ${ordered}; do
    ccq_invoke_step_lifecycle "${step_id}" || return 1
  done
}
