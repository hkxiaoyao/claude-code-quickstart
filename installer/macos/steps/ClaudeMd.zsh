#!/usr/bin/env zsh
# ClaudeMd.zsh - macOS 用户级 CLAUDE.md 配置步骤
# 功能: 生成 macOS 感知的 CLAUDE.md/rules 内容并保留 Windows 模板兼容

if [ -n "${CCQ_STEP_CLAUDEMD_ZSH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
CCQ_STEP_CLAUDEMD_ZSH_LOADED=1

ccq_claude_md_path() { printf '%s\n' "${HOME}/.claude/CLAUDE.md"; }

ccq_claude_md_template() {
  cat <<'EOF'
# Claude Code 增强配置

## 一、核心原则

### 调研优先（强制）
修改代码或配置前必须先检索验证：确认入口、可复用实现、调用链和影响范围；上下文不足时继续检索，仍不明确则提问。

### 修改前三问
1. 这是真问题还是臆想？（拒绝过度设计）
2. 现有实现能否复用或扩展？（优先复用）
3. 会影响哪些调用关系、配置或用户流程？（保护依赖链）

### 红线原则
- 禁止 copy-paste 重复代码；禁止破坏现有功能；禁止对错误方案妥协
- 禁止盲目执行不加思考；禁止基于假设回答（必须检索验证）
- 关键路径必须有错误处理

### 安全检查
- 禁止硬编码密钥/密码/token；不提交 .env / credentials 等敏感文件
- 用户输入在系统边界必须验证

### 代码风格
- **KISS** - 能简单就不复杂 | **DRY** - 零容忍重复，必须复用
- **保护调用链** - 修改函数签名时同步更新所有调用点
- 完成后清理：临时文件、废弃代码、未使用导入、调试日志

## 二、工作流原则

1. **先检索，后生成** - 修改代码或配置前，必须先检索相关代码/文档，确认入口、复用点、调用链和影响范围；上下文不足时继续检索，仍不明确则提问
2. **事实必须验证** - 代码库事实用本地检索验证；第三方库、框架、SDK、CLI、云服务、版本迁移和配置语法用文档或联网工具验证，禁止猜测
3. **需求先对齐** - 复杂任务或检索后仍有歧义时，先明确关键边界、验收标准和不做范围，再进入实现
4. **高风险先确认** - 删除、提交、推送、重置、批量修改、依赖变更、生产 API、权限/环境配置等操作必须先获得用户明确确认

## 三、任务分级

| 级别 | 判断标准 | 处理方式 |
|------|----------|----------|
| 简单 | 单文件、明确需求、少于 20 行 | 除高风险操作外可直接执行 |
| 中等 | 2-5 个文件、需要调研 | 简要说明方案 → 等待用户确认 → 执行 |
| 复杂 | 架构变更、多模块、不确定性高 | 调研后生成具体 Markdown plan 文件 → 等待用户确认 → 执行 |

### 复杂任务流程
1. **RESEARCH** - 调研代码、调用链、复用点和影响范围，不急于给方案
2. **PLAN FILE** - 采用 ccg-plan 风格生成具体 Markdown 计划文件；不使用 Claude Code 内置 Plan Mode
3. **CONFIRM** - 等待用户确认计划文件后再执行
4. **EXECUTE** - 严格按确认后的计划执行
5. **REVIEW** - 完成后自检

触发：用户说“进入X模式”或任务符合复杂标准时自动启用。

## 四、交互与环境

### 何时询问用户
- 存在多个合理方案时；需求不明确或有歧义时
- 改动范围超出预期时；发现潜在风险时

### 何时直接执行
- 需求明确、方案唯一、非高风险、非破坏性，且属于小范围修改（少于 20 行）时直接执行

### 敢于说不
发现问题直接指出，不妥协于错误方案。

### 环境特定（macOS / zsh / Homebrew）
- 默认 Shell 为 zsh；用户级初始化优先写入 `~/.zshrc` 和 `~/.zprofile`
- Homebrew 仅在 CCQ 执行官方安装成功后，按官方推荐追加 `eval "$(<brew路径> shellenv)"` 到 `~/.zprofile`
- 路径使用正斜杠 `/`，PATH 分隔符为 `:`
- Shell 命令中路径必须加双引号；CCQ 自身涉及 profile 写入时优先使用 CCQ 托管标记块
- Node.js 由 nvm 官方脚本管理；nvm 安装后必要时执行 `source ~/.zshrc` 或重新打开终端

### Windows 兼容提醒
本配置文件可被 Windows 与 macOS 共用；在 macOS 环境中不要建议 winget、注册表、MSI/EXE、Windows Terminal 或 PowerShell `$PROFILE` 作为主实现路径。

### 输出设置
- 中文响应；禁止截断输出

## 五、偏好与记忆写入

### 写入位置决策
- **只在当前仓库成立的偏好 / 团队约束 / 项目约束** → 优先写入该项目的 `CLAUDE.md`，保持项目自洽
- **跨多个项目都成立的真实用户偏好 / 个人协作偏好** → 才考虑写入 memory
- 判断不清时，先问“换个项目这条还成立吗？”：成立 → memory；不成立 → 项目 `CLAUDE.md`

### 反例（禁止写入 memory）
- 项目特定的架构、路径、依赖、命令、约束（HC-*/SC-* 等）
- 临时任务状态、调试解决方案、git 历史可推导的信息
EOF
}

ccq_claude_md_result() {
  printf 'IsInstalled=%s\n' "${1:-false}"
  printf 'Version=\n'
  printf 'Message=%s\n' "${2:-}"
}

ccq_claude_md_install_result() {
  printf 'Success=%s\n' "${1:-false}"
  printf 'ErrorMessage=%s\n' "${2:-}"
  printf 'UpdatedItems=%s\n' "${3:-noop::ClaudeMd::no-change}"
}

Test-ClaudeMdInstalled() {
  local target content
  target="$(ccq_claude_md_path)"
  if [ ! -f "${target}" ]; then
    ccq_claude_md_result false "CLAUDE.md 不存在"
    return 0
  fi
  content="$(cat "${target}" 2>/dev/null || true)"
  case "${content}" in
    *"# Claude Code 增强配置"*"环境特定（macOS / zsh / Homebrew）"*) ccq_claude_md_result true "CLAUDE.md 已配置" ;;
    *) ccq_claude_md_result false "CLAUDE.md 缺少 macOS 感知内容" ;;
  esac
}

Install-ClaudeMd() {
  local target template
  target="$(ccq_claude_md_path)"
  template="$(ccq_claude_md_template)"
  # $'\n' 写入真实换行符（"\n" 在 printf '%s' 下是字面反斜杠+n，会导致指纹永远不匹配）
  if ! ccq_write_file_atomic "${target}" "${template}"$'\n'; then
    ccq_claude_md_install_result false "CLAUDE.md 写入失败" ""
    return 1
  fi
  ccq_claude_md_install_result true "" "file::CLAUDE.md::overwritten"
}

Verify-ClaudeMd() {
  local result
  result="$(Test-ClaudeMdInstalled)"
  if ccq_result_is_installed "${result}"; then
    printf 'Success=true\n'
    printf 'ErrorMessage=\n'
    return 0
  fi
  printf 'Success=false\n'
  printf 'ErrorMessage=CLAUDE.md 验证失败\n'
  return 1
}

# 模板与现有文件指纹比较：模板有变更返回 0（有更新），一致返回 1
ccq_claudemd_has_update() {
  local target template_fp file_fp
  target="$(ccq_claude_md_path)"
  [ -f "${target}" ] || return 0
  command -v shasum >/dev/null 2>&1 || return 0
  # 标准化尾部空白后比较（Install 写入时模板末尾追加换行）
  template_fp="$(ccq_claude_md_template | sed -e 's/[[:space:]]*$//' | shasum -a 256 | awk '{print $1}')"
  file_fp="$(sed -e 's/[[:space:]]*$//' "${target}" | shasum -a 256 2>/dev/null | awk '{print $1}')"
  [ "${template_fp}" != "${file_fp}" ]
}

Update-ClaudeMd() {
  if ! ccq_claudemd_has_update; then
    ccq_claude_md_install_result true "" "noop::ClaudeMd::fingerprint-match"
    return 0
  fi
  Install-ClaudeMd
}
