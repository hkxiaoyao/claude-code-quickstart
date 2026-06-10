#!/usr/bin/env zsh
# ApiKey.zsh - macOS 第三方供应商配置步骤（薄包装层）
# 功能: 提供 Test / Install / Verify 契约函数，业务逻辑委托 core/Provider.zsh
# 依赖: core/Provider.zsh（须先加载，提供 ccq_provider_* 全部能力）

if [ -n "${CCQ_STEP_APIKEY_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_APIKEY_ZSH_LOADED=1

ccq_apikey_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=\n'
  printf 'Message=%s\n' "${2:-}"
}

ccq_apikey_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'Provider=%s\n' "${2:-}"
  printf 'BaseUrlConfigured=%s\n' "${3:-false}"
  printf 'ErrorMessage=%s\n' "${4:-}"
}

Test-ApiKeyInstalled() {
  local settings_path
  settings_path="$(ccq_provider_settings_path)"
  if [ ! -f "${settings_path}" ]; then
    ccq_apikey_result false "settings.json 不存在"
    return 0
  fi
  if ccq_provider_env_value_exists "${settings_path}" "env.ANTHROPIC_AUTH_TOKEN" && ccq_provider_env_value_exists "${settings_path}" "env.ANTHROPIC_BASE_URL"; then
    ccq_apikey_result true "供应商配置已存在"
    return 0
  fi
  ccq_apikey_result false "供应商配置未完成"
}

Install-ApiKey() {
  if ! ccq_provider_contract_node; then
    ccq_apikey_install_result false "" false "Node.js 不可用或 providers 契约不存在"
    return 1
  fi

  # 迁移旧用户：settings.json 已配置但无 Profile 时反向生成
  ccq_provider_sync_from_settings

  if ccq_provider_interactive_install; then
    ccq_apikey_install_result true "${CCQ_PROVIDER_LAST_NAME}" true ""
    return 0
  fi
  ccq_apikey_install_result false "${CCQ_PROVIDER_LAST_NAME}" "${CCQ_PROVIDER_LAST_BASEURL_OK:-false}" "${CCQ_PROVIDER_ERROR:-供应商配置失败}"
  return 1
}

Verify-ApiKey() {
  local settings_path
  settings_path="$(ccq_provider_settings_path)"
  if ccq_provider_env_value_exists "${settings_path}" "env.ANTHROPIC_AUTH_TOKEN" && ccq_provider_env_value_exists "${settings_path}" "env.ANTHROPIC_BASE_URL"; then
    printf 'Success=true\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\n'
  printf 'ErrorMessage=供应商配置验证失败\n'
  return 1
}
