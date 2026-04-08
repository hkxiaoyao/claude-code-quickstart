# installer/steps/ — 安装步骤模块

> 面包屑：[根目录](../../CLAUDE.md) › [installer/](../CLAUDE.md) › steps/
> 生成时间：2026-03-06 (Install+Manage 分离架构)

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

### Update 函数契约（可选）

可更新步骤额外实现 `Update-<StepId>` 函数，由 Registry 的 `UpdateFunction` 字段注册：

```powershell
# 执行更新（仅可更新步骤需要实现）
function Update-<StepId> {
    return @{
        Success      = [bool]
        ErrorMessage = [string]
        Data         = @{}
        UpdatedItems = @(        # 变更记录数组
            "<Scope>::<Target>::<Change>"
            # 示例: "npm::claude-code::1.2.3->1.3.0"
            # 示例: "config::env.KEY::added"
            # 示例: "noop::StepId::no-change"
        )
    }
}
```

> 8 个步骤实现了 Update 函数：ClaudeCode、ClaudeConfig、ClaudeMd、Ccline、CcgWorkflow、CodexCli、GeminiCli、OpenSpec。
> 5 个步骤不可更新（UpdateFunction 为空）：NodeJS、Git、ApiKey、CcSwitch、Mcp。

> **注意**：Bootstrap.ps1 的 `Invoke-StepLifecycle` / `Invoke-UpdateLifecycle` 同时兼容 `bool` 和 `hashtable` 两种返回类型（向后兼容旧步骤）。

---

## 步骤总览

| StepId | 名称 | 文件 | 可选 | SkipIfInstalled | 可更新 | 主要依赖 | 分组 |
|--------|------|------|:----:|:---------------:|:------:|---------|------|
| NodeJS | Node.js (fnm) | `NodeJS.ps1` | — | ✓ | — | 无 | 基础 |
| Git | Git | `Git.ps1` | — | ✓ | — | 无 | 基础 |
| ClaudeCode | Claude Code | `ClaudeCode.ps1` | — | ✓ | ✓ | NodeJS | 基础 |
| ApiKey | 第三方供应商配置 | `ApiKey.ps1` | — | ✓ | — | ClaudeCode | 基础 |
| Ccline | ccline | `Ccline.ps1` | — | ✓ | ✓ | ClaudeCode | 进阶 |
| CcSwitch | cc-switch | `CcSwitch.ps1` | **✓** | ✓ | — | ClaudeCode | 进阶 |
| ClaudeConfig | Claude 基础配置 | `ClaudeConfig.ps1` | — | ✓ | ✓ | ClaudeCode | 进阶 |
| ClaudeMd | CLAUDE.md 配置 | `ClaudeMd.ps1` | — | ✓ | ✓ | ClaudeConfig | 进阶 |
| Mcp | MCP Server 配置 | `Mcp.ps1` | — | ✓ | — | ClaudeCode | 进阶 |
| CcgWorkflow | CCG 工作流 | `CcgWorkflow.ps1` | — | ✓ | ✓ | NodeJS | 进阶 |
| CodexCli | Codex CLI | `CodexCli.ps1` | **✓** | ✓ | ✓ | NodeJS | 进阶 |
| GeminiCli | Gemini CLI | `GeminiCli.ps1` | **✓** | ✓ | ✓ | NodeJS | 进阶 |
| OpenSpec | OpenSpec CLI | `OpenSpec.ps1` | — | ✓ | ✓ | NodeJS | 进阶 |

---

## NodeJS — Node.js (fnm)

**文件**：`NodeJS.ps1`
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

## ApiKey — 第三方供应商配置（HC-12 关键）

**文件**：`ApiKey.ps1`
**依赖核心模块**：`Provider.ps1`（供应商 CRUD + 交互菜单）
**配置路径**：`$env:USERPROFILE\.claude\settings.json`

### 架构变更（Install+Manage 分离）

ApiKey 步骤已精简为**薄包装层**，核心供应商逻辑委托给 `core/Provider.ps1`：

| 职责 | 旧版 ApiKey.ps1 (~710行) | 新版 ApiKey.ps1 (~170行) |
|------|--------------------------|--------------------------|
| 供应商模板 | `$script:ApiProviders` 自行定义 | 引用 `Provider.ps1` 的 `$script:BuiltinProviders` |
| 供应商选择 + API Key 输入 | 自行实现完整流程 | 委托 `Add-Provider -Activate` |
| Profile 文件管理 | 自行写入 `~/.claude/providers/` | 由 `Provider.ps1` 统一管理 |
| 供应商切换 (ccp) | 注入 `Switch-ClaudeProvider` 到 `$PROFILE` | **已移除**，改用 `Manage → 供应商管理` |
| settings.json 写入 | 自行实现 JSON 合并 | 由 `Provider.ps1` 的 `Switch-Provider` 处理 |

### SkipIfInstalled

`SkipIfInstalled = $true`（注册表已更新）。首次配置后自动跳过，用户通过 `Manage-ClaudeEnv.ps1 -Action Provider` 管理供应商。

### Install-ApiKey 流程

```
Install-ApiKey($state)
  ├── 清理旧版 ccp 标记块（Remove-ManagedBlockFromFile）
  ├── 调用 Add-Provider -Activate（委托给 Provider.ps1）
  │   ├── 供应商选择菜单（内置 4 个 + 自定义）
  │   ├── API Key 输入（SecureString）
  │   ├── 写入 Provider Profile → ~/.claude/providers/<key>.json
  │   └── 激活：合并到 settings.json
  └── 写入 ~/.claude.json（hasCompletedOnboarding = true）
```

### 供应商模板（定义于 Provider.ps1）

内置供应商由 `core/Provider.ps1` 的 `$script:BuiltinProviders` 统一定义：

| Key | Name | 模型配置 |
|-----|------|----------|
| `zhipu` | 智谱 GLM | 无（服务端自动路由） |
| `minimax` | MiniMax | 3 个模型环境键均写入 `MiniMax-M2.5` |
| `moonshot` | Kimi (Moonshot) | 3 个模型环境键均写入 `kimi-k2.5` |
| `custom` | 自定义供应商 | 无（用户按需配置） |

### 写入格式（HC-12）

**~/.claude/settings.json**（所有供应商，模型选择统一写入 env）：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "<API_KEY>",
    "ANTHROPIC_BASE_URL": "<BaseUrl>",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "<HaikuModel>",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "<OpusModel>",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "<SonnetModel>"
  }
}
```

> 若某供应商不需要模型覆盖，则只写入 `ANTHROPIC_AUTH_TOKEN` 与 `ANTHROPIC_BASE_URL`。历史旧版别名映射字段会在切换供应商时自动迁移为上述 env 键。

**~/.claude.json**：
```json
{
  "hasCompletedOnboarding": true
}
```

此配置用于标记 Claude Code 环境已完成初始化，由 ApiKey 步骤自动创建。如果文件已存在，将合并写入，保留用户已有字段。

### 供应商后续管理

安装完成后，供应商的增删改查和切换统一通过 `Manage-ClaudeEnv.ps1 -Action Provider` 管理（详见 [core/CLAUDE.md](../core/CLAUDE.md) Provider.ps1 章节）。

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

## CcSwitch — cc-switch [可选]

**文件**：`CcSwitch.ps1`
**依赖核心模块**：`Process.ps1`, `Ui.ps1`, `Admin.ps1`, `Net.ps1`

**功能**：Claude Code / Codex / Gemini CLI 全方位辅助桌面软件

**安装**：从 GitHub Release (`farion1231/cc-switch`) 下载 MSI/EXE → 静默安装（需管理员权限）。非 CLI 工具，安装后通过开始菜单或桌面快捷方式启动。

---

## ClaudeConfig — Claude 基础配置

**文件**：`ClaudeConfig.ps1`
**配置路径**：`$env:USERPROFILE\.claude\settings.json`（与 ApiKey 同一文件）

**写入策略**：声明式字段管理，读取 -> 补缺失 -> 原子写入。仅管理 ClaudeConfig 自有字段，不覆盖 ApiKey（供应商配置/Base URL/模型环境键）、Ccline（statusLine）或用户自定义配置。

**ClaudeConfig 管辖的 env 字段**：

| 字段 | 默认值 | 写入策略 |
|------|--------|----------|
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
| `permissions.allow` | 14 项基础权限 | 合并（只添加缺失项，不删除已有项） |
| `attribution` | `{ commit: "", pr: "" }` | 仅补缺失 |

**ClaudeConfig 不触碰的字段**：`model`（用户自行选择）、`statusLine`（Ccline）、`hooks`（用户/插件）、`outputStyle`（用户自定义）、`mcpServers`（Mcp）、`env.ANTHROPIC_AUTH_TOKEN`/`env.ANTHROPIC_BASE_URL`/`env.ANTHROPIC_DEFAULT_HAIKU_MODEL`/`env.ANTHROPIC_DEFAULT_OPUS_MODEL`/`env.ANTHROPIC_DEFAULT_SONNET_MODEL`（ApiKey）、`env.CODEAGENT_POST_MESSAGE_DELAY`/`env.CODEX_TIMEOUT`/`env.BASH_DEFAULT_TIMEOUT_MS`/`env.BASH_MAX_TIMEOUT_MS`（CcgWorkflow）

> **注意**：statusLine 配置完全由 Ccline 步骤负责，ClaudeConfig 不触碰 statusLine 字段。

---

## ClaudeMd — CLAUDE.md 配置

**文件**：`ClaudeMd.ps1`
**目标**：`$env:USERPROFILE\.claude\CLAUDE.md`
**依赖**：无（不依赖 Claude 基础配置）

**功能**：生成全局 Claude Code 工作规范主文件。~80 行（确保在 token 截断限制内完整可见）。详细的工具速查由 McpManager 动态渲染到 `rules/ccq-mcp-*.md`，多模型协作/工作流增强由 CcgWorkflow 管理到 `rules/ccq-ccgworkflow.md`。

**命名约定**：CCQ 管理的 rules 文件统一使用 `ccq-` 前缀，与用户自定义 rules 隔离。

**写入方式**：`Write-FileAtomically -FilePath`（**注意参数名**）。主文件采用原子覆写（直接替换，无备份）。

**检测条件**：`Test-ClaudeMdInstalled` 检查主文件 3 个关键标识。

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
1. 修复了配置文件路径错误：MCP Server 配置应写入 `~/.claude.json`，而不是 `settings.json`
2. 现在只有当 .claude.json 中有实际的 stdio/http MCP Server 配置时才返回 true（但不会跳过安装）

**Vault 集成（mcp-lifecycle）**：
- Install-Mcp Phase 3：凭据收集前读取 `~/.ccq/mcp-meta.json` 检查历史凭据，提示 `[Y/n]` 自动填充
- Install-Mcp Phase 5：`.claude.json` 写入成功后，通过 `Invoke-WithMcpLock` 将凭据持久化到 vault
- Update-Mcp（当前未注册到 Registry，不参与统一更新，仅保留备用）：`Clear-NpxCache` 清理 npx 缓存 + PreInstall npm-global 包更新
- 凭据在 vault 写入后立即清零（安全）
- Vault 读写失败不阻塞主流程（仅 warning）

**MCP Rules 动态渲染**：
- Install-Mcp 末尾调用 `Sync-AllMcpRules`，根据已启用的 MCP Server 动态生成 `rules/ccq-mcp-*.md` 文件
- 分类定义在 `core/McpManager.ps1` 的 `$script:McpRulesCategories` 中维护
- 3 个分类：Search（搜索）、Documentation（文档）、Development（代码检索）
- 某分类下所有 MCP 禁用时，对应 rules 文件自动删除

---

## CcgWorkflow — CCG 工作流

**文件**：`CcgWorkflow.ps1`
**依赖**：NodeJS + ClaudeConfig

**功能**：通过官方 `npx ccg-workflow@latest init` 安装 CCG Workflow 工作流引擎，并写入 `rules/ccq-ccgworkflow.md`（多模型协作 + 工作流增强策略）。

**安装命令**：
```powershell
npx --yes ccg-workflow@latest init --skip-prompt --skip-mcp --lang zh-CN --install-dir "$env:USERPROFILE\.claude"
```

**安装后目录结构**：
- `~/.claude/commands/ccg/` — 命令模板（Slash Commands）
- `~/.claude/agents/ccg/` — Agent 模板
- `~/.claude/.ccg/` — CCG 配置目录（含 config.toml）
- `~/.claude/bin/codeagent-wrapper.exe` — 核心二进制
- `~/.claude/rules/ccq-ccgworkflow.md` — CCG 工作流规则文件

**关键机制**：
- `--skip-mcp`：安装前后对 `settings.json` 的 `mcpServers` 做快照比对，保护 Mcp 步骤的 MCP 配置
- 超时/重试：`TimeoutSeconds 300`，`RetryCount 3`
- 安装后立即调用 `Refresh-SessionPath`
- 规则文件更新：更新时会清理遗留文件 `ccq-multimodel.md` / `ccq-tools.md` / `ccq-workflow.md`

**CcgWorkflow 管辖的 env 字段**：

| 字段 | 默认值 | 写入策略 |
|------|--------|----------|
| `CODEAGENT_POST_MESSAGE_DELAY` | `1` | Install 补缺失 / Update 声明式对齐 |
| `CODEX_TIMEOUT` | `7200` | Install 补缺失 / Update 声明式对齐 |
| `BASH_DEFAULT_TIMEOUT_MS` | `600000` | Install 补缺失 / Update 声明式对齐 |
| `BASH_MAX_TIMEOUT_MS` | `3600000` | Install 补缺失 / Update 声明式对齐 |

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
$installOut = Invoke-NpmGlobalInstall -PackageName "@google/gemini-cli"
```

**fnm multishell 兼容**：fnm 环境下 `gemini` 解析到 `.ps1` wrapper，`Invoke-ExternalCommand` 通过 `pwsh.exe -File` 执行时会挂起。因此所有版本检测和验证均通过 `npm list -g @google/gemini-cli` 完成，不执行 `gemini` 命令本身。私有辅助函数 `Get-GeminiCliVersionFromNpm` 封装了此逻辑。

---

## OpenSpec — OpenSpec CLI（可选）

**文件**：`OpenSpec.ps1`
**依赖核心模块**：`Process.ps1`, `Ui.ps1`

**安装流程**：`npm install -g @fission-ai/openspec` → PATH 刷新 → 验证 `openspec --version` / `openspec --help`

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
        Write-UiDanger $result.ErrorMessage
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
