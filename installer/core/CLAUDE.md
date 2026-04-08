# installer/core/ — 核心基础库

> 面包屑：[根目录](../../CLAUDE.md) › [installer/](../CLAUDE.md) › core/
> 生成时间：2026-03-06 (Install+Manage 分离架构)

所有核心模块通过 **dot-source** 加载（非 Module），无 `Export-ModuleMember`，函数在调用方作用域内直接可用。

---

## 模块一览

| 文件 | 行数 | 职责 |
|------|------|------|
| `Ui.ps1` | 893 | TUI 组件：语义颜色系统（6 色）、菜单、进度、摘要表格 |
| `Process.ps1` | 492 | 外部命令执行、PATH 刷新、版本检测、npm/winget 封装 |
| `Profile.ps1` | 526 | `$PROFILE` 安全编辑：备份、标记块读写、原子写入 |
| `Admin.ps1` | 137 | 管理员权限检测与自提权 |
| `Net.ps1` | ~270 | 端点可达性检测、文件下载 |
| `Registry.ps1` | 280 | **共享步骤注册表**：元数据、分组、依赖、迁移映射（消除 DRY 违规） |
| `Bootstrap.ps1` | 617 | 步骤状态模型、生命周期调度、拓扑排序、恢复逻辑 |
| `McpManager.ps1` | ~890 | MCP Server CRUD 管理：vault 读写、状态查看、禁用/启用/删除、凭据持久化 |
| `Provider.ps1` | ~810 | 供应商管理核心：CRUD + Sync + 交互菜单，Install-ApiKey 和 Manage 共用 |

---

## Ui.ps1

### 终端能力检测

初始化时自动检测（`Initialize-TerminalCapabilities`）：
- `$script:IsWindowsTerminal`：环境变量 `$env:WT_SESSION` 不为空
- `$script:SupportsAnsi`：PS 6+ 或 Windows Terminal 时为 `$true`

> 所有 UI 函数在 `SupportsAnsi = false` 时自动降级为纯文本 ASCII 模式。

### 语义颜色系统（6 色）

| 函数 | 语义角色 | 颜色（ANSI 模式） | 用途 |
|------|---------|-----------------|------|
| `Write-UiSuccess` | 成功 | 亮绿 `\e[92m` | 成功确认、完成提示 |
| `Write-UiPrimary` | 品牌/进行中 | Claude Orange `\e[38;2;217;119;87m` | 标题、横幅、活跃进度 |
| `Write-UiWarning` | 警告 | 亮黄 `\e[93m` | 警告、可恢复错误 |
| `Write-UiDanger` | 危险 | 亮红 `\e[91m` | 错误、失败 |
| `Write-UiInfo` | 信息 | 白色 `\e[97m` | 数据、路径、指令性文本 |
| `Write-UiDim` | 次要 | 灰色 `\e[90m` | 时间戳、提示、装饰分隔线 |

> **零逃逸约束**：`$script:AnsiColors` 和 `-ForegroundColor` **仅限** `Ui.ps1` 内部使用。外部文件通过 `Write-Ui*` 函数访问颜色。入口脚本在 Ui.ps1 加载前的早期错误处理块（PS 版本检查）例外。

### 通用输出调度器

```powershell
Write-UiOutput $Message -Type <Primary|Info|Success|Warning|Danger|Dim>
```

### UI 组件函数

| 函数 | 用途 |
|------|------|
| `Show-AsciiBanner` | 自适应宽度的 `╔═╗` 横幅（Primary 色） |
| `Show-SingleSelectMenu` | 箭头键单选（不支持 ANSI 时数字输入降级） |
| `Show-MultiSelectMenu` | 空格多选菜单（同上降级） |
| `Show-StepProgress` | 状态指示：`[PASS]` / `[FAIL]` / `[SKIP]` |
| `Show-InstallSummary` | 安装结果表格（动态列宽） |
| `Show-ErrorDetails` | 友好信息 + 按 `D` 键展开技术详情（SC-5） |

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
| `Test-CommandAvailable` | `-Command [-ReturnDetails] [-TimeoutSeconds=10]` | `$true/$false` 或详细诊断对象 |
| `Get-CommandVersion` | `-Command` | `string` 版本号 |
| `Refresh-SessionPath` | — | void（刷新当前会话 PATH） |
| `Invoke-NpmGlobalInstall` | `-PackageName [-Version] [-Force]` | `@{Success; Error; Data}` |
| `Invoke-WingetInstall` | `-PackageId -PackageName [-Silent] [-AcceptLicense]` | `@{Success; ErrorMessage}` |

> **注意**：`Invoke-NpmGlobalInstall` **无 `-DisplayName` 参数**，步骤文件调用时不要传此参数。

> **HC-WINGET-SILENT（强约束）**：`Invoke-WingetInstall` 传入 `-Silent` 时，内部自动切换为重定向模式（`RedirectStandardOutput/Error = $true`）并异步消费缓冲区，以抑制 winget 进度条噪音（如 `Removed N of M files`）。**禁止**在 `-Silent` 模式下将 `RedirectStandardOutput/RedirectStandardError` 设为 `$false`——否则进度条输出会泄漏到终端且可能死锁。

> **HC-PS1-PATH-QUOTE（强约束）**：`Invoke-ExternalCommand` 对 `.ps1` 文件通过 `pwsh.exe -File` 执行时，若路径含空格**必须**加双引号包裹（`"`"$path"`"`），否则 `ProcessStartInfo.Arguments -join ' '` 拼接后路径被截断（如 `C:\Program Files\nodejs\npm.ps1` → `-File C:\Program`），退出码 64。

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
| `Invoke-SelfElevated` | `-ScriptPath -ArgumentList` | void（重启进程） |
| `Assert-StepPrivilege` | `-StepName [-RequiresAdmin=$true] [-ScriptPath]` | **`$true/$false`（布尔，非对象）** |

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
    [datetime]$StartTime
    [string]$Mode             # "OneClick" | "Staged" | "Manage-Basic" | "Manage-Advanced"
    [hashtable]$StepResults   # key = StepId（仅本次会话内的结果）
    [hashtable]$GlobalData
    [string]$CurrentStep; [bool]$IsCompleted
}
```

### 步骤依赖图（由 `Registry.ps1` 的 `Get-StepDependencies` 提供）

```powershell
"NodeJS"      = @()
"Git"           = @()
"ClaudeCode"    = @("NodeJS")
"ApiKey"        = @("ClaudeCode")
"Ccline"        = @("ClaudeCode")
"CcSwitch"      = @("ClaudeCode")
"ClaudeConfig"  = @("ClaudeCode")
"ClaudeMd"      = @()
"Mcp"           = @("ClaudeCode")
"CcgWorkflow"   = @("NodeJS")
"CodexCli"      = @("NodeJS")
"GeminiCli"     = @("NodeJS")
"OpenSpec"      = @("NodeJS")
```

### 主要函数

| 函数 | 职责 |
|------|------|
| `Invoke-StepLifecycle` | 执行 Test → Install → Verify 三阶段（完全基于实时检测） |
| `Test-StepDependencies` | 检查前置依赖（实时检测 + 会话状态）|
| `Get-ExecutionOrder` | Kahn 拓扑排序 + Registry Order 字段 tie-break |

> **重要变更**：移除了所有持久化函数（`Save-InstallState`、`Load-InstallState`、`Resume-Installation`、`Clear-InstallState`），采用纯内存状态管理 + 实时检测机制。

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

### 实时检测机制

**核心原则**：每次运行都实时检测组件状态，不依赖缓存的历史记录。

- `Invoke-StepLifecycle`：每次都执行 `Test` 函数检测当前环境
- `Test-StepDependencies`：优先检查本次会话内的失败状态（阻止执行），然后实时调用依赖的 `Test` 函数检测是否真的已安装
- 已安装的组件自动跳过，无需手动管理状态文件

---

## McpManager.ps1

### 职责

MCP Server 生命周期管理：凭据 vault 读写、状态查看、禁用/启用/删除、批量切换、管理菜单。

### 数据模型

**Vault 文件**: `~/.ccq/mcp-meta.json`（Schema v1）

```json
{
  "schemaVersion": 1,
  "createdAt": "ISO 8601",
  "updatedAt": "ISO 8601",
  "servers": {
    "<serverId>": {
      "disabled": false,
      "credentials": { "values": {}, "envFileValues": {} },
      "definitionHash": "8 hex chars (SHA-256)",
      "updatedAt": "ISO 8601"
    }
  }
}
```

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `$McpMetaSchemaVersion` | `1` | vault schema 版本 |
| `$McpMaxCorruptBackups` | `5` | 腐败备份最大数量 |
| `$McpMutexName` | `Global\CCQ.Mcp.Lock` | 并发保护 Mutex |
| `$McpMutexTimeoutMs` | `30000` | Mutex 超时（30s） |

### 主要函数

| 函数 | 职责 |
|------|------|
| `Ensure-CcqMetaDir` | 确保 `~/.ccq/` 目录存在 |
| `Get-McpMetaPath` | 返回 vault 文件路径 |
| `New-EmptyMcpMeta` | 创建空 v1 vault |
| `Read-McpMeta` | 读取 vault + 腐败恢复 + schema 校验 |
| `Write-McpMeta` | 原子写入 vault + 时间戳更新 |
| `Invoke-WithMcpLock` | Mutex 包装（防止并发写入） |
| `Get-McpDefinitionHash` | SHA-256 前 8 位哈希 |
| `Get-McpStatus` | 计算所有 MCP 状态（Custom/Disabled/Active/Missing） |
| `Show-McpStatusTable` | 彩色表格输出 |
| `Disable-McpServer` | 禁用（保存配置到 vault，从 .claude.json 移除） |
| `Enable-McpServer` | 启用（从 vault 恢复，重建配置） |
| `Remove-McpServer` | 删除（清理所有相关文件） |
| `Invoke-McpToggle` | 批量切换（Active↔Disabled） |
| `Show-McpManageMenu` | 交互管理菜单（状态/切换/删除） |

> **加载顺序**：McpManager.ps1 必须在 Bootstrap.ps1 之后、steps/ 之前加载。依赖 Ui.ps1、Process.ps1、Profile.ps1 的函数。运行时依赖 Mcp.ps1 的 `$script:McpServers` 和 `New-McpSettingsEntry`。

---

## Provider.ps1

### 职责

**v2.0.0 新增**：供应商管理核心模块，提供完整 CRUD + 自动同步 + 交互菜单。被 `Install-ApiKey` 和 `Manage-ClaudeEnv.ps1` 共用。

### 内置供应商模板

```powershell
$script:BuiltinProviders = @{
    zhipu    = @{ Name = "智谱 GLM"; BaseUrl = "https://open.bigmodel.cn/api/anthropic"; ... }
    minimax  = @{ Name = "MiniMax"; BaseUrl = "https://api.minimaxi.com/anthropic"; ModelEnv = @{...} }  # M2.7
    moonshot = @{ Name = "Kimi (Moonshot)"; BaseUrl = "https://api.moonshot.cn/anthropic"; ModelEnv = @{...} }
    bailian  = @{ Name = "阿里云百炼"; BaseUrl = "https://coding.dashscope.aliyuncs.com/apps/anthropic"; RequireModelConfig = $true }
    custom   = @{ Name = "自定义供应商"; BaseUrl = "" }
}
```

### 主要函数

| 函数 | 职责 |
|------|------|
| `Get-ProviderSettingsPath` | 返回 `~/.claude/settings.json` 路径（私有辅助） |
| `Get-ProviderProfilesDir` | 返回 `~/.claude/providers/` 目录路径 |
| `Read-SettingsJson` | 安全读取 settings.json 为 hashtable |
| `Write-SettingsJsonAtomic` | 原子写入 settings.json（temp + Move-Item） |
| `Get-ProviderManagedModelEnvFromLegacyAliases` | 兼容读取旧版别名映射字段并转换为模型 env 键 |
| `Get-ProviderManagedModelEnv` | 从 Profile 提取受管模型 env 键 |
| `Set-ProviderManagedModelEnv` | 写入 Profile 的 `modelEnv` 并清理旧字段 |
| `Get-ProviderManagedModelSummary` | 生成人类可读的模型配置摘要 |
| `Sync-ProviderFromSettings` | 从 settings.json 反向生成 Profile（迁移旧用户） |
| `Get-ProviderProfiles` | 扫描 `~/.claude/providers/*.json`，返回 Profile 数组 |
| `Get-ActiveProvider` | 识别当前活跃供应商（BaseUrl 匹配） |
| `Show-ProviderStatus` | 显示供应商状态表格（CJK-aware padding） |
| `Add-Provider` | 交互式添加供应商（`-Activate` 开关控制自动激活） |
| `Edit-Provider` | 修改已有供应商配置（API Key / Base URL / 名称 / 全部） |
| `Remove-Provider` | 删除供应商（活跃供应商安全阻止） |
| `Switch-Provider` | 切换活跃供应商（Profile → settings.json 合并） |
| `Show-ProviderManageMenu` | 供应商管理交互菜单（while 循环，Esc 返回） |

### 设计要点

- **安装复用**：`Add-Provider -Activate` 被 `Install-ApiKey` 直接调用，安装步骤不再自行实现供应商选择
- **自动同步**：`Sync-ProviderFromSettings` 在进入供应商管理菜单时自动执行
- **单一数据源**：`$script:BuiltinProviders` 是内置供应商的唯一定义
- **SecureString**：API Key 输入使用 `Read-Host -AsSecureString`，内存中用后即清
- **原子写入**：所有 Profile 和 settings.json 操作均为 temp + Move-Item

### 加载顺序

Provider.ps1 在 McpManager.ps1 之后加载。依赖 Ui.ps1、Profile.ps1 的函数。被 steps/ApiKey.ps1 dot-source 引用。
