#!/usr/bin/env zsh
# PackageManager.zsh - macOS Homebrew 包管理器封装
# 功能: Homebrew 检测、官方安装、prefix 识别、shellenv 初始化、formula/cask 安装与升级包装

if [ -n "${CCQ_PACKAGE_MANAGER_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_PACKAGE_MANAGER_ZSH_LOADED=1

ccq_brew_command() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  local prefix
  if command -v ccq_default_brew_prefix >/dev/null 2>&1; then
    prefix="$(ccq_default_brew_prefix)"
  else
    prefix="/opt/homebrew"
  fi

  if [ -x "${prefix}/bin/brew" ]; then
    printf '%s\n' "${prefix}/bin/brew"
    return 0
  fi
  if [ -x "/usr/local/bin/brew" ]; then
    printf '%s\n' "/usr/local/bin/brew"
    return 0
  fi
  return 1
}

ccq_brew_available() {
  ccq_brew_command >/dev/null 2>&1
}

ccq_homebrew_install_command() {
  printf '%s\n' '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty'
}

ccq_install_homebrew() {
  if ccq_brew_available; then
    return 0
  fi
  if [ ! -r /dev/tty ]; then
    return 1
  fi
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
}

ccq_brew_prefix() {
  local brew_bin
  brew_bin="$(ccq_brew_command 2>/dev/null || true)"
  if [ -n "${brew_bin}" ]; then
    "${brew_bin}" --prefix 2>/dev/null || dirname "$(dirname "${brew_bin}")"
    return 0
  fi
  if command -v ccq_default_brew_prefix >/dev/null 2>&1; then
    ccq_default_brew_prefix
  else
    printf '%s\n' '/opt/homebrew'
  fi
}

ccq_brew_shellenv() {
  local brew_bin
  brew_bin="$(ccq_brew_command 2>/dev/null || true)"
  if [ -z "${brew_bin}" ]; then
    return 1
  fi
  "${brew_bin}" shellenv
}

ccq_homebrew_shellenv_line() {
  local brew_bin="${1:-}"
  [ -n "${brew_bin}" ] || brew_bin="$(ccq_brew_command 2>/dev/null || true)"
  [ -n "${brew_bin}" ] || return 1
  printf 'eval "$(%s shellenv)"\n' "${brew_bin}"
}

ccq_apply_homebrew_post_install_steps() {
  local profile_path="${1:-${HOME}/.zprofile}"
  local brew_bin shellenv_line
  brew_bin="$(ccq_brew_command 2>/dev/null || true)"
  [ -n "${brew_bin}" ] || return 1
  shellenv_line="$(ccq_homebrew_shellenv_line "${brew_bin}")" || return 1

  if [ ! -f "${profile_path}" ] || ! grep -F -- "${shellenv_line}" "${profile_path}" >/dev/null 2>&1; then
    {
      printf '\n'
      printf '%s\n' "${shellenv_line}"
    } >>"${profile_path}"
  fi

  eval "$("${brew_bin}" shellenv)"
}

ccq_brew_install_formula() {
  local formula="${1:-}"
  [ -z "${formula}" ] && return 1
  local brew_bin
  brew_bin="$(ccq_brew_command)" || return 1

  if "${brew_bin}" list --formula "${formula}" >/dev/null 2>&1; then
    return 0
  fi
  "${brew_bin}" install "${formula}"
}

ccq_brew_install_cask() {
  local cask="${1:-}"
  [ -z "${cask}" ] && return 1
  local brew_bin
  brew_bin="$(ccq_brew_command)" || return 1

  if "${brew_bin}" list --cask "${cask}" >/dev/null 2>&1; then
    return 0
  fi
  "${brew_bin}" install --cask "${cask}"
}

ccq_brew_upgrade_package() {
  local package_name="${1:-}"
  local kind="${2:-formula}"
  [ -z "${package_name}" ] && return 1
  local brew_bin
  brew_bin="$(ccq_brew_command)" || return 1

  case "${kind}" in
    cask) "${brew_bin}" upgrade --cask "${package_name}" ;;
    formula|*) "${brew_bin}" upgrade "${package_name}" ;;
  esac
}

ccq_homebrew_install_hint() {
  cat <<'EOF'
Homebrew 未安装。可按 Homebrew 官方方式安装：
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
安装完成后重新运行 CCQ。
EOF
}
