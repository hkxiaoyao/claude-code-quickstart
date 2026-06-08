#!/usr/bin/env zsh
# Git.zsh - macOS Git 安装和基础配置
# 功能: 通过 Homebrew 安装 Git 并应用推荐 global config

if [ -n "${CCQ_STEP_GIT_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_GIT_ZSH_LOADED=1

: "${CCQ_MIN_GIT_VERSION:=2.30.0}"

ccq_git_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'Message=%s\n' "${3:-}"
}

ccq_git_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'ErrorMessage=%s\n' "${3:-}"
}

ccq_git_version() {
  git --version 2>/dev/null | head -n 1 || true
}

ccq_git_normalize_version() {
  local version="${1:-}"
  version="${version#git version }"
  version="${version%% *}"
  printf '%s' "${version}"
}

ccq_git_version_part() {
  local version="${1:-0}"
  local index="${2:-1}"
  local part rest
  rest="${version}"
  while [ "${index}" -gt 1 ]; do
    case "${rest}" in
      *.*) rest="${rest#*.}" ;;
      *) rest="0" ;;
    esac
    index=$((index - 1))
  done
  part="${rest%%.*}"
  part="${part%%[^0-9]*}"
  printf '%s' "${part:-0}"
}

ccq_git_version_ge() {
  local actual="${1:-0.0.0}"
  local required="${2:-0.0.0}"
  local i actual_part required_part
  for i in 1 2 3; do
    actual_part="$(ccq_git_version_part "${actual}" "${i}")"
    required_part="$(ccq_git_version_part "${required}" "${i}")"
    if [ "${actual_part}" -gt "${required_part}" ]; then return 0; fi
    if [ "${actual_part}" -lt "${required_part}" ]; then return 1; fi
  done
  return 0
}

ccq_git_config_value() {
  git config --global --get "$1" 2>/dev/null || true
}

ccq_git_has_required_config() {
  [ "$(ccq_git_config_value init.defaultBranch)" = "main" ] || return 1
  [ "$(ccq_git_config_value core.quotepath)" = "false" ] || return 1
  return 0
}

ccq_git_apply_config() {
  git config --global init.defaultBranch main || return 1
  git config --global core.quotepath false || return 1
  git config --global i18n.commit.encoding utf-8 || return 1
  git config --global i18n.logoutputencoding utf-8 || return 1
}

ccq_git_version_ok() {
  if ! ccq_command_exists git; then
    return 1
  fi
  local version
  version="$(ccq_git_normalize_version "$(ccq_git_version)")"
  [ -n "${version}" ] && ccq_git_version_ge "${version}" "${CCQ_MIN_GIT_VERSION}"
}

Test-GitInstalled() {
  if ! ccq_git_version_ok; then
    ccq_git_result false "$(ccq_git_version)" "Git 未安装或版本过低"
    return 0
  fi
  if ! ccq_git_has_required_config; then
    ccq_git_result false "$(ccq_git_version)" "Git 推荐配置未完成"
    return 0
  fi
  ccq_git_result true "$(ccq_git_version)" "Git 已安装并完成推荐配置"
}

Install-Git() {
  if ! ccq_git_version_ok; then
    if ! ccq_brew_available; then
      printf 'Success=false\n'
      printf 'Status=ManualRequired\n'
      printf 'ErrorMessage=Homebrew 不可用，请先安装 Homebrew 后重试\n'
      return 1
    fi

    if ! ccq_brew_install_formula git >/dev/null 2>&1; then
      ccq_git_install_result false "$(ccq_git_version)" "brew install git 失败"
      return 1
    fi

    ccq_refresh_path
    if ! ccq_git_version_ok; then
      ccq_git_install_result false "$(ccq_git_version)" "Git 安装后仍不可用"
      return 1
    fi
  fi

  if ! ccq_git_apply_config; then
    ccq_git_install_result false "$(ccq_git_version)" "Git 推荐配置写入失败"
    return 1
  fi

  ccq_git_install_result true "$(ccq_git_version)" ""
}

Verify-Git() {
  if ccq_git_version_ok && ccq_git_has_required_config; then
    printf 'Success=true\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\n'
  printf 'ErrorMessage=Git 安装或推荐配置验证失败\n'
  return 1
}
