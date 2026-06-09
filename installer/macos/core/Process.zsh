#!/usr/bin/env zsh
# Process.zsh - macOS 外部命令执行封装
# 功能: 命令检测、版本提取、超时执行、npm/npx 包装

if [ -n "${CCQ_PROCESS_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_PROCESS_ZSH_LOADED=1

: "${CCQ_DEFAULT_TIMEOUT_SECONDS:=300}"
: "${CCQ_DEFAULT_RETRY_COUNT:=3}"

ccq_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ccq_resolve_command() {
  command -v "$1" 2>/dev/null || true
}

ccq_join_args_for_display() {
  local command_name="${1:-}"
  shift || true
  local text="${command_name}"
  local arg
  for arg in "$@"; do
    text="${text} ${arg}"
  done
  printf '%s' "${text}"
}

ccq_run_command_once() {
  local timeout_seconds="${1:-${CCQ_DEFAULT_TIMEOUT_SECONDS}}"
  local suppress_output="${2:-0}"
  shift 2 || true

  local output_file error_file exit_code
  output_file="$(mktemp -t ccq_cmd_out.XXXXXX)" || return 1
  error_file="$(mktemp -t ccq_cmd_err.XXXXXX)" || { rm -f "${output_file}"; return 1; }

  if ccq_command_exists timeout; then
    timeout "${timeout_seconds}" "$@" >"${output_file}" 2>"${error_file}"
    exit_code=$?
  else
    "$@" >"${output_file}" 2>"${error_file}"
    exit_code=$?
  fi

  CCQ_LAST_EXIT_CODE="${exit_code}"
  CCQ_LAST_OUTPUT="$(cat "${output_file}" 2>/dev/null || true)"
  CCQ_LAST_ERROR="$(cat "${error_file}" 2>/dev/null || true)"
  rm -f "${output_file}" "${error_file}"

  if [ "${suppress_output}" != "1" ] && [ -n "${CCQ_LAST_OUTPUT}" ]; then
    printf '%s\n' "${CCQ_LAST_OUTPUT}"
  fi

  [ "${exit_code}" -eq 0 ]
}

ccq_run_command() {
  local timeout_seconds="${CCQ_DEFAULT_TIMEOUT_SECONDS}"
  local retry_count="${CCQ_DEFAULT_RETRY_COUNT}"
  local suppress_output=0
  local working_directory=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --timeout)
        timeout_seconds="$2"
        shift 2
        ;;
      --retries)
        retry_count="$2"
        shift 2
        ;;
      --suppress-output)
        suppress_output=1
        shift
        ;;
      --working-directory)
        working_directory="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  if [ "$#" -eq 0 ]; then
    CCQ_LAST_EXIT_CODE=127
    CCQ_LAST_OUTPUT=""
    CCQ_LAST_ERROR="未提供命令"
    return 127
  fi

  local attempt=0
  local max_attempts=$((retry_count + 1))
  local display_command
  display_command="$(ccq_join_args_for_display "$@")"

  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))
    if [ -n "${working_directory}" ]; then
      (cd "${working_directory}" && ccq_run_command_once "${timeout_seconds}" "${suppress_output}" "$@")
    else
      ccq_run_command_once "${timeout_seconds}" "${suppress_output}" "$@"
    fi
    local command_status=$?
    if [ "${command_status}" -eq 0 ]; then
      return 0
    fi
    if [ "${attempt}" -lt "${max_attempts}" ]; then
      if command -v ccq_ui_warning >/dev/null 2>&1; then
        ccq_ui_warning "命令失败，准备重试(${attempt}/${retry_count}): ${display_command}"
      fi
      sleep $((attempt * 2))
    fi
  done

  return "${CCQ_LAST_EXIT_CODE:-1}"
}

ccq_get_command_version() {
  local command_name="${1:-}"
  local output=""
  if [ -z "${command_name}" ] || ! ccq_command_exists "${command_name}"; then
    return 1
  fi

  output="$(${command_name} --version 2>/dev/null | head -n 1 || true)"
  if [ -z "${output}" ]; then
    output="$(${command_name} -v 2>/dev/null | head -n 1 || true)"
  fi
  printf '%s\n' "${output}"
}

ccq_refresh_path() {
  # macOS 当前 shell 通常无需全量刷新；补充常见 Homebrew、nvm 与 npm 前缀。
  local brew_prefix=""
  if ccq_command_exists brew; then
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [ -n "${brew_prefix}" ]; then
      case ":${PATH}:" in
        *":${brew_prefix}/bin:"*) ;;
        *) PATH="${brew_prefix}/bin:${PATH}" ;;
      esac
      case ":${PATH}:" in
        *":${brew_prefix}/sbin:"*) ;;
        *) PATH="${brew_prefix}/sbin:${PATH}" ;;
      esac
    fi
  fi

  case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) PATH="${HOME}/.local/bin:${PATH}" ;;
  esac

  local nvm_dir="${NVM_DIR:-}"
  if [ -z "${nvm_dir}" ]; then
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
      nvm_dir="${XDG_CONFIG_HOME%/}/nvm"
    else
      nvm_dir="${HOME}/.nvm"
    fi
  fi
  nvm_dir="${nvm_dir%/}"
  if [ -s "${nvm_dir}/nvm.sh" ]; then
    export NVM_DIR="${nvm_dir}"
    . "${nvm_dir}/nvm.sh" >/dev/null 2>&1 || true
    if ccq_command_exists nvm; then
      nvm use --silent default >/dev/null 2>&1 || nvm use --silent 'lts/*' >/dev/null 2>&1 || true
    fi
  fi

  if ccq_command_exists npm; then
    local npm_prefix
    npm_prefix="$(npm prefix -g 2>/dev/null || true)"
    if [ -n "${npm_prefix}" ]; then
      case ":${PATH}:" in
        *":${npm_prefix}/bin:"*) ;;
        *) PATH="${npm_prefix}/bin:${PATH}" ;;
      esac
    fi
  fi
  export PATH
}

ccq_npm_global_install() {
  local package_name="${1:-}"
  local version="${2:-}"
  local full_package="${package_name}"
  if [ -z "${package_name}" ]; then
    CCQ_LAST_ERROR="npm 包名不能为空"
    return 1
  fi
  if [ -n "${version}" ]; then
    full_package="${package_name}@${version}"
  fi
  ccq_run_command --timeout 300 --retries 3 -- npm install -g "${full_package}"
}

ccq_npx() {
  ccq_run_command --timeout "${CCQ_DEFAULT_TIMEOUT_SECONDS}" --retries 0 -- npx "$@"
}
