# installer/steps/ — 安装步骤模块

> 面包屑：[根目录](../../CLAUDE.md) › [installer/](../CLAUDE.md) › steps/
> 生成时间：2026-02-23 (架构重构后更新)

---

## 步骤契约（HC-2）

每个步骤文件**必须**实现三个函数（函数名使用语义化命名，无数字前缀）：

```powershell
# 检测是否已安装/已完成
function Test-<StepId>Installed {
    return @{
        IsInstalled = [bool]
        Version     = [string]   # 版本号，不适用时为 ""
        Data        = @{}        # 传递给 StepResult.Data
        Message     = [string]   # 状态说明
    }
}

# 执行安装
function Install-<StepId> {
    return @{
        Success      = [bool]
        ErrorMessage = [string]
        Data         = @{}       # 版本号等写入此处
    }
}

# 验证安装结果（可选，不需要时返回 @{Success=$true}）
function Verify-<StepId> {
    return @{ Success = [bool]; ErrorMessage = [string] }
}
```

> **注意**：回滚功能已移除，后续将在更新环境脚本中重新设计。
> Bootstrap.ps1 的 `Invoke-StepLifecycle` 同时兼容 `bool` 和 `hashtable` 两种返回类型（向后兼容旧步骤）。

---

## 步骤总览

| StepId | 名称 | 文件 | 可选 | SkipIfInstalled | 主要依赖 | 分组 |
|--------|------|------|:----:|:---------------:|---------|------|
| NodeFnm | Node.js (fnm) | `NodeFnm.ps1` | — | ✓ | 无 | 基础 |
| Git | Git | `Git.ps1` | — | ✓ | 无 | 基础 |
| ClaudeCode | Claude Code | `ClaudeCode.ps1` | — | ✓ | NodeFnm | 基础 |
| ApiKey | API Key 配置 | `ApiKey.ps1` | — | ✓ | ClaudeCode | 基础 |
| Ccline | ccline | `Ccline.ps1` | — | ✓ | ClaudeCode | 进阶 |
| CcSwitch | cc-switch | `CcSwitch.ps1` | — | ✓ | ClaudeCode | 进阶 |
| ClaudeConfig | Claude 基础配置 | `ClaudeConfig.ps1` | — | ✓ | ClaudeCode | 进阶 |
| ClaudeMd | CLAUDE.md 配置 | `ClaudeMd.ps1` | — | ✓ | ClaudeConfig | 进阶 |
| Mcp | MCP Server 配置 | `Mcp.ps1` | — | ✓ | ClaudeCode | 进阶 |
| CcgWorkflow | CCG 工作流 | `CcgWorkflow.ps1` | — | ✓ | NodeFnm | 进阶 |
| CodexCli | Codex CLI | `CodexCli.ps1` | **✓** | ✓ | NodeFnm | 进阶 |
| GeminiCli | Gemini CLI | `GeminiCli.ps1` | **✓** | ✓ | NodeFnm | 进阶 |

---

## NodeFnm — Node.js (fnm)

**文件**：`NodeFnm.ps1`
**依赖核心模块**：`Process.ps1`, `Ui.ps1`, `Profile.ps1`

**安装流程**：
1. 检测 `fnm` / `node` 是否已安装
2. 用 `winget install Schniz.fnm` 安装 fnm
3. 写入 `$PROFILE` 标记块（`fnm env` 初始化）
4. `Refresh-SessionPath` + `fnm install --lts`
5. 验证 `node --version` / `npm --version`

---

## Git — Git

**文件**：`Git.ps1`
**依赖核心模块**：`Process.ps1`, `Ui.ps1`

**安装流程**：`winget install Git.Git` → 配置 4 项 Git 推荐设置 → 写入 Git Bash UTF-8（Python + PowerShell wrapper）→ 验证 `git --version` / `git config --list --global`

---

## ClaudeCode — Claude Code

**文件**：`ClaudeCode.ps1`
**依赖核心模块**：`Process.ps1`, `Ui.ps1`

**安装流程**：`npm install -g @anthropic-ai/claude-code` → 验证 `claude --version`

---

## ApiKey — API Key 配置（HC-12 关键）

**文件**：`ApiKey.ps1`
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

此配置用于标记 Claude Code 环境已完成初始化，由 ApiKey 步骤自动创建。如果文件已存在，将合并写入，保留用户已有字段。

### 自定义供应商流程

1. 用户选择"自定义供应商"
2. 输入自定义 Base URL（必须以 `http://` 或 `https://` 开头）
3. 输入 API Key

> **禁止**写入 `anthropicApiKey`、`openaiApiKey` 等顶层字段。
> **禁止**写入 Anthropic / OpenAI / Azure 供应商。

---

## Ccline — ccline

**文件**：`Ccline.ps1`
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

## CcSwitch — cc-switch

**文件**：`CcSwitch.ps1`
**依赖核心模块**：`Process.ps1`, `Ui.ps1`, `Profile.ps1`

**功能**：Claude Code / Codex / Gemini CLI 全方位辅助工具

**安装**：npm 全局安装 cc-switch + 写入 `$PROFILE`。

---

## ClaudeConfig — Claude 基础配置

**文件**：`ClaudeConfig.ps1`
**配置路径**：`$env:USERPROFILE\.claude\settings.json`（与 ApiKey 同一文件）

**写入策略**：声明式字段管理，读取 -> 补缺失 -> 原子写入。仅管理 ClaudeConfig 自有字段，不覆盖 ApiKey（API Key/Base URL/modelMapping）、Ccline（statusLine）或用户自定义配置。

**ClaudeConfig 管辖的 env 字段**：

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

**其他 ClaudeConfig 管辖字段**：

| 字段 | 默认值 | 写入策略 |
|------|--------|----------|
| `language` | `简体中文` | 仅补缺失 |
| `model` | `sonnet` | 仅补缺失 |
| `permissions.allow` | 14 项基础权限 | 合并（只添加缺失项，不删除已有项） |
| `attribution` | `{ commit: "", pr: "" }` | 仅补缺失 |

**ClaudeConfig 不触碰的字段**：`statusLine`（Ccline）、`hooks`（用户/插件）、`outputStyle`（用户自定义）、`mcpServers`（Mcp）、`env.ANTHROPIC_AUTH_TOKEN`/`env.ANTHROPIC_BASE_URL`/`modelMapping`（ApiKey）、`env.CODEAGENT_POST_MESSAGE_DELAY`/`env.CODEX_TIMEOUT`（CcgWorkflow）

> **注意**：statusLine 配置完全由 Ccline 步骤负责，ClaudeConfig 不触碰 statusLine 字段。

---

## ClaudeMd — CLAUDE.md 配置

**文件**：`ClaudeMd.ps1`
**目标**：`$env:USERPROFILE\.claude\CLAUDE.md` + `$env:USERPROFILE\.claude\rules\`
**依赖**：无（不依赖 Claude 基础配置）

**功能**：生成全局 Claude Code 工作规范。主文件 ~80 行（确保在 token 截断限制内完整可见），详细内容拆分到 `rules/` 目录（Claude Code 无条件加载）。

**瘦身结构**：
- `CLAUDE.md`（~80 行）：核心原则 / 工作流原则 / 任务分级 / 交互与环境+输出设置
- `rules/ccg-multimodel.md`：多模型协作（Codex/Gemini 调用格式、会话复用、并行调用）
- `rules/ccg-tools.md`：工具速查表 + 知识获取 + 设计图获取
- `rules/ccg-workflow.md`：工作流增强（上下文检索、Prompt 增强、需求对齐）

**写入方式**：`Write-FileAtomically -FilePath`（**注意参数名**）。主文件和 rules 文件均采用备份 + 原子覆写。

**检测条件**：`Test-ClaudeMdInstalled` 检查主文件 3 个关键标识 + 3 个 rules 文件存在性。

---

## Mcp — MCP Server 配置

**文件**：`Mcp.ps1`
**配置路径**：
- `$env:USERPROFILE\.claude.json` - MCP Server 配置（mcpServers）
- `$env:USERPROFILE\.claude\settings.json` - 权限配置（permissions）

**功能**：在 .claude.json 中写入 `mcpServers` 配置块，在 settings.json 中写入权限配置，支持多个 MCP 插件服务器。
变量插值注意使用 `${serverId}` 格式（避免冒号歧义）。

**增量安装支持**：
- 设置 `SkipIfInstalled = $false`，允许用户每次都能进入选择菜单
- 自动检测已安装的 MCP Server 并在选项中标记 `[已安装]`
- 默认只选中推荐的且未安装的 MCP Server
- 自动跳过已安装的 MCP Server，只安装新选择的

**contextweaver 安装增强**：针对 Windows 权限问题，添加了 npm 缓存清理和 `--force` 重试机制，解决 EPERM 错误导致的安装失败。

**检测逻辑修复**：
1. 修复了 Pencil 软件存在时错误跳过 MCP 配置的问题
2. 修复了配置文件路径错误：MCP Server 配置应写入 `~/.claude.json`，而不是 `settings.json`
3. 现在只有当 .claude.json 中有实际的 stdio/http MCP Server 配置时才返回 true（但不会跳过安装）

---

## CcgWorkflow — CCG 工作流

**文件**：`CcgWorkflow.ps1`
**依赖**：NodeFnm + ClaudeConfig

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
- `--skip-mcp`：安装前后对 `settings.json` 的 `mcpServers` 做快照比对，保护 Mcp 步骤的 MCP 配置
- 超时/重试：`TimeoutSeconds 300`，`RetryCount 3`
- 安装后立即调用 `Refresh-SessionPath`

---

## CodexCli — Codex CLI（可选）

**文件**：`CodexCli.ps1`

```powershell
# 正确调用方式（无 -DisplayName 参数）
$installOut = Invoke-NpmGlobalInstall -PackageName "codex-cli"
```

---

## GeminiCli — Gemini CLI（可选）

**文件**：`GeminiCli.ps1`

```powershell
# 正确调用方式（无 -DisplayName 参数）
$installOut = Invoke-NpmGlobalInstall -PackageName "gemini-cli"
```

---

## 新增步骤模板

添加新步骤时遵循此模板：

```powershell
#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Process.ps1"

function Test-<StepId>Installed {
    $result = @{ IsInstalled = $false; Version = ""; Data = @{}; Message = "" }
    try {
        # 检测逻辑
        $result.IsInstalled = $true
    } catch {
        $result.Message = $_.Exception.Message
    }
    return $result
}

function Install-<StepId> {
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

function Verify-<StepId> {
    $result = @{ Success = $false; ErrorMessage = "" }
    try {
        # 验证逻辑
        $result.Success = $true
    } catch {
        $result.ErrorMessage = $_.Exception.Message
    }
    return $result
}
```

在 `core/Registry.ps1` 的 `Get-StepRegistry` 中注册新步骤条目（含 StepId、函数名、依赖、分组、Order 等），依赖关系和分组信息均从 Registry 自动派生，无需额外维护。
