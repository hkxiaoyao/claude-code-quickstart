# installer/ — 安装器入口层

> 面包屑：[根目录](../CLAUDE.md) › installer/
> 生成时间：2026-02-23 (架构重构后更新)

---

## 文件职责

| 文件 | PS 版本 | 职责 |
|------|---------|------|
| `Bootstrap-ClaudeEnv.ps1` | 5.1+ | 前置检测：Windows 版本 → winget → Windows Terminal → **PS 7 安装** → Git Bash UTF-8 |
| `Install-ClaudeEnv.ps1`（维护中） | **7.0+** | 全量安装：动态加载 Registry → 选择模式 → 拓扑排序执行 13 步 → 摘要 |
| `Manage-ClaudeEnv.ps1` | **7.0+** | 分组安装（推荐）：基础环境（NodeFnm~ApiKey）/ 进阶扩展（Ccline~OpenSpec）两级分组 |
| `Update-ClaudeEnv.ps1` | **7.0+** | 统一更新：声明式更新已安装组件，支持交互多选 / CLI 指定 / 全量更新 |

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

> **状态**：维护中，暂不推荐使用。请使用 `Manage-ClaudeEnv.ps1`。

**用途**：PS 7 主安装入口，协调全部 13 个步骤。

### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `-OneClick` | switch | 跳过模式选择，直接一键安装所有步骤 |
| `-Staged` | switch | 跳过模式选择，直接进入分阶段选择菜单 |
| `-ListSteps` | switch | 列出所有注册步骤及依赖后退出 |

### 加载顺序

```powershell
# 核心模块（顺序敏感：Registry 在 Bootstrap 之前）
. core/Ui.ps1 → Process.ps1 → Profile.ps1 → Admin.ps1 → Net.ps1 → Registry.ps1 → Bootstrap.ps1 → McpManager.ps1

# 步骤模块（从 Registry 动态加载，按 Order 字段排序）
$stepFiles = Get-StepFiles
foreach ($stepFile in $stepFiles) {
    . "$script:InstallerRoot\$stepFile"
}
```

> **重要**：使用 `$script:InstallerRoot = $PSScriptRoot` 固定根路径，防止被 dot-source 覆盖。

### 步骤注册表（从 `core/Registry.ps1` 动态加载）

**v1.2.0 架构变更**：步骤注册表已迁移到共享模块 `core/Registry.ps1`，消除 Install/Manage 之间的重复定义。

每条记录的字段（示例）：

```powershell
@{
    StepId          = "ApiKey"              # 语义化 ID（无数字前缀）
    StepName        = "第三方供应商配置"
    Description     = "配置第三方 AI 供应商连接到 ~/.claude/settings.json"
    StepFile        = "steps/ApiKey.ps1"    # 相对 installer/ 的路径
    TestFunction    = "Test-ApiKeyInstalled"
    InstallFunction = "Install-ApiKey"
    VerifyFunction  = "Verify-ApiKey"
    SkipIfInstalled = $true                 # true = 已安装时跳过
    IsOptional      = $false                # false = 必选步骤
    Order           = 40                    # 拓扑排序 tie-break 权重
    Dependencies    = @("ClaudeCode")       # 前置依赖 StepId 数组
    Group           = "Basic"               # Basic / Advanced
    LegacyIds       = @("Step04.ApiKey")    # 旧 StepId（用于状态迁移）
}
```

**加载方式**：

```powershell
. "$script:InstallerRoot\core\Registry.ps1"
$script:StepRegistry = Get-StepRegistry
$script:StepGroups = Get-StepGroups  # Manage-ClaudeEnv.ps1 使用
```

### 核心函数

| 函数 | 职责 |
|------|------|
| `Select-InstallMode` | 交互菜单选择 OneClick / Staged |
| `Invoke-StagedMode` | 单选迭代式分阶段安装（循环选择 → 依赖检查 → 执行 → 返回） |
| `Invoke-AllSteps` | 拓扑排序 → 依赖检查 → `Invoke-StepLifecycle`（OneClick 模式使用） |
| `Show-FinalSummary` | 调用 `Show-InstallSummary` 展示结果表格 |
| `Main` | 总入口；处理 `-ListSteps` / 模式选择 |

### 执行流

```
Main()
  ├── [if -ListSteps] Show-StepList → exit
  ├── 创建新的安装状态（纯内存，不持久化）
  ├── Select-InstallMode（或读取参数）
  ├── [if OneClick]
  │   ├── Invoke-AllSteps（全部步骤）
  │   │   ├── Get-ExecutionOrder  # 拓扑排序
  │   │   └── foreach stepId:
  │   │       ├── Test-StepDependencies  # 前置依赖检查（实时检测）
  │   │       └── Invoke-StepLifecycle   # Test → Install → Verify
  │   └── Show-FinalSummary（无 Logo，简化快速开始）
  └── [if Staged]
      └── Invoke-StagedMode（迭代式单选）
          ├── 构建步骤列表（带状态标签 PASS/FAIL/LOCK/空）
          ├── Show-SingleSelectMenu → 用户选择一个步骤
          ├── Esc → 退出循环 → Show-FinalSummary
          ├── Test-StepDependencies → 依赖检查（实时检测）
          ├── 依赖未满足 → 提示 → 回到选择
          └── Invoke-StepLifecycle → 展示结果 → 回到选择
```

---

## 可选步骤（IsOptional = true）

| 步骤 | 说明 |
|------|------|
| CcSwitch | cc-switch，Claude Code / Codex / Gemini CLI 全方位辅助工具 |
| CodexCli | OpenAI Codex CLI，多模型协作使用 |
| GeminiCli | Google Gemini CLI，多模型协作使用 |

在 Staged 模式下，用户通过**单选迭代式菜单**逐个选择步骤执行，每次执行后返回菜单。可选步骤同样列出，带状态标签标识。在 OneClick 模式下，**全部包含**。

---

## Manage-ClaudeEnv.ps1

**用途**：PS 7 分组安装入口（推荐），将 13 个步骤分为**基础环境**和**进阶扩展**两组。

### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `-ListSteps` | switch | 列出所有步骤（按分组显示）后退出 |
| `-Group` | string | 指定分组：`Basic`（基础环境）或 `Advanced`（进阶扩展） |
| `-Mode` | string | 进阶扩展安装模式：`OneClick` 或 `Select` |
| `-Staged` | switch | 兼容旧参数，等同于 `-Group Advanced -Mode Select` |

### 步骤分组

| 分组 | 步骤 | 安装模式 |
|------|------|----------|
| **基础环境** | NodeFnm, Git, ClaudeCode, ApiKey | 仅一键安装 |
| **进阶扩展** | Ccline, CcSwitch, ClaudeConfig, ClaudeMd, Mcp, CcgWorkflow, CodexCli, GeminiCli, OpenSpec | 一键或多选 |

### 核心函数

| 函数 | 职责 |
|------|------|
| `Get-GroupStatus` | 统计分组内步骤完成状态 |
| `Get-DependencyClosure` | 计算传递依赖闭包，自动补齐跨组依赖 |
| `Show-ExecutionPlan` | 显示执行计划（含自动补齐的依赖）并确认 |
| `Invoke-GroupedInstall` | 依赖闭包 → 确认 → 拓扑排序 → 执行 |
| `Show-AdvancedSelectMenu` | 进阶多选菜单（带状态标签和智能默认勾选） |
| `Select-TopLevelAction` | 顶层菜单：基础环境 / 进阶扩展 / MCP 管理 |
| `Select-AdvancedAction` | 进阶子菜单：一键安装 / 可选安装 |

### 执行流

```
Main()
  ├── [if -ListSteps] Show-StepList（按分组显示） → exit
  ├── Show-AsciiBanner
  ├── 创建新的安装状态（纯内存，不持久化）
  │
  ├── [CLI 模式]（-Group 参数）
  │   ├── Basic → Invoke-GroupedInstall(基础步骤) → Show-FinalSummary（无 Logo，简化快速开始）
  │   ├── Advanced/OneClick → Invoke-GroupedInstall(进阶步骤) → Show-FinalSummary
  │   ├── Advanced/Select → Show-AdvancedSelectMenu → Invoke-GroupedInstall → Show-FinalSummary
  │   └── Mcp → Show-McpManageMenu（查看状态 / 切换 / 删除）
  │
  └── [交互模式]（无 -Group 参数） while($true):
      ├── Select-TopLevelAction
      ├── [基础环境] → Invoke-GroupedInstall(基础步骤) → Show-FinalSummary
      ├── [进阶扩展] → Select-AdvancedAction
      │   ├── [一键] → Invoke-GroupedInstall(进阶步骤)
      │   ├── [可选] → Show-AdvancedSelectMenu → Invoke-GroupedInstall
      │   └── [Esc] → 回到顶层
      ├── [MCP 管理] → Show-McpManageMenu（查看状态 / 切换 / 删除）
      └── [Esc] → 退出
```

---

## Update-ClaudeEnv.ps1

**用途**：PS 7 统一更新入口，交互式多选更新已安装组件。

### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `-ListUpdates` | switch | 列出所有可更新步骤及状态后退出 |

### 可更新步骤（8 个）

| StepId | UpdateFunction | 更新策略 |
|--------|---------------|---------|
| ClaudeCode | Update-ClaudeCode | npm install @latest + 版本回退 |
| ClaudeConfig | Update-ClaudeConfig | 声明式对齐 env 键 + 废弃键清理 |
| ClaudeMd | Update-ClaudeMd | 原子覆写 CLAUDE.md + ccq- rules |
| Ccline | Update-Ccline | npm @latest + 重新 patch |
| CcgWorkflow | Update-CcgWorkflow | npx ccg-workflow@latest init |
| CodexCli | Update-CodexCli | npm install @latest |
| GeminiCli | Update-GeminiCli | npm install @latest |
| OpenSpec | Update-OpenSpec | npm install @latest |

### 不可更新步骤（5 个）

NodeFnm、Git、ApiKey、CcSwitch、Mcp — 需通过 Manage 重新安装。

### 核心机制

- **Mutex**: `Global\CCQ.Update.Lock`，防止并发更新
- **快照备份**: 更新前创建 `update_*` 目录，保留最近 5 个
- **UpdatedItems 契约**: `<Scope>::<Target>::<Change>` 格式（如 `npm::claude-code::1.2.3->1.3.0`）
- **依赖闭包**: 自动补齐更新依赖 + ClaudeCode→Ccline 后置联动

### 执行流

```
Main()
  ├── 统一检测所有组件状态（Get-UpdateStatus）
  ├── 展示组件状态表（Show-UpdateStatus，仅显示已安装组件）
  ├── [if -ListUpdates] 退出
  ├── Mutex 获取（不等待，失败则退出）
  ├── try:
  │   ├── 交互多选（Select-UpdateSteps）
  │   ├── 构建执行计划（Build-UpdatePlan）
  │   ├── 指纹预检（跳过模板未变更的步骤）
  │   ├── 创建快照（New-UpdateSnapshot）
  │   ├── 遍历执行计划 → Invoke-UpdateLifecycle
  │   ├── 清理旧快照（Clear-OldUpdateSnapshots）
  │   └── Show-UpdateSummary（分四类：Updated/Up-to-Date/Failed/Skipped）
  └── finally: 释放 Mutex
```
