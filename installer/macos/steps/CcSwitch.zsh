#!/usr/bin/env zsh
# CcSwitch.zsh - macOS cc-switch 安装步骤
# 功能: 通过 Homebrew Cask 安装、检测、验证和更新 cc-switch

if [ -n "${CCQ_STEP_CCSWITCH_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_CCSWITCH_ZSH_LOADED=1

: "${CCQ_CCSWITCH_CASK:=cc-switch}"
CCQ_CCSWITCH_APP_NAMES=("CC-Switch.app" "CC Switch.app" "cc-switch.app")

ccq_ccswitch_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'Message=%s\n' "${3:-}"
}

ccq_ccswitch_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'Version=%s\n' "${2:-}"
  printf 'ErrorMessage=%s\n' "${3:-}"
  if [ -n "${4:-}" ]; then
    printf 'Status=%s\n' "${4}"
  fi
}

ccq_ccswitch_update_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'UpdatedItems=%s\n' "${2:-}"
  printf 'Version=%s\n' "${3:-}"
  printf 'ErrorMessage=%s\n' "${4:-}"
  if [ -n "${5:-}" ]; then
    printf 'Status=%s\n' "${5}"
  fi
}

ccq_ccswitch_brew() {
  ccq_brew_command 2>/dev/null || true
}

ccq_ccswitch_cask_version() {
  local brew_bin versions
  brew_bin="$(ccq_ccswitch_brew)"
  [ -n "${brew_bin}" ] || return 1
  versions="$(${brew_bin} list --cask --versions "${CCQ_CCSWITCH_CASK}" 2>/dev/null || true)"
  [ -n "${versions}" ] || return 1
  printf '%s\n' "${versions#${CCQ_CCSWITCH_CASK} }"
}

ccq_ccswitch_app_exists() {
  local app_name
  for app_name in "${CCQ_CCSWITCH_APP_NAMES[@]}"; do
    [ -d "/Applications/${app_name}" ] && return 0
    [ -d "${HOME}/Applications/${app_name}" ] && return 0
  done
  return 1
}

ccq_ccswitch_manual_hint() {
  cat <<'EOF'
cc-switch macOS 官方路径：
  brew install --cask cc-switch
  brew upgrade --cask cc-switch
也可从 GitHub Release 下载 macOS DMG/ZIP：
  https://github.com/farion1231/cc-switch/releases
EOF
}

Test-CcSwitchInstalled() {
  local version
  version="$(ccq_ccswitch_cask_version 2>/dev/null || true)"
  if [ -n "${version}" ]; then
    ccq_ccswitch_result true "${version}" "cc-switch 已通过 Homebrew Cask 安装"
    return 0
  fi

  if ccq_ccswitch_app_exists; then
    ccq_ccswitch_result true "manual" "检测到 cc-switch 应用，但无法从 Homebrew 获取版本"
    return 0
  fi

  ccq_ccswitch_result false "" "cc-switch 未安装"
}

Install-CcSwitch() {
  if ! ccq_brew_available; then
    ccq_ccswitch_manual_hint >&2
    ccq_ccswitch_install_result false "" "Homebrew 不可用，请按手动指引安装 cc-switch" "ManualRequired"
    return 1
  fi

  if ! ccq_brew_install_cask "${CCQ_CCSWITCH_CASK}"; then
    ccq_ccswitch_manual_hint >&2
    ccq_ccswitch_install_result false "$(ccq_ccswitch_cask_version 2>/dev/null || true)" "brew install --cask cc-switch 失败，请按手动指引处理" "ManualRequired"
    return 1
  fi

  local version
  version="$(ccq_ccswitch_cask_version 2>/dev/null || true)"
  if [ -z "${version}" ] && ! ccq_ccswitch_app_exists; then
    ccq_ccswitch_install_result false "" "cc-switch 安装后验证失败" "ManualRequired"
    return 1
  fi

  ccq_ccswitch_install_result true "${version:-manual}" ""
}

Verify-CcSwitch() {
  local result
  result="$(Test-CcSwitchInstalled)"
  if ccq_result_is_installed "${result}"; then
    printf 'Success=true\nErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\nErrorMessage=cc-switch 验证失败\n'
  return 1
}

Update-CcSwitch() {
  if ! ccq_brew_available; then
    ccq_ccswitch_manual_hint >&2
    ccq_ccswitch_update_result false "" "" "Homebrew 不可用，无法自动更新 cc-switch" "ManualRequired"
    return 1
  fi

  local old_version new_version item
  old_version="$(ccq_ccswitch_cask_version 2>/dev/null || true)"

  if [ -z "${old_version}" ] && ! ccq_ccswitch_app_exists; then
    if ! ccq_brew_install_cask "${CCQ_CCSWITCH_CASK}"; then
      ccq_ccswitch_manual_hint >&2
      ccq_ccswitch_update_result false "" "" "cc-switch 未安装且自动安装失败" "ManualRequired"
      return 1
    fi
    new_version="$(ccq_ccswitch_cask_version 2>/dev/null || true)"
    ccq_ccswitch_update_result true "brew::cc-switch::installed" "${new_version:-manual}" ""
    return 0
  fi

  if ! ccq_brew_upgrade_package "${CCQ_CCSWITCH_CASK}" cask; then
    ccq_ccswitch_update_result false "" "${old_version}" "brew upgrade --cask cc-switch 失败，请按手动指引处理" "ManualRequired"
    return 1
  fi
  new_version="$(ccq_ccswitch_cask_version 2>/dev/null || true)"

  if [ -n "${old_version}" ] && [ -n "${new_version}" ] && [ "${old_version}" != "${new_version}" ]; then
    item="brew::cc-switch::${old_version}->${new_version}"
  else
    item="noop::CcSwitch::no-change"
  fi

  ccq_ccswitch_update_result true "${item}" "${new_version:-${old_version:-manual}}" ""
}
