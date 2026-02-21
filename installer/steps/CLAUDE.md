# installer/steps/ — 安装步骤模块

> 面包屑：[根目录](../../CLAUDE.md) › [installer/](../CLAUDE.md) › steps/
> 生成时间：2026-02-20 15:24:29

---

## 步骤契约（HC-2）

每个步骤文件**必须**实现四个函数：

```powershell
# 检测是否已安装/已完成
function Test-StepXXInstalled {
    return @{
        IsInstalled = [bool]
        Version     = [string]   # 版本号，不适用时为 ""
        Data        = @{}        # 传递给 StepResult.Data
        Message     = [string]   # 状态说明
    }
}

# 执行安装
function Install-StepXX {
    return @{
        Success      = [bool]
        ErrorMessage = [string]
        Data         = @{}       # 版本号等写入此处
    }
}

# 验证安装结果（可选，不需要时返回 @{Success=$true}）
function Verify-StepXX {
    return @{ Success = [bool]; ErrorMessage = [string] }
}

# 回滚（可选）
function Rollback-StepXX {
    return @{ Success = [bool]; ErrorMessage = [string] }
}
```

> Bootstrap.ps1 的 `Invoke-StepLifecycle` 同时兼容 `bool` 和 `hashtable` 两种返回类型（向后兼容旧步骤）。

---

## 步骤总览

| 步骤 | 名称 | 可选 | SkipIfInstalled | 主要依赖 |
|------|------|:----:|:---------------:|---------|
| Step01 | 代理配置检测 | — | — | 无 |
| Step02 | Node.js (fnm) | — | ✓ | Step01 |
| Step03 | Git | — | ✓ | Step01 |
| Step04 | Claude Code | — | ✓ | Step02 |
| Step05 | ccline | — | ✓ | Step04 |
| Step06 | cc-switch | — | ✓ | Step04 |
| Step07 | API Key 配置 | — | — | Step04 |
| Step08 | Claude 基础配置 | — | ✓ | Step07 |
| Step09 | CLAUDE.md 配置 | — | ✓ | Step08 |
| Step10 | MCP Server 配置 | — | ✓ | Step08 |
| Step11 | CCG 工作流 | — | ✓ | Step02 + Step08 |
| Step12 | Codex CLI | **✓** | ✓ | Step02 |
| Step13 | Gemini CLI | **✓** | ✓ | Step02 |

---

## Step01 — 代理配置检测

**文件**：`Step01.Proxy.ps1`（258 行）
**依赖核心模块**：`Net.ps1`, `Ui.ps1`
**SkipIfInstalled**：`false`（每次都重新检测网络环境）

**逻辑**：调用 `Get-NetworkHealth` + `Get-ProxySnapshot`，评估网络可达性。
`Install-Step01` 实际不安装任何东西——显示代理配置建议并引导用户确认。

---

## Step02 — Node.js (fnm)

**文件**：`Step02.NodeFnm.ps1`（493 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`, `Profile.ps1`

**安装流程**：
1. 检测 `fnm` / `node` 是否已安装
2. 用 `winget install Schniz.fnm` 安装 fnm
3. 写入 `$PROFILE` 标记块（`fnm env` 初始化）
4. `Refresh-SessionPath` + `fnm install --lts`
5. 验证 `node --version` / `npm --version`

---

## Step03 — Git

**文件**：`Step03.Git.ps1`（546 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`

**安装流程**：`winget install Git.Git` → 配置 `core.autocrlf=false` 等 → 验证 `git --version`

---

## Step04 — Claude Code

**文件**：`Step04.ClaudeCode.ps1`（454 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`

**安装流程**：`npm install -g @anthropic-ai/claude-code` → 验证 `claude --version`

---

## Step05 — ccline

**文件**：`Step05.Ccline.ps1`（307 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`, `Profile.ps1`

**安装**：npm 全局安装 + 写入 `$PROFILE` PATH。

---

## Step06 — cc-switch

**文件**：`Step06.CcSwitch.ps1`（562 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`, `Profile.ps1`

**安装**：npm 全局安装 cc-switch + 写入 `$PROFILE`。

---

## Step07 — API Key 配置（HC-12 关键）

**文件**：`Step07.ApiKey.ps1`（330 行）
**配置路径**：`$env:USERPROFILE\.claude\settings.json`

### 支持的 AI 供应商

```powershell
$script:ApiProviders = @{
    zhipu    = @{
        Name        = "智谱 GLM"
        BaseUrl     = "https://open.bigmodel.cn/api/paas/v4/"
        PlatformUrl = "https://open.bigmodel.cn"
    }
    minimax  = @{
        Name        = "MiniMax"
        BaseUrl     = "https://api.minimax.chat/v1/"
        PlatformUrl = "https://platform.minimaxi.com"
    }
    moonshot = @{
        Name        = "Kimi (Moonshot)"
        BaseUrl     = "https://api.moonshot.cn/v1/"
        PlatformUrl = "https://platform.moonshot.cn"
    }
}
```

### 写入格式（HC-12）

```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "<API_KEY>",
    "ANTHROPIC_BASE_URL": "<BaseUrl>"
  }
}
```

> **禁止**写入 `anthropicApiKey`、`openaiApiKey` 等顶层字段。
> **禁止**写入 Anthropic / OpenAI / Azure 供应商。

---

## Step08 — Claude 基础配置

**文件**：`Step08.ClaudeConfig.ps1`（298 行）
**配置路径**：`$env:USERPROFILE\.claude\settings.json`（与 Step07 同一文件）

**写入字段**（补充 Step07 的 env 配置）：

```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "...",
    "ANTHROPIC_BASE_URL": "...",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "8192"
  },
  "language": "zh-CN",
  "model": "claude-opus-4-5",
  "permissions": {
    "allow": ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "WebFetch"]
  },
  "statusLine": "auto"
}
```

---

## Step09 — CLAUDE.md 配置

**文件**：`Step09.ClaudeMd.ps1`（454 行）
**目标**：`$env:USERPROFILE\.claude\CLAUDE.md`

**功能**：生成全局 Claude Code 工作规范文件，包含代码风格、工具速查、交互规范等内容。
使用 `Write-FileAtomically -FilePath`（**注意参数名**）。

---

## Step10 — MCP Server 配置

**文件**：`Step10.Mcp.ps1`（533 行）
**配置路径**：`$env:USERPROFILE\.claude\settings.json`

**功能**：在 settings.json 中写入 `mcpServers` 配置块，支持多个 MCP 插件服务器。
变量插值注意使用 `${serverId}` 格式（避免冒号歧义）。

---

## Step11 — CCG 工作流

**文件**：`Step11.CcgWorkflow.ps1`（约 369 行）
**依赖**：Step02.NodeFnm + Step08.ClaudeConfig

**功能**：通过官方 `npx ccg-workflow@latest init` 安装 CCG Workflow 工作流引擎。

**安装命令**：
```powershell
npx --yes ccg-workflow@latest init --skip-prompt --skip-mcp --lang zh-CN --install-dir "$env:USERPROFILE\.claude"
```

**安装后目录结构**：
- `~/.claude/commands/ccg/` — 命令模板（Slash Commands）
- `~/.claude/agents/ccg/` — Agent 模板
- `~/.claude/.ccg/` — CCG 配置目录（含 config.toml）
- `~/.claude/bin/codeagent-wrapper.exe` — 核心二进制

**关键机制**：
- `--skip-mcp`：安装前后对 `settings.json` 的 `mcpServers` 做快照比对，保护 Step10 的 MCP 配置
- 超时/重试：`TimeoutSeconds 300`，`RetryCount 3`
- 安装后立即调用 `Refresh-SessionPath`

---

## Step12 — Codex CLI（可选）

**文件**：`Step12.CodexCli.ps1`（212 行）

```powershell
# 正确调用方式（无 -DisplayName 参数）
$installOut = Invoke-NpmGlobalInstall -PackageName "codex-cli"
```

---

## Step13 — Gemini CLI（可选）

**文件**：`Step13.GeminiCli.ps1`（212 行）

```powershell
# 正确调用方式（无 -DisplayName 参数）
$installOut = Invoke-NpmGlobalInstall -PackageName "gemini-cli"
```

---

## 新增步骤模板

添加 Step14+ 时遵循此模板：

```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Process.ps1"

function Test-Step14Installed {
    $result = @{ IsInstalled = $false; Version = ""; Data = @{}; Message = "" }
    try {
        # 检测逻辑
        $result.IsInstalled = $true
    } catch {
        $result.Message = $_.Exception.Message
    }
    return $result
}

function Install-Step14 {
    $result = @{ Success = $false; ErrorMessage = ""; Data = @{} }
    try {
        # 安装逻辑
        $result.Success = $true
    } catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiError $result.ErrorMessage
    }
    return $result
}

function Verify-Step14 {
    $result = @{ Success = $false; ErrorMessage = "" }
    try {
        # 验证逻辑
        $result.Success = $true
    } catch {
        $result.ErrorMessage = $_.Exception.Message
    }
    return $result
}

function Rollback-Step14 {
    $result = @{ Success = $false; ErrorMessage = "" }
    try {
        # 回滚逻辑
        $result.Success = $true
    } catch {
        $result.ErrorMessage = $_.Exception.Message
    }
    return $result
}
```

在 `Install-ClaudeEnv.ps1` 的 `$script:StepRegistry` 中注册，并在 `Bootstrap.ps1` 的 `Get-StepDependencies` 中声明依赖。
