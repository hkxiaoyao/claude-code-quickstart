# installer/core/ — 核心基础库

> 面包屑：[根目录](../../CLAUDE.md) › [installer/](../CLAUDE.md) › core/
> 生成时间：2026-02-23 (架构重构后更新)

所有核心模块通过 **dot-source** 加载（非 Module），无 `Export-ModuleMember`，函数在调用方作用域内直接可用。

---

## 模块一览

| 文件 | 行数 | 职责 |
|------|------|------|
| `Ui.ps1` | 648 | TUI 组件：彩色输出、菜单、进度、摘要表格 |
| `Process.ps1` | 492 | 外部命令执行、PATH 刷新、版本检测、npm/winget 封装 |
| `Profile.ps1` | 526 | `$PROFILE` 安全编辑：备份、标记块读写、原子写入 |
| `Admin.ps1` | 137 | 管理员权限检测与自提权 |
| `Net.ps1` | ~270 | 端点可达性检测、文件下载 |
| `Registry.ps1` | 280 | **共享步骤注册表**：元数据、分组、依赖、迁移映射（消除 DRY 违规） |
| `Bootstrap.ps1` | 617 | 步骤状态模型、生命周期调度、拓扑排序、恢复逻辑 |

---

## Ui.ps1

### 终端能力检测

初始化时自动检测（`Initialize-TerminalCapabilities`）：
- `$script:IsWindowsTerminal`：环境变量 `$env:WT_SESSION` 不为空
- `$script:SupportsAnsi`：PS 6+ 或 Windows Terminal 时为 `$true`

> 所有 UI 函数在 `SupportsAnsi = false` 时自动降级为纯文本 ASCII 模式。

### 主要函数

| 函数 | 颜色（ANSI 模式） | 用途 |
|------|-----------------|------|
| `Write-UiInfo` | 青色 `\e[36m` | 信息、步骤说明 |
| `Write-UiSuccess` | 亮绿 `\e[92m` | 成功确认 |
| `Write-UiWarn` | 亮黄 `\e[93m` | 警告、可恢复错误 |
| `Write-UiError` | 亮红 `\e[91m` | 错误、失败 |
| `Show-AsciiBanner` | 青色 | 自适应宽度的 `╔═╗` 横幅 |
| `Show-SingleSelectMenu` | — | 箭头键单选（不支持 ANSI 时数字输入降级） |
| `Show-MultiSelectMenu` | — | 空格多选菜单（同上降级） |
| `Show-StepProgress` | 按状态着色 | 状态指示：`[PASS]` / `[FAIL]` / `[SKIP]` |
| `Show-InstallSummary` | 按状态着色 | 安装结果表格（动态列宽） |
| `Show-ErrorDetails` | — | 友好信息 + 按 `D` 键展开技术详情（SC-5） |

**关键约束**：
- SC-3：状态指示器固定为 `[PASS]` / `[FAIL]` / `[SKIP]`（不用 ✓/✗）
- SC-5：`Show-ErrorDetails` 监听 `D` 键展开，其他键跳过

---

## Process.ps1

### 全局配置

```powershell
$script:DefaultRetryCount      = 3
$script:DefaultTimeoutSeconds  = 300
```

### 主要函数

| 函数 | 签名摘要 | 返回 |
|------|---------|------|
| `Invoke-ExternalCommand` | `-Command -Arguments [-WorkingDirectory] [-TimeoutSeconds] [-RetryCount] [-SuppressOutput]` | `@{ExitCode; Output; Error}` |
| `Test-CommandAvailable` | `-Command` | `$true/$false` |
| `Get-CommandVersion` | `-Command` | `string` 版本号 |
| `Refresh-SessionPath` | — | void（刷新当前会话 PATH） |
| `Invoke-NpmGlobalInstall` | `-PackageName [-Version] [-Force]` | `@{Success; Error; Data}` |
| `Invoke-WingetInstall` | `-PackageId -PackageName [-Silent] [-AcceptLicense]` | `@{Success; ErrorMessage}` |

> **注意**：`Invoke-NpmGlobalInstall` **无 `-DisplayName` 参数**，步骤文件调用时不要传此参数。

---

## Profile.ps1

### 标记块格式（HC-4）

```powershell
$script:ManagedBlockStartMarker = "# >>> Claude Code Quickstart >>>"
$script:ManagedBlockEndMarker   = "# <<< Claude Code Quickstart <<<"
```

### 备份目录

```powershell
$script:BackupDirectory = "$env:TEMP\ClaudeEnvInstaller\Backups"
```

### 主要函数

| 函数 | 职责 |
|------|------|
| `Backup-FileWithTimestamp` | 带时间戳备份文件（`yyyyMMdd_HHmmss`） |
| `Get-ManagedBlockContent` | 读取标记块内容，返回 `Found/Content/BeforeBlock/AfterBlock` |
| `Set-ManagedBlockInFile` | 写入/更新标记块（原子写入），`-CreateIfNotExists -AppendIfNoBlock` |
| `Remove-ManagedBlockFromFile` | 从文件移除标记块 |
| `Test-ManagedBlockExists` | 检测标记块是否存在 |
| `Write-FileAtomically` | **参数 `-FilePath`（非 `-Path`）**，临时文件 + `Move-Item -Force` |
| `Clear-OldBackups` | 清理超过 N 天或超过 M 个的备份文件 |

---

## Admin.ps1

### 主要函数

| 函数 | 签名 | 返回 |
|------|------|------|
| `Test-IsAdministrator` | — | `$true/$false` |
| `Invoke-SelfElevated` | `-ScriptPath -ArgumentList [-StateFilePath]` | void（重启进程） |
| `Assert-StepPrivilege` | `-StepName [-RequiresAdmin=$true] [-ScriptPath] [-StateFilePath]` | **`$true/$false`（布尔，非对象）** |

> **关键**：`Assert-StepPrivilege` 返回 **布尔值**，调用方直接用 `if (-not $privilegeResult)` 判断，不能用 `.Success`。

---

## Net.ps1

### 主要函数

| 函数 | 返回 |
|------|------|
| `Test-EndpointReachable -Url -TimeoutSeconds` | `@{Url; Reachable; StatusCode; ErrorMessage; LatencyMs}` |
| `Invoke-FileDownload -Url -OutputPath [-Description] [-TimeoutSeconds]` | `@{Success; FilePath; ErrorMessage; FileSize}` |

---

## Registry.ps1

### 职责

**v1.2.0 新增**：共享步骤注册表，消除 `Install-ClaudeEnv.ps1` 与 `Manage-ClaudeEnv.ps1` 之间的重复定义。

### 主要函数

| 函数 | 返回 | 职责 |
|------|------|------|
| `Get-StepRegistry` | `hashtable[]` | 返回完整注册表数组（含 Order、Dependencies、Group、LegacyIds） |
| `Get-StepGroups` | `hashtable` | 从注册表动态派生 Basic/Advanced 分组 |
| `Get-StepDependencies` | `hashtable` | 提取 StepId → 依赖数组映射 |
| `Get-LegacyStepIdMap` | `hashtable` | 旧 → 新 StepId 映射（状态迁移用） |
| `Get-StepFiles` | `string[]` | 按 Order 排序的步骤文件路径数组 |

> **加载顺序**：Registry.ps1 必须在 Bootstrap.ps1 之前加载（Bootstrap 的 `Get-ExecutionOrder` 和 `Load-InstallState` 依赖 Registry 函数）。

---

## Bootstrap.ps1

### 数据模型

```powershell
enum StepStatus { Pending=0; Running=1; Success=2; Failed=3; Skipped=4 }

class StepResult {
    [string]$StepId; [string]$StepName; [StepStatus]$Status
    [string]$Message; [hashtable]$Data
    [datetime]$StartTime; [datetime]$EndTime; [string]$ErrorDetails
}

class InstallState {
    [string]$Version          # "1.0"
    [datetime]$StartTime; [datetime]$LastUpdateTime
    [string]$Mode             # "OneClick" | "Staged"
    [hashtable]$StepResults   # key = StepId
    [hashtable]$GlobalData
    [string]$CurrentStep; [bool]$IsCompleted
    [string]$InstallationId   # GUID
}
```

### 步骤依赖图（由 `Registry.ps1` 的 `Get-StepDependencies` 提供）

```powershell
"NodeFnm"      = @()
"Git"           = @()
"ClaudeCode"    = @("NodeFnm")
"ApiKey"        = @("ClaudeCode")
"Ccline"        = @("ClaudeCode")
"CcSwitch"      = @("ClaudeCode")
"ClaudeConfig"  = @("ClaudeCode")
"ClaudeMd"      = @("ClaudeConfig")
"Mcp"           = @("ClaudeCode")
"CcgWorkflow"   = @("NodeFnm")
"CodexCli"      = @("NodeFnm")
"GeminiCli"     = @("NodeFnm")
```

### 主要函数

| 函数 | 职责 |
|------|------|
| `Save-InstallState / Load-InstallState` | JSON 持久化（原子写入），Load 含旧 StepId 自动迁移 |
| `Resume-Installation` | 加载状态并显示进度摘要 |
| `Invoke-StepLifecycle` | 执行 Test → Install → Verify 三阶段 |
| `Test-StepDependencies` | 检查前置依赖是否 Success/Skipped |
| `Get-ExecutionOrder` | Kahn 拓扑排序 + Registry Order 字段 tie-break |

> **注意**：回滚功能已移除，安装失败时仅记录状态，用户可使用 `-Resume` 重试。

### `Invoke-StepLifecycle` 兼容性

调度器兼容步骤函数的两种返回类型：

```powershell
# Test 函数：兼容 bool 和 @{IsInstalled=...; ...}
$isInstalled = if ($testResult -is [bool]) { $testResult }
               elseif ($testResult) { [bool]$testResult.IsInstalled }
               else { $false }

# Install/Verify 函数：兼容 bool 和 @{Success=...; ErrorMessage=...; ...}
$success = if ($result -is [bool]) { $result }
           elseif ($result) { [bool]$result.Success }
           else { $false }
```

### 状态文件路径

```powershell
$script:StateFilePath = "$env:TEMP\ClaudeEnvInstaller\install-state.json"
```
