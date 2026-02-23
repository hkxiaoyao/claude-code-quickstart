# installer/steps/ — 安装步骤模块

> 面包屑：[根目录](../../CLAUDE.md) › [installer/](../CLAUDE.md) › steps/
> 生成时间：2026-02-20 15:24:29

---

## 步骤契约（HC-2）

每个步骤文件**必须**实现三个函数：

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
```

> **注意**：回滚功能已移除，后续将在更新环境脚本中重新设计。
> Bootstrap.ps1 的 `Invoke-StepLifecycle` 同时兼容 `bool` 和 `hashtable` 两种返回类型（向后兼容旧步骤）。

---

## 步骤总览

| 步骤 | 名称 | 可选 | SkipIfInstalled | 主要依赖 | 分组 |
|------|------|:----:|:---------------:|---------|------|
| Step01 | Node.js (fnm) | — | ✓ | 无 | 基础 |
| Step02 | Git | — | ✓ | 无 | 基础 |
| Step03 | Claude Code | — | ✓ | Step01 | 基础 |
| Step04 | API Key 配置 | — | — | Step03 | 基础 |
| Step05 | ccline | — | ✓ | Step03 | 进阶 |
| Step06 | cc-switch | — | ✓ | Step03 | 进阶 |
| Step07 | Claude 基础配置 | — | ✓ | Step03 | 进阶 |
| Step08 | CLAUDE.md 配置 | — | ✓ | Step07 | 进阶 |
| Step09 | MCP Server 配置 | — | ✓ | Step03 | 进阶 |
| Step10 | CCG 工作流 | — | ✓ | Step01 | 进阶 |
| Step11 | Codex CLI | **✓** | ✓ | Step01 | 进阶 |
| Step12 | Gemini CLI | **✓** | ✓ | Step01 | 进阶 |

---

## Step01 — Node.js (fnm)

**文件**：`Step01.NodeFnm.ps1`（493 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`, `Profile.ps1`

**安装流程**：
1. 检测 `fnm` / `node` 是否已安装
2. 用 `winget install Schniz.fnm` 安装 fnm
3. 写入 `$PROFILE` 标记块（`fnm env` 初始化）
4. `Refresh-SessionPath` + `fnm install --lts`
5. 验证 `node --version` / `npm --version`

---

## Step02 — Git

**文件**：`Step02.Git.ps1`
**依赖核心模块**：`Process.ps1`, `Ui.ps1`

**安装流程**：`winget install Git.Git` → 配置 4 项 Git 推荐设置 → 写入 Git Bash UTF-8（Python + PowerShell wrapper）→ 验证 `git --version` / `git config --list --global`

---

## Step03 — Claude Code

**文件**：`Step03.ClaudeCode.ps1`（454 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`

**安装流程**：`npm install -g @anthropic-ai/claude-code` → 验证 `claude --version`

---

## Step04 — API Key 配置（HC-12 关键）

**文件**：`Step04.ApiKey.ps1`（约 330 行）
**配置路径**：`$env:USERPROFILE\.claude\settings.json`

### 支持的 AI 供应商

```powershell
$script:ApiProviders = @{
    zhipu    = @{
        Name        = "智谱 GLM"
        Description = "智谱 AI，服务端自动路由到最新 GLM 模型"
        BaseUrl     = "https://open.bigmodel.cn/api/anthropic"
        PlatformUrl = "https://bigmodel.cn/usercenter/proj-mgmt/apikeys"
        # 无 ModelMapping — 服务端自动翻译模型名
    }
    minimax  = @{
        Name         = "MiniMax"
        BaseUrl      = "https://api.minimaxi.com/anthropic"
        PlatformUrl  = "https://platform.minimaxi.com/user-center/basic-information/interface-key"
        ModelMapping = @{
            "opus"   = "MiniMax-M2.5"
            "sonnet" = "MiniMax-M2.5"
            "haiku"  = "MiniMax-M2.5"
        }
    }
    moonshot = @{
        Name         = "Kimi (Moonshot)"
        BaseUrl      = "https://api.moonshot.cn/anthropic"
        PlatformUrl  = "https://platform.moonshot.cn/console/api-keys"
        ModelMapping = @{
            "opus"   = "kimi-k2.5"
            "sonnet" = "kimi-k2.5"
            "haiku"  = "kimi-k2.5"
        }
    }
    custom   = @{
        Name        = "自定义供应商"
        Description = "手动配置 Base URL 和 API Key"
        BaseUrl     = ""  # 用户输入
        # 无 ModelMapping — 用户按需自行配置
    }
}
```

### 写入格式（HC-12）

**~/.claude/settings.json**（智谱/自定义 — 无 modelMapping）：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "<API_KEY>",
    "ANTHROPIC_BASE_URL": "<BaseUrl>"
  }
}
```

**~/.claude/settings.json**（MiniMax/Moonshot — 含 modelMapping）：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "<API_KEY>",
    "ANTHROPIC_BASE_URL": "<BaseUrl>"
  },
  "modelMapping": {
    "opus": "MiniMax-M2.5",
    "sonnet": "MiniMax-M2.5",
    "haiku": "MiniMax-M2.5"
  }
}
```

**~/.claude.json**：
```json
{
  "hasCompletedOnboarding": true
}
```

此配置用于标记 Claude Code 环境已完成初始化，由 Step04 自动创建。如果文件已存在，将合并写入，保留用户已有字段。

### 自定义供应商流程

1. 用户选择"自定义供应商"
2. 输入自定义 Base URL（必须以 `http://` 或 `https://` 开头）
3. 输入 API Key

> **禁止**写入 `anthropicApiKey`、`openaiApiKey` 等顶层字段。
> **禁止**写入 Anthropic / OpenAI / Azure 供应商。

---

## Step05 — ccline

**文件**：`Step05.Ccline.ps1`（295 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`

**包名**：`@cometix/ccline`（scoped package）

**安装流程**：
1. 前置检查（Claude Code + npm）
2. `npm install -g @cometix/ccline`
3. 配置 `statusLine`（官方 schema）写入 `~/.claude/settings.json`
4. 执行 `ccline --patch <cli.js>` 对 Claude Code 进行 patch

**statusLine 配置格式（Claude Code 官方 schema）**：
```json
{
  "statusLine": {
    "type": "command",
    "command": "ccline",
    "padding": 0
  }
}
```

**检测条件**：`$settings.statusLine.type -eq "command"`

**ccline patch**：安装后自动定位 `npm prefix/node_modules/@anthropic-ai/claude-code/cli.js`，执行 `ccline --patch` 注入状态栏支持。失败时仅警告不中断。

---

## Step06 — cc-switch

**文件**：`Step06.CcSwitch.ps1`（562 行）
**依赖核心模块**：`Process.ps1`, `Ui.ps1`, `Profile.ps1`

**安装**：npm 全局安装 cc-switch + 写入 `$PROFILE`。

---

## Step07 — Claude 基础配置

**文件**：`Step07.ClaudeConfig.ps1`
**配置路径**：`$env:USERPROFILE\.claude\settings.json`（与 Step04 同一文件）

**写入策略**：声明式字段管理，读取 -> 补缺失 -> 原子写入。仅管理 Step07 自有字段，不覆盖 Step04（API Key/Base URL/modelMapping）、Step05（statusLine）或用户自定义配置。

**Step07 管辖的 env 字段**：

| 字段 | 默认值 | 写入策略 |
|------|--------|----------|
| `BASH_DEFAULT_TIMEOUT_MS` | `600000` | 仅补缺失 |
| `BASH_MAX_TIMEOUT_MS` | `3600000` | 仅补缺失 |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `90` | 仅补缺失 |
| `CLAUDE_CODE_ATTRIBUTION_HEADER` | `0` | 仅补缺失 |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | 仅补缺失 |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `1` | 仅补缺失 |
| `DISABLE_INSTALLATION_CHECKS` | `1` | 仅补缺失 |
| `MAX_THINKING_TOKENS` | `31999` | 仅补缺失 |

**其他 Step07 管辖字段**：

| 字段 | 默认值 | 写入策略 |
|------|--------|----------|
| `language` | `简体中文` | 仅补缺失 |
| `model` | `sonnet` | 仅补缺失 |
| `permissions.allow` | 14 项基础权限 | 合并（只添加缺失项，不删除已有项） |
| `attribution` | `{ commit: "", pr: "" }` | 仅补缺失 |

**Step07 不触碰的字段**：`statusLine`（Step05）、`hooks`（用户/插件）、`outputStyle`（用户自定义）、`mcpServers`（Step09）、`env.ANTHROPIC_AUTH_TOKEN`/`env.ANTHROPIC_BASE_URL`/`modelMapping`（Step04）、`env.CODEAGENT_POST_MESSAGE_DELAY`/`env.CODEX_TIMEOUT`（Step10）

> **注意**：statusLine 配置完全由 Step05（ccline）负责，Step07 不触碰 statusLine 字段。

---

## Step08 — CLAUDE.md 配置

**文件**：`Step08.ClaudeMd.ps1`
**目标**：`$env:USERPROFILE\.claude\CLAUDE.md` + `$env:USERPROFILE\.claude\rules\`

**功能**：生成全局 Claude Code 工作规范。主文件 ~80 行（确保在 token 截断限制内完整可见），详细内容拆分到 `rules/` 目录（Claude Code 无条件加载）。

**瘦身结构**：
- `CLAUDE.md`（~80 行）：核心原则 / 工作流原则 / 任务分级 / 交互与环境+输出设置
- `rules/ccg-multimodel.md`：多模型协作（Codex/Gemini 调用格式、会话复用、并行调用）
- `rules/ccg-tools.md`：工具速查表 + 知识获取 + 设计图获取
- `rules/ccg-workflow.md`：工作流增强（上下文检索、Prompt 增强、需求对齐）

**写入方式**：`Write-FileAtomically -FilePath`（**注意参数名**）。主文件和 rules 文件均采用备份 + 原子覆写。

**检测条件**：`Test-Step08Installed` 检查主文件 3 个关键标识 + 3 个 rules 文件存在性。

---

## Step09 — MCP Server 配置

**文件**：`Step09.Mcp.ps1`（533 行）
**配置路径**：`$env:USERPROFILE\.claude\settings.json`

**功能**：在 settings.json 中写入 `mcpServers` 配置块，支持多个 MCP 插件服务器。
变量插值注意使用 `${serverId}` 格式（避免冒号歧义）。

---

## Step10 — CCG 工作流

**文件**：`Step10.CcgWorkflow.ps1`（约 369 行）
**依赖**：Step01.NodeFnm + Step07.ClaudeConfig

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
- `--skip-mcp`：安装前后对 `settings.json` 的 `mcpServers` 做快照比对，保护 Step09 的 MCP 配置
- 超时/重试：`TimeoutSeconds 300`，`RetryCount 3`
- 安装后立即调用 `Refresh-SessionPath`

---

## Step11 — Codex CLI（可选）

**文件**：`Step11.CodexCli.ps1`（212 行）

```powershell
# 正确调用方式（无 -DisplayName 参数）
$installOut = Invoke-NpmGlobalInstall -PackageName "codex-cli"
```

---

## Step12 — Gemini CLI（可选）

**文件**：`Step12.GeminiCli.ps1`（212 行）

```powershell
# 正确调用方式（无 -DisplayName 参数）
$installOut = Invoke-NpmGlobalInstall -PackageName "gemini-cli"
```

---

## 新增步骤模板

添加 Step13+ 时遵循此模板：

```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Process.ps1"

function Test-Step13Installed {
    $result = @{ IsInstalled = $false; Version = ""; Data = @{}; Message = "" }
    try {
        # 检测逻辑
        $result.IsInstalled = $true
    } catch {
        $result.Message = $_.Exception.Message
    }
    return $result
}

function Install-Step13 {
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

function Verify-Step13 {
    $result = @{ Success = $false; ErrorMessage = "" }
    try {
        # 验证逻辑
        $result.Success = $true
    } catch {
        $result.ErrorMessage = $_.Exception.Message
    }
    return $result
}

function Rollback-Step13 {
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

在 `Install-ClaudeEnv.ps1` 和 `Manage-ClaudeEnv.ps1` 的 `$script:StepRegistry` 中注册，并在 `Bootstrap.ps1` 的 `Get-StepDependencies` 中声明依赖。
