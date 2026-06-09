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

ccq_process_stream_enabled() {
  local suppress_output="${1:-0}"
  [ "${suppress_output}" != "1" ] || return 1
  command -v ccq_output_is_developer >/dev/null 2>&1 || return 1
  ccq_output_is_developer || return 1
  command -v ccq_tty_available >/dev/null 2>&1 || return 1
  ccq_tty_available
}

ccq_process_tty_block() {
  local text="${1:-}"
  [ -n "${text}" ] || return 0
  printf '%s\n' "${text}" > /dev/tty 2>/dev/null || true
}

ccq_run_native_command() {
  if ccq_process_stream_enabled 0; then
    "$@" > >(tee /dev/tty >/dev/null) 2> >(tee /dev/tty >/dev/null)
  else
    "$@" >/dev/null 2>&1
  fi
}

ccq_run_command_once() {
  local timeout_seconds="${1:-${CCQ_DEFAULT_TIMEOUT_SECONDS}}"
  local suppress_output="${2:-0}"
  shift 2 || true

  local output_file error_file heartbeat_file exit_code stream_output=0 heartbeat_pid=""
  output_file="$(mktemp -t ccq_cmd_out.XXXXXX)" || return 1
  error_file="$(mktemp -t ccq_cmd_err.XXXXXX)" || { rm -f "${output_file}"; return 1; }
  heartbeat_file="$(mktemp -t ccq_cmd_heartbeat.XXXXXX)" || { rm -f "${output_file}" "${error_file}"; return 1; }

  if ccq_process_stream_enabled "${suppress_output}"; then
    stream_output=1
    (
      sleep 2 || exit 0
      printf '1' > "${heartbeat_file}" 2>/dev/null || true
      elapsed=2
      while true; do
        printf '\r  等待中... (%s 秒)' "${elapsed}" > /dev/tty 2>/dev/null || true
        sleep 1 || exit 0
        elapsed=$((elapsed + 1))
      done
    ) &
    heartbeat_pid="$!"
  fi

  if ccq_command_exists timeout; then
    timeout "${timeout_seconds}" "$@" >"${output_file}" 2>"${error_file}"
    exit_code=$?
  else
    "$@" >"${output_file}" 2>"${error_file}"
    exit_code=$?
  fi

  if [ -n "${heartbeat_pid}" ]; then
    kill "${heartbeat_pid}" >/dev/null 2>&1 || true
    wait "${heartbeat_pid}" 2>/dev/null || true
    if [ -s "${heartbeat_file}" ]; then
      printf '\n' > /dev/tty 2>/dev/null || true
    fi
  fi

  CCQ_LAST_EXIT_CODE="${exit_code}"
  CCQ_LAST_OUTPUT="$(cat "${output_file}" 2>/dev/null || true)"
  CCQ_LAST_ERROR="$(cat "${error_file}" 2>/dev/null || true)"
  if [ "${exit_code}" -eq 124 ] && [ -z "${CCQ_LAST_ERROR}" ]; then
    CCQ_LAST_ERROR="命令执行超时 (${timeout_seconds} 秒): $(ccq_join_args_for_display "$@")"
  fi
  rm -f "${output_file}" "${error_file}" "${heartbeat_file}"

  if [ "${stream_output}" = "1" ]; then
    ccq_process_tty_block "${CCQ_LAST_OUTPUT}"
    ccq_process_tty_block "${CCQ_LAST_ERROR}"
  elif [ "${suppress_output}" != "1" ] && ! command -v ccq_output_is_developer >/dev/null 2>&1 && [ -n "${CCQ_LAST_OUTPUT}" ]; then
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
      if command -v ccq_ui_runtime_warning >/dev/null 2>&1; then
        ccq_ui_runtime_warning "命令失败，准备重试(${attempt}/${retry_count}): ${display_command}"
      elif command -v ccq_ui_warning >/dev/null 2>&1; then
        ccq_ui_warning "命令失败，准备重试(${attempt}/${retry_count}): ${display_command}" "developer"
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
  local brew_bin="" brew_prefix=""
  if command -v ccq_brew_command >/dev/null 2>&1; then
    brew_bin="$(ccq_brew_command 2>/dev/null || true)"
  elif ccq_command_exists brew; then
    brew_bin="$(command -v brew 2>/dev/null || true)"
  fi
  if [ -n "${brew_bin}" ]; then
    brew_prefix="$("${brew_bin}" --prefix 2>/dev/null || dirname "$(dirname "${brew_bin}")")"
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

ccq_run_command_developer_or_silent() {
  if command -v ccq_output_is_developer >/dev/null 2>&1 && ccq_output_is_developer; then
    ccq_run_command "$@"
  else
    ccq_run_command --suppress-output "$@" >/dev/null 2>&1
  fi
}

ccq_npx() {
  ccq_run_command --timeout "${CCQ_DEFAULT_TIMEOUT_SECONDS}" --retries 0 -- npx "$@"
}
