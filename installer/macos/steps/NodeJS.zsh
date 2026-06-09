#!/usr/bin/env zsh
# NodeJS.zsh - macOS Node.js / nvm 安装步骤
# 功能: 通过 nvm 安装 Node.js LTS、设置 default alias 并验证 node/npm

if [ -n "${CCQ_STEP_NODEJS_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_NODEJS_ZSH_LOADED=1

: "${CCQ_REQUIRED_NODE_MAJOR:=20}"
: "${CCQ_NVM_INSTALL_URL:=https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh}"

ccq_nodejs_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'Message=%s\n' "${3:-}"
}

ccq_nodejs_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'NpmVersion=%s\n' "${3:-}"
  printf 'ErrorMessage=%s\n' "${4:-}"
}

ccq_nodejs_major() {
  local version="${1:-}"
  version="${version#v}"
  printf '%s' "${version%%.*}"
}

ccq_nodejs_nvm_dir() {
  printf '%s\n' "${HOME}/.nvm"
}

ccq_nodejs_nvm_init_content() {
  cat <<'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
EOF
}

ccq_nodejs_write_nvm_profile() {
  local profile_path
  profile_path="$(ccq_zshrc_path)"
  ccq_set_profile_subsection "${profile_path}" "NVM" "$(ccq_nodejs_nvm_init_content)"
}

ccq_nodejs_load_nvm() {
  local nvm_dir
  nvm_dir="$(ccq_nodejs_nvm_dir)"
  export NVM_DIR="${nvm_dir}"
  if [ -s "${NVM_DIR}/nvm.sh" ]; then
    . "${NVM_DIR}/nvm.sh"
  fi
  command -v nvm >/dev/null 2>&1
}

ccq_nodejs_extract_nvm_error() {
  local output_file="${1:-}"
  local line last_line=""
  if [ -z "${output_file}" ] || [ ! -f "${output_file}" ]; then
    printf '%s' 'nvm 官方安装脚本执行失败'
    return 0
  fi

  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    last_line="${line}"
    case "${line}" in
      *"Xcode Command Line Developer Tools"*|*"xcode-select --install"*)
        printf '%s' '缺少 Xcode Command Line Tools，请执行 xcode-select --install 后重试'
        return 0
        ;;
      *"Failed to clone"*|*"Failed to fetch"*|*"Failed to download"*|*"Could not resolve host"*|*"SSL"*|*"Connection"*"failed"*)
        printf '%s' "${line}"
        return 0
        ;;
      *"Permission denied"*|*"has the same name as installation directory"*|*"directory does not exist"*)
        printf '%s' "${line}"
        return 0
        ;;
    esac
  done < "${output_file}"

  [ -n "${last_line}" ] && printf '%s' "${last_line}" || printf '%s' '未获取到 nvm 安装输出'
}

ccq_nodejs_install_nvm() {
  if ccq_nodejs_load_nvm; then
    return 0
  fi
  if ! ccq_command_exists curl; then
    CCQ_NODEJS_ERROR="curl 不可用，无法安装 nvm"
    return 1
  fi

  if ! mkdir -p "$(ccq_nodejs_nvm_dir)"; then
    CCQ_NODEJS_ERROR="无法创建 nvm 目录: $(ccq_nodejs_nvm_dir)"
    return 1
  fi

  local output_file error_hint
  output_file="$(mktemp "${TMPDIR:-/tmp}/ccq-nvm-install.XXXXXX")" || {
    CCQ_NODEJS_ERROR="无法创建 nvm 安装日志临时文件"
    return 1
  }

  if ! PROFILE=/dev/null NVM_DIR="$(ccq_nodejs_nvm_dir)" bash -c "set -o pipefail; curl -fsSL '${CCQ_NVM_INSTALL_URL}' | bash" >"${output_file}" 2>&1; then
    error_hint="$(ccq_nodejs_extract_nvm_error "${output_file}")"
    rm -f "${output_file}"
    CCQ_NODEJS_ERROR="nvm 官方安装脚本执行失败：${error_hint}"
    return 1
  fi
  rm -f "${output_file}"

  if ! ccq_nodejs_load_nvm; then
    CCQ_NODEJS_ERROR="nvm 安装后未能加载 ${NVM_DIR}/nvm.sh"
    return 1
  fi
}

ccq_nodejs_versions_ok() {
  if ! ccq_command_exists node || ! ccq_command_exists npm; then
    return 1
  fi
  local node_version node_major
  node_version="$(node --version 2>/dev/null || true)"
  node_major="$(ccq_nodejs_major "${node_version}")"
  [ -n "${node_major}" ] && [ "${node_major}" -ge "${CCQ_REQUIRED_NODE_MAJOR}" ]
}

Test-NodeJSInstalled() {
  if ! ccq_nodejs_load_nvm; then
    ccq_nodejs_result false "" "nvm 未初始化"
    return 0
  fi
  if ! ccq_nodejs_versions_ok; then
    ccq_nodejs_result false "$(node --version 2>/dev/null || true)" "Node.js 未安装或版本低于 v${CCQ_REQUIRED_NODE_MAJOR}"
    return 0
  fi
  ccq_nodejs_result true "$(node --version 2>/dev/null || true)" "Node.js 与 npm 已通过 nvm 就绪"
}

Install-NodeJS() {
  local error_message=""
  if ! ccq_nodejs_write_nvm_profile; then
    error_message="写入 ~/.zshrc NVM 托管段失败"
    ccq_nodejs_install_result false "" "" "${error_message}"
    return 1
  fi

  if ! ccq_nodejs_install_nvm; then
    error_message="${CCQ_NODEJS_ERROR:-nvm 安装失败}"
    ccq_nodejs_install_result false "" "" "${error_message}"
    return 1
  fi

  if ! nvm install --lts >/dev/null 2>&1; then
    error_message="Node.js LTS 安装失败"
    ccq_nodejs_install_result false "" "" "${error_message}"
    return 1
  fi
  if ! nvm alias default 'lts/*' >/dev/null 2>&1; then
    error_message="nvm default alias 设置失败"
    ccq_nodejs_install_result false "" "" "${error_message}"
    return 1
  fi
  if ! nvm use default >/dev/null 2>&1; then
    error_message="nvm use default 失败"
    ccq_nodejs_install_result false "" "" "${error_message}"
    return 1
  fi

  ccq_refresh_path
  if ! ccq_nodejs_versions_ok; then
    error_message="Node.js 安装后验证失败"
    ccq_nodejs_install_result false "$(node --version 2>/dev/null || true)" "$(npm --version 2>/dev/null || true)" "${error_message}"
    return 1
  fi

  ccq_nodejs_install_result true "$(node --version 2>/dev/null || true)" "$(npm --version 2>/dev/null || true)" ""
}

Verify-NodeJS() {
  if ccq_nodejs_load_nvm && ccq_nodejs_versions_ok; then
    printf 'Success=true\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\n'
  printf 'ErrorMessage=Node.js 或 npm 验证失败\n'
  return 1
}
