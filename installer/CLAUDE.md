# installer/ — 安装器入口层

> 面包屑：[根目录](../CLAUDE.md) › installer/
> 生成时间：2026-03-06 (Install+Manage 分离架构)

---

## 文件职责

| 文件 | PS 版本 | 职责 |
|------|---------|------|
| `Bootstrap-ClaudeEnv.ps1` | 5.1+ | 前置检测：Windows 版本 → winget → Windows Terminal → **PS 7 安装** → Git Bash UTF-8 |
| `Install-ClaudeEnv.ps1` | **7.0+** | 安装入口（推荐）：基础环境（NodeJS~ApiKey）/ 进阶扩展（增强配置、MCP、Skills、Workflow）两级分组 |
| `Manage-ClaudeEnv.ps1` | **7.0+** | 统一管理：更新已安装组件 / 供应商管理（CRUD + 切换）/ MCP Server 管理 / Skills 管理 |

---

## Bootstrap-ClaudeEnv.ps1

**用途**：用户最先运行的入口，兼容旧版 PowerShell（5.1）。

**执行流程**：
```
Main()
  ├── Assert-StepPrivilege -StepName "引导脚本" -RequiresAdmin $true   # 管理员检查
  ├── Test-WindowsVersion        → 需 Windows 10 1903 (10.0.18362)+
  ├── Test-WingetAvailability    → 检测 winget
  ├── Install-WindowsTerminal    → 软性推荐，用户可跳过
  ├── Install-PowerShell7        → 硬性前置，失败则 exit 1
  ├── Set-GitBashUtf8Config      → 写入 ~/.bashrc 标记块
  └── Show-CompletionMessage     → 提示运行 Install-ClaudeEnv.ps1
```

**完成后提示用户**：
```powershell
pwsh -File "$scriptRoot\Install-ClaudeEnv.ps1"
```

---

## Install-ClaudeEnv.ps1

**用途**：PS 7 安装入口（推荐），将 14 个步骤分为**基础环境**和**进阶扩展**两组。

### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `-ListSteps` | switch | 列出所有步骤（按分组显示）后退出 |
| `-Group` | string | 指定分组：`Basic`（基础环境）或 `Advanced`（进阶扩展） |
| `-Mode` | string | 进阶扩展安装模式：`OneClick` 或 `Select` |
| `-Staged` | switch | 兼容旧参数，等同于 `-Group Advanced -Mode Select` |
| `-OutputMode` | string | `Normal`（默认） / `Developer`（详细输出） |
| `-SkillsCopy` | switch | 仅影响 Skills 步骤：追加 `--copy`，适合 Windows symlink 权限受限场景 |

### 加载顺序

```powershell
# 核心模块（顺序敏感：Registry 在 Bootstrap 之前，Provider 在最后）
. core/Ui.ps1 → Process.ps1 → Profile.ps1 → Admin.ps1 → Net.ps1 → Registry.ps1 → Bootstrap.ps1 → McpManager.ps1 → Provider.ps1

# 步骤模块（从 Registry 动态加载，按 Order 字段排序）
$stepFiles = Get-StepFiles
foreach ($stepFile in $stepFiles) {
    . "$script:InstallerRoot\$stepFile"
}
```

> **重要**：使用 `$script:InstallerRoot = $PSScriptRoot` 固定根路径，防止被 dot-source 覆盖。

### 步骤分组

| 分组 | 步骤 | 安装模式 |
|------|------|----------|
| **基础环境** | NodeJS, Git, ClaudeCode, ApiKey | 仅一键安装 |
| **进阶扩展** | Ccline, ClaudeConfig, ClaudeMd, Mcp, CcgWorkflow, Skills, OpenSpec, CcSwitch, CodexCli, AntigravityCli | 一键或多选 |

### 核心函数

| 函数 | 职责 |
|------|------|
| `Get-GroupStatus` | 统计分组内步骤完成状态 |
| `Get-DependencyClosure` | 计算传递依赖闭包，自动补齐跨组依赖 |
| `Show-ExecutionPlan` | 显示执行计划（含自动补齐的依赖）并确认 |
| `Invoke-GroupedInstall` | 依赖闭包 → 确认 → 拓扑排序 → 执行 → 指纹种子写入 |
| `Show-AdvancedSelectMenu` | 进阶多选菜单（带状态标签和智能默认勾选） |
| `Select-TopLevelAction` | 顶层菜单：基础环境 / 进阶扩展 |
| `Select-AdvancedAction` | 进阶子菜单：一键安装 / 可选安装 |

### 执行流

```
Main()
  ├── [if -ListSteps] Show-StepList（按分组显示） → exit
  ├── Show-AsciiBanner
  ├── 创建新的安装状态（纯内存，不持久化）
  │
  ├── [CLI 模式]（-Group 参数）
  │   ├── Basic → Invoke-GroupedInstall(基础步骤) → Show-FinalSummary
  │   ├── Advanced/OneClick → Invoke-GroupedInstall(进阶必选步骤，排除可选 Skills/CLI) → Show-FinalSummary
  │   └── Advanced/Select → Show-AdvancedSelectMenu → Invoke-GroupedInstall → Show-FinalSummary
  │
  └── [交互模式]（无 -Group 参数） while($true):
      ├── Select-TopLevelAction
      ├── [基础环境] → Invoke-GroupedInstall(基础步骤) → Show-FinalSummary
      ├── [进阶扩展] → Select-AdvancedAction
      │   ├── [一键] → Invoke-GroupedInstall(进阶必选步骤，排除可选 Skills/CLI)
      │   ├── [可选] → Show-AdvancedSelectMenu → Invoke-GroupedInstall
      │   └── [Esc] → 回到顶层
      └── [Esc] → 退出
```

---

## 可选步骤（IsOptional = true）

| 步骤 | 说明 |
|------|------|
| Skills | Skills 用户级全局安装/更新/卸载；安装 source 单选、集合类支持子 Skills 多选；更新走官方 `skills update` |
| CcSwitch | cc-switch，Claude Code / Codex / Gemini CLI 全方位辅助工具 |
| CodexCli | OpenAI Codex CLI，多模型协作使用 |
| AntigravityCli | Google Antigravity CLI，多模型协作使用 |

在 Select/可选安装模式下，用户通过多选菜单选择步骤执行。可选步骤同样列出，带状态标签标识。在 OneClick 模式下，默认排除可选步骤。

---

## Manage-ClaudeEnv.ps1

**用途**：PS 7 统一管理入口，整合更新管理 + 供应商管理 + MCP 管理 + Skills 管理。

### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `-Action` | string | 管理动作：`Update` / `Mcp` / `Provider` / `Skills`（交互模式时可省略） |
| `-ListUpdates` | switch | 列出所有可更新步骤及状态后退出 |
| `-Provider` | string | CLI 直接切换供应商（如 `-Provider zhipu`） |
| `-ListProviders` | switch | 列出所有已配置供应商后退出 |
| `-OutputMode` | string | `Normal`（默认） / `Developer`（详细输出） |

### 四大子功能

| 子功能 | 来源 | 说明 |
|--------|------|------|
| 更新管理 | 迁移自旧 `Update-ClaudeEnv.ps1` | Mutex + 快照 + 指纹预检 + 交互多选 |
| 供应商管理 | `core/Provider.ps1` | 完整 CRUD + 自动同步 + 切换 |
| MCP 管理 | `core/McpManager.ps1` | 状态查看 / 启用/禁用 / 删除 |
| Skills 管理 | `steps/Skills.ps1` | 状态查看 / 安装 / 更新 / 卸载 |

### 可更新步骤（9 个）

| StepId | UpdateFunction | 更新策略 |
|--------|---------------|---------|
| ClaudeCode | Update-ClaudeCode | npm install @latest + 版本回退 |
| ClaudeConfig | Update-ClaudeConfig | 声明式对齐 env 键 + 废弃键清理 |
| ClaudeMd | Update-ClaudeMd | 原子覆写 CLAUDE.md + ccq- rules |
| Ccline | Update-Ccline | npm @latest + 重新 patch |
| CcgWorkflow | Update-CcgWorkflow | npx --yes ccg-workflow@latest init --skip-prompt --skip-mcp --lang zh-CN --install-dir ~/.claude |
| Skills | Update-Skills | npx --yes skills update -g -y |
| CodexCli | Update-CodexCli | npm install @latest |
| AntigravityCli | Update-AntigravityCli | agy update（失败回退官方安装脚本） |
| OpenSpec | Update-OpenSpec | npm install @latest |

### 核心机制

- **Mutex**: `Global\CCQ.Update.Lock`，防止并发更新
- **快照备份**: 更新前创建 `update_*` 目录，保留最近 5 个
- **UpdatedItems 契约**: `<Scope>::<Target>::<Change>` 格式
- **指纹预检**: SHA-256 指纹比对，模板未变更时自动跳过

### 执行流

```
Main()
  ├── Show-AsciiBanner
  │
  ├── [CLI 模式]（-Action 参数）
  │   ├── -Action Update [-ListUpdates]
  │   │   ├── Get-UpdateStatus
  │   │   ├── [if -ListUpdates] 退出
  │   │   └── Invoke-UpdateAction（Mutex + 交互多选 + 执行 + 摘要）
  │   ├── -Action Provider [-ListProviders | -Provider <key>]
  │   │   ├── [if -ListProviders] Show-ProviderStatus → 退出
  │   │   ├── [if -Provider] Switch-Provider → 退出
  │   │   └── Show-ProviderManageMenu（交互式 CRUD）
  │   ├── -Action Mcp
  │   │   └── Show-McpManageMenu
  │   └── -Action Skills
  │       └── Show-SkillsManageMenu
  │
  └── [交互模式]（无 -Action 参数） while($true):
      ├── Select-ManageAction（更新管理 / 供应商管理 / MCP 管理 / Skills 管理）
      ├── [更新管理] → Invoke-UpdateAction
      ├── [供应商管理] → Show-ProviderManageMenu
      ├── [MCP 管理] → Show-McpManageMenu
      ├── [Skills 管理] → Show-SkillsManageMenu
      └── [Esc] → 退出
```
