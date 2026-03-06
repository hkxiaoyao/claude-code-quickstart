<div align="center">
<pre>
  ██████╗  ██████╗  ██████╗
 ██╔════╝ ██╔════╝ ██╔═══██╗
 ██║      ██║      ██║   ██║
 ██║      ██║      ██║▄▄ ██║
  ╚██████╗ ╚██████╗ ╚██████╔╝
  ╚═════╝  ╚═════╝  ╚══▀▀═╝
</pre>

**Claude Code Quickstart** — Windows 平台的 Claude Code 开发环境自动化安装器

一键完成从零到 Claude Code 的全套环境配置：Node.js、Git、Claude Code CLI、第三方 AI 供应商配置、MCP 插件、CCG 工作流等 12 个步骤，**全程自动化，实时检测**。

</div>

---

## 特性

- **云端直接执行**：一条命令从零到完整环境，无需下载任何文件（`irm + iex`）
- **双阶段架构**：PS 5.1 引导脚本 → PS 7 主安装脚本，兼容未升级 PowerShell 的系统
- **单文件分发**：支持构建为独立可执行的单文件脚本，无需携带整个源码目录
- **依赖自动排序**：步骤按拓扑依赖顺序执行，无需手动关心安装顺序
- **实时检测**：每次运行都实时检测组件状态，已安装组件自动跳过，无状态漂移问题
- **两种安装模式**：一键安装全部组件 / 分阶段手动选择需要的组件
- **统一管理系统**：更新已安装组件、管理 AI 供应商配置、管理 MCP Server，一站式管理
- **MCP 管理器**：交互式管理 MCP Server — 查看状态、启用/禁用、删除，凭据持久化
- **国内 AI 供应商适配**：支持智谱 GLM、MiniMax、Kimi（月之暗面），开箱即用，供应商管理支持完整 CRUD
- **智能命令验证**：验证命令实际可执行性，避免 PATH 记录存在但文件缺失的误报

---

## 系统要求

| 要求 | 说明 |
|------|------|
| 操作系统 | Windows 10 1903 (Build 18362) 或更高版本 / Windows 11 |
| 权限 | **管理员权限**（右键 → 以管理员身份运行） |
| 网络 | 可访问 npm registry、GitHub（代理可选） |
| PowerShell | 5.1 即可启动引导脚本，引导脚本会自动安装 PS 7 |

---

## 快速开始

### 方式一：云端直接执行 ⚡

**适用场景**：零配置、一条命令搞定、适合快速体验

#### 引导脚本（PS 5.1+，以管理员身份运行）

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
[Text.Encoding]::UTF8.GetString((New-Object Net.WebClient).DownloadData('https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/Bootstrap-ClaudeEnv.built.ps1')) | iex
```

> 使用 `WebClient.DownloadData` + `UTF8.GetString` 显式 UTF-8 解码，避免 PS 5.1 默认代码页导致中文乱码

#### 安装 Claude Code 环境（PS 7+）

引导完成后，在 **PowerShell 7**（`pwsh`）中运行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm 'https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/Install-ClaudeEnv.built.ps1' | iex
```

#### 管理已安装环境（PS 7+）

```powershell
# 交互式管理（更新/供应商/MCP）
irm 'https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/Manage-ClaudeEnv.built.ps1' | iex
```

---

### 方式二：下载单文件执行（推荐）

**适用场景**：网络不稳定、需要离线安装、想先查看脚本内容

从 [Releases](../../releases) 下载所需脚本文件。

#### 引导脚本（PS 5.1+，以管理员身份运行）

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\Bootstrap-ClaudeEnv.built.ps1
```

#### 安装 Claude Code 环境（PS 7+）

```powershell
pwsh -File ".\Install-ClaudeEnv.built.ps1"
```

#### 管理已安装环境（PS 7+）

```powershell
# 交互式管理（更新/供应商/MCP）
pwsh -File ".\Manage-ClaudeEnv.built.ps1"

# CLI 模式示例
pwsh -File ".\Manage-ClaudeEnv.built.ps1" -Action Update -ListUpdates
pwsh -File ".\Manage-ClaudeEnv.built.ps1" -Action Provider -ListProviders
```

---

### 方式三：从源码运行（开发者模式）

**适用场景**：需要自定义修改、参与开发、调试安装器

#### 引导脚本（PS 5.1+，以管理员身份运行）

```powershell
git clone https://github.com/MrNine-666/claude-code-quickstart.git
cd claude-code-quickstart
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\installer\Bootstrap-ClaudeEnv.ps1
```

引导脚本会自动完成：检测 Windows 版本 → 安装 winget → 推荐 Windows Terminal → **安装 PowerShell 7** → 配置 Git Bash UTF-8

#### 安装 Claude Code 环境（PS 7+）

```powershell
pwsh -File ".\installer\Install-ClaudeEnv.ps1"
```

#### 管理已安装环境（PS 7+）

```powershell
# 交互式管理（更新/供应商/MCP）
pwsh -File ".\installer\Manage-ClaudeEnv.ps1"

# CLI 模式示例
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Update -ListUpdates
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Provider -ListProviders
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Provider -Provider zhipu
```

---

## 安装说明

分组安装将步骤分为**基础环境**和**进阶扩展**两组：
- **基础环境**：Node.js、Git、Claude Code、第三方供应商配置 — 一键安装，无需选择
- **进阶扩展**：ccline、cc-switch、配置优化、MCP、多模型工具 — 支持一键或多选

安装器采用**实时检测机制**，每次运行都检测所有组件当前状态，已安装的自动跳过，失败后直接重新运行即可。

```powershell
# 查看全部步骤列表及状态
pwsh -File ".\Install-ClaudeEnv.built.ps1" -ListSteps       # 单文件版
pwsh -File ".\installer\Install-ClaudeEnv.ps1" -ListSteps   # 源码版
```

---

## 更新说明

可更新步骤（8 个）：

| 步骤 | 更新策略 |
|------|---------|
| ClaudeCode | npm install @latest + 版本回退保护 |
| ClaudeConfig | 声明式对齐 env 字段 + 废弃键清理 |
| ClaudeMd | 原子覆写 CLAUDE.md 及 rules/ 文件 |
| Ccline | npm @latest + 重新 patch Claude Code |
| CcgWorkflow | npx ccg-workflow@latest init |
| CodexCli | npm install @latest |
| GeminiCli | npm install @latest |
| OpenSpec | npm install @latest |

> **更新前自动备份**：更新前在 `%TEMP%\ClaudeEnvInstaller\Backups\` 创建快照目录，保留最近 5 个快照，方便回滚。
> 更新组件请使用 `Manage-ClaudeEnv.ps1 -Action Update` 或交互式管理菜单。

---

## MCP 管理

安装 MCP Server 后，可通过内置的 MCP 管理器对已配置的 MCP Server 进行状态管理。

### 进入 MCP 管理

```powershell
# 在管理脚本中选择"MCP 管理"
pwsh -File ".\installer\Manage-ClaudeEnv.ps1"
# → 选择 [MCP 管理]

# 或直接通过 CLI 进入
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Mcp
```

### 功能说明

| 功能 | 说明 |
|------|------|
| **查看状态** | 显示所有 MCP Server 的运行状态（Active / Disabled / Missing） |
| **启用/禁用** | 切换 MCP Server 启用状态，禁用后配置保留在凭据 vault 中 |
| **删除** | 彻底删除 MCP Server 配置及凭据 |

凭据持久化到 `~/.ccq/mcp-meta.json`，重新安装时自动读取历史凭据并提示填充，无需重复输入。

---

## 安装内容

| # | 步骤 | 说明 | 分组 | 可选 |
|---|------|------|------|:----:|
| 01 | Node.js (fnm) | 安装 fnm 版本管理器 + Node.js LTS | 基础 | — |
| 02 | Git | 安装 Git，配置中文支持 | 基础 | — |
| 03 | Claude Code | 全局安装 `@anthropic-ai/claude-code` | 基础 | — |
| 04 | 第三方供应商配置 | 配置第三方 AI 供应商连接 | 基础 | — |
| 05 | ccline | 安装 ccline 状态栏工具 | 进阶 | — |
| 06 | cc-switch | Claude Code / Codex / Gemini CLI 全方位辅助工具 | 进阶 | ✓ |
| 07 | Claude 基础配置 | 写入语言/模型/权限/环境变量配置 | 进阶 | — |
| 08 | CLAUDE.md | 生成全局 Claude Code 工作规范文件 | 进阶 | — |
| 09 | MCP Server | 配置 MCP 插件服务器 | 进阶 | — |
| 10 | CCG 工作流 | 安装 Claude Code Generator 工作流 | 进阶 | — |
| 11 | Codex CLI | 安装 OpenAI Codex CLI（多模型协作） | 进阶 | ✓ |
| 12 | Gemini CLI | 安装 Google Gemini CLI（多模型协作） | 进阶 | ✓ |

---

## 第三方供应商配置

安装器支持以下国内 AI 供应商，无需翻墙即可使用 Claude Code：

| 供应商 | 最新模型系列 | 模型映射（2026-02 更新） | 获取 Key |
|--------|------------|------------------------|---------|
| **智谱 GLM** | GLM-5, GLM-4.7, GLM-4-Plus | 服务端自动路由（无需配置） | [open.bigmodel.cn](https://open.bigmodel.cn) |
| **MiniMax** | M2.5, M2.1, abab6.5 | opus/sonnet/haiku → MiniMax-M2.5 | [platform.minimaxi.com](https://platform.minimaxi.com) |
| **Kimi (月之暗面)** | K2.5, K2-turbo, moonshot-v1 | opus/sonnet/haiku → kimi-k2.5 | [platform.moonshot.cn](https://platform.moonshot.cn) |
| **自定义供应商** | 自定义 | 可自定义模型映射 | 手动输入 Base URL 和 API Key |

供应商配置和模型映射写入 `~/.claude/settings.json`：

**智谱 GLM（服务端自动路由）**：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-api-key",
    "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic"
  }
}
```

**MiniMax（统一使用 M2.5）**：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-api-key",
    "ANTHROPIC_BASE_URL": "https://api.minimaxi.com/anthropic"
  },
  "modelMapping": {
    "opus": "MiniMax-M2.5",
    "sonnet": "MiniMax-M2.5",
    "haiku": "MiniMax-M2.5"
  }
}
```

**Kimi（统一使用 K2.5）**：
```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-api-key",
    "ANTHROPIC_BASE_URL": "https://api.moonshot.cn/anthropic"
  },
  "modelMapping": {
    "opus": "kimi-k2.5",
    "sonnet": "kimi-k2.5",
    "haiku": "kimi-k2.5"
  }
}
```

### 供应商管理

配置供应商后，安装器会自动保存 Profile 文件到 `~/.claude/providers/`。供应商管理（查看/切换/添加/修改/删除）通过管理脚本完成：

```powershell
# 交互式供应商管理
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Provider

# CLI 直接切换供应商
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Provider -Provider zhipu

# 查看供应商列表
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Provider -ListProviders
```

切换时从 Profile 读取配置，合并到 `settings.json`（仅覆盖供应商字段，不影响其他配置）。切换后直接运行 `claude` 即可使用新供应商。

---

## 项目结构

```
claude-code-quickstart/
├── installer/
│   ├── Bootstrap-ClaudeEnv.ps1   # PS 5.1 引导入口
│   ├── Install-ClaudeEnv.ps1     # PS 7+ 安装入口（基础环境 + 进阶扩展）
│   ├── Manage-ClaudeEnv.ps1      # PS 7+ 统一管理入口（更新/供应商/MCP）
│   ├── build/                    # 构建工具目录
│   │   ├── Build-SingleFile.ps1  # 单文件打包构建脚本
│   │   └── dist/                 # 构建产物输出（gitignored，由 CI 自动构建）
│   ├── core/                     # 核心功能模块
│   │   ├── Ui.ps1                # TUI 组件（彩色输出、菜单、进度条）
│   │   ├── Process.ps1           # 外部命令执行封装
│   │   ├── Profile.ps1           # $PROFILE 安全编辑
│   │   ├── Admin.ps1             # 管理员权限管理
│   │   ├── Net.ps1               # 网络检测与代理配置
│   │   ├── Registry.ps1          # 共享步骤注册表（元数据、分组、依赖）
│   │   ├── Bootstrap.ps1         # 步骤状态模型与调度引擎
│   │   ├── McpManager.ps1        # MCP Server 管理（状态/启用/禁用/删除/凭据 vault）
│   │   └── Provider.ps1          # 供应商管理核心（CRUD + Sync + 菜单）
│   └── steps/                    # 安装步骤模块（语义化命名）
│       ├── NodeFnm.ps1
│       ├── Git.ps1
│       ├── ...
│       └── GeminiCli.ps1
└── test-syntax.ps1               # 语法全量校验工具
```

---

## 安装后使用

```powershell
# 启动 Claude Code
claude

# 查看帮助
claude --help

# 使用 Codex CLI（需已安装）
codex --help

# 使用 Gemini CLI（需已安装）
gemini --help
```

> **cc-switch**：安装后可在开始菜单或桌面快捷方式启动，提供 Claude Code / Codex / Gemini CLI 的图形化辅助管理。

---

## 常见问题

**Q：云端直接执行安全吗？**

- ✓ 脚本托管在 GitHub，内容完全公开透明
- ✓ 执行前可以先访问 URL 查看脚本源码
- ✓ 建议使用 Releases 中的稳定版本 URL
- ✓ 如果担心安全性，可以使用方式二下载后本地执行

**Q：云端执行失败怎么办？**

可能原因及解决方案：
1. **网络问题**：GitHub 访问受限，使用镜像加速或下载单文件脚本
2. **执行策略限制**：先运行 `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force`
3. **权限不足**：确保以管理员身份运行 PowerShell

**Q：安装中途失败了怎么办？**

直接重新运行安装器即可，实时检测机制会自动跳过已安装组件：

```powershell
# 单文件版
pwsh -File ".\Install-ClaudeEnv.built.ps1"

# 源码版
pwsh -File ".\installer\Install-ClaudeEnv.ps1"
```

**Q：想重新配置供应商？**

通过管理脚本的供应商管理功能完成：

```powershell
# 交互式供应商管理（查看/切换/添加/修改/删除）
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Provider

# CLI 直接切换
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Action Provider -Provider zhipu
```

**Q：运行脚本报 "无法加载文件" 错误？**

需要先设置执行策略：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

**Q：如何验证所有脚本语法正确？**

```powershell
# 源码模式下验证所有源文件
pwsh -File test-syntax.ps1

# 或验证构建后的单文件脚本
pwsh -File ".\installer\build\Build-SingleFile.ps1"
```

**Q：构建后的单文件脚本和源码版本有什么区别？**

- **功能完全相同**：两者执行逻辑一致，只是文件组织方式不同
- **单文件版本**：适合快速分发，无需携带整个源码目录，下载即用
- **源码版本**：适合开发调试，可以单独修改某个模块文件，便于维护和扩展

> **注意**：构建后的单文件脚本不在仓库中，需从 [Releases](../../releases) 下载，
> 或本地运行 `pwsh -File ".\installer\build\Build-SingleFile.ps1"` 自行构建。

---

## 构建单文件脚本

如果你需要生成可分发的单文件版本（用于 Releases 发布），可以使用构建脚本：

```powershell
# 在 PowerShell 7 中运行
pwsh -File ".\installer\build\Build-SingleFile.ps1"
```

构建脚本会自动：
- ✓ 按依赖顺序合并所有源文件
- ✓ 移除 dot-source 引用和重复的 #Requires 声明
- ✓ 生成三个单文件脚本到 `installer/build/dist/` 目录：
  - `Bootstrap-ClaudeEnv.built.ps1` - 引导脚本（PS 5.1+）
  - `Install-ClaudeEnv.built.ps1` - 安装脚本（PS 7+，基础 + 进阶）
  - `Manage-ClaudeEnv.built.ps1` - 管理脚本（PS 7+，更新/供应商/MCP）
- ✓ 自动进行语法检查验证

构建产物可直接分发给用户使用，无需携带整个源码目录。

---

## 开发者文档

- [安装器入口文档](installer/CLAUDE.md)
- [核心模块文档](installer/core/CLAUDE.md)
- [步骤模块文档 + 新步骤模板](installer/steps/CLAUDE.md)

---

## License

[MIT](LICENSE)
