# installer/ — 安装器入口层

> 面包屑：[根目录](../CLAUDE.md) › installer/
> 生成时间：2026-02-20 15:24:29

---

## 文件职责

| 文件 | PS 版本 | 职责 |
|------|---------|------|
| `Bootstrap-ClaudeEnv.ps1` | 5.1+ | 前置检测：Windows 版本 → winget → Windows Terminal → **PS 7 安装** → Git Bash UTF-8 |
| `Install-ClaudeEnv.ps1` | **7.0+** | 主安装：dot-source 所有模块 → 选择模式 → 拓扑排序执行 12 步 → 摘要 |

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

**用途**：PS 7 主安装入口，协调全部 12 个步骤。

### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `-Resume` | switch | 从上次失败点继续（加载 `install-state.json`） |
| `-OneClick` | switch | 跳过模式选择，直接一键安装所有步骤 |
| `-Staged` | switch | 跳过模式选择，直接进入分阶段选择菜单 |
| `-ListSteps` | switch | 列出所有注册步骤及依赖后退出 |

### 加载顺序

```powershell
# 核心模块（顺序敏感）
. core/Ui.ps1 → Process.ps1 → Profile.ps1 → Admin.ps1 → Net.ps1 → Bootstrap.ps1

# 步骤模块（顺序无关，依赖由 Bootstrap.ps1 拓扑排序管理）
. steps/Step01.NodeFnm.ps1 ... steps/Step12.GeminiCli.ps1
```

> **重要**：使用 `$script:InstallerRoot = $PSScriptRoot` 固定根路径，防止被 dot-source 覆盖。

### 步骤注册表（`$script:StepRegistry`）

每条记录的字段：

```powershell
@{
    StepId          = "Step06.ApiKey"       # 与 Bootstrap.ps1 依赖图 key 一致
    StepName        = "API Key 配置"
    Description     = "..."
    TestFunction    = "Test-Step06Installed"
    InstallFunction = "Install-Step06"
    VerifyFunction  = "Verify-Step06"        # 空字符串 = 不验证
    RollbackFunction = "Rollback-Step06"     # 空字符串 = 不回滚
    SkipIfInstalled = $false                 # false = 每次都重新配置
    IsOptional      = $false                 # true = 分阶段模式默认不勾选
}
```

### 核心函数

| 函数 | 职责 |
|------|------|
| `Select-InstallMode` | 交互菜单选择 OneClick / Staged |
| `Select-StagedSteps` | 多选菜单，必选步骤预勾选 |
| `Invoke-AllSteps` | 拓扑排序 → 依赖检查 → `Invoke-StepLifecycle` |
| `Show-FinalSummary` | 调用 `Show-InstallSummary` 展示结果表格 |
| `Main` | 总入口；处理 `-ListSteps` / `-Resume` / 模式选择 |

### 执行流

```
Main()
  ├── [if -ListSteps] Show-StepList → exit
  ├── Load-InstallState 或 Resume-Installation
  ├── Select-InstallMode（或读取参数）
  ├── Select-StagedSteps（Staged 模式）
  ├── Invoke-AllSteps
  │   ├── Get-ExecutionOrder  # 拓扑排序
  │   └── foreach stepId:
  │       ├── Test-StepDependencies  # 前置依赖检查
  │       └── Invoke-StepLifecycle   # Test → Install → Verify → Rollback
  └── Show-FinalSummary
      └── Save-InstallState (IsCompleted)
```

---

## 可选步骤（IsOptional = true）

| 步骤 | 说明 |
|------|------|
| Step11.CodexCli | OpenAI Codex CLI，多模型协作使用 |
| Step12.GeminiCli | Google Gemini CLI，多模型协作使用 |

在 Staged 模式下，可选步骤**默认不勾选**。在 OneClick 模式下，**全部包含**。
