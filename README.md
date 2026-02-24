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

一键完成从零到 Claude Code 的全套环境配置：Node.js、Git、Claude Code CLI、多 AI 供应商 API Key 配置、MCP 插件、CCG 工作流等 12 个步骤，**全程自动化，支持断点续传**。

</div>

---

## 特性

- **云端直接执行**：一条命令从零到完整环境，无需下载任何文件（`irm + iex`）
- **双阶段架构**：PS 5.1 引导脚本 → PS 7 主安装脚本，兼容未升级 PowerShell 的系统
- **单文件分发**：支持构建为独立可执行的单文件脚本，无需携带整个源码目录
- **依赖自动排序**：步骤按拓扑依赖顺序执行，无需手动关心安装顺序
- **断点续传**：安装中途失败或中断后，使用 `-Resume` 从断点继续，无需重头再来
- **两种安装模式**：一键安装全部组件 / 分阶段手动选择需要的组件
- **国内 AI 供应商适配**：支持智谱 GLM、MiniMax、Kimi（月之暗面），开箱即用
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

### 方式一：云端直接执行（最快捷）⚡

**适用场景**：零配置、一条命令搞定、适合快速体验

以**管理员身份**打开 PowerShell，复制粘贴以下命令：

```powershell
# 第一步：执行引导脚本（PS 5.1+）
Set-ExecutionPolicy Bypass -Scope Process -Force
[Text.Encoding]::UTF8.GetString((New-Object Net.WebClient).DownloadData('https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/Bootstrap-ClaudeEnv.built.ps1')) | iex
```

引导完成后，在 **PowerShell 7**（`pwsh`）中运行：

```powershell
# 第二步：执行分组安装脚本（PS 7+）
Set-ExecutionPolicy Bypass -Scope Process -Force
irm 'https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/Manage-ClaudeEnv.built.ps1' | iex
```

> **说明**：
> - 第一步使用 `WebClient.DownloadData` + `UTF8.GetString` 显式 UTF-8 解码，避免 PS 5.1 `irm` 默认用系统代码页解码导致中文乱码
> - 第二步在 PS 7 中运行，`irm` 原生支持 UTF-8，无需特殊处理
> - `iex` (Invoke-Expression) 直接执行脚本
> - 执行前可以先访问 URL 查看脚本源码，确保安全
> - 分组安装将 12 个步骤分为基础环境和进阶扩展两组，更灵活

---

### 方式二：下载单文件脚本（推荐）

**适用场景**：需要离线安装、网络不稳定、想先查看脚本内容

#### 第一步：下载并运行引导脚本

从 [Releases](../../releases) 下载 `Bootstrap-ClaudeEnv.built.ps1`，以**管理员身份**打开 PowerShell，运行：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\Bootstrap-ClaudeEnv.built.ps1
```

#### 第二步：运行主安装脚本

引导完成后，下载 `Manage-ClaudeEnv.built.ps1`，在 **PowerShell 7**（`pwsh`）中运行：

```powershell
pwsh -File ".\Manage-ClaudeEnv.built.ps1"
```

按提示选择安装模式后，全程自动完成。

---

### 方式三：从源码运行（开发者模式）

**适用场景**：需要自定义修改、参与开发、调试安装器

#### 第一步：克隆仓库并运行引导脚本

```powershell
git clone https://github.com/MrNine-666/claude-code-quickstart.git
cd claude-code-quickstart
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\installer\Bootstrap-ClaudeEnv.ps1
```

引导脚本会自动完成：
- ✓ 检测 Windows 版本兼容性
- ✓ 检测并安装 winget（如需要）
- ✓ 推荐安装 Windows Terminal（可选）
- ✓ **安装 PowerShell 7**（必需）
- ✓ 配置 Git Bash UTF-8 支持

#### 第二步：运行主安装脚本

引导完成后，按照提示在 **PowerShell 7**（`pwsh`）中运行：

```powershell
pwsh -File ".\installer\Manage-ClaudeEnv.ps1"
```

按提示选择安装模式后，全程自动完成。

---

## 安装模式

> **提示**：以下命令中的脚本路径根据你的使用方式选择：
> - 构建后的单文件：`.\Manage-ClaudeEnv.built.ps1`
> - 源码模式：`.\installer\Manage-ClaudeEnv.ps1`

### 分组安装

```powershell
# 构建后的单文件版本
pwsh -File ".\Manage-ClaudeEnv.built.ps1"

# 或源码版本
pwsh -File ".\installer\Manage-ClaudeEnv.ps1"
```

将 12 个步骤分为**基础环境**和**进阶扩展**两组：
- **基础环境**：Node.js、Git、Claude Code、API Key — 一键安装，无需选择
- **进阶扩展**：ccline、cc-switch、配置优化、MCP、多模型工具 — 支持一键或多选

### 断点续传

```powershell
# 构建后的单文件版本
pwsh -File ".\Manage-ClaudeEnv.built.ps1" -Resume

# 或源码版本
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Resume
```

从上次失败或中断的步骤继续，已成功的步骤自动跳过。Manage 脚本完整支持断点续传功能。

### 查看步骤列表

```powershell
# 构建后的单文件版本
pwsh -File ".\Manage-ClaudeEnv.built.ps1" -ListSteps

# 或源码版本
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -ListSteps
```

---

## 安装内容

| # | 步骤 | 说明 | 分组 | 可选 |
|---|------|------|------|:----:|
| 01 | Node.js (fnm) | 安装 fnm 版本管理器 + Node.js LTS | 基础 | — |
| 02 | Git | 安装 Git，配置中文支持 | 基础 | — |
| 03 | Claude Code | 全局安装 `@anthropic-ai/claude-code` | 基础 | — |
| 04 | API Key 配置 | 配置 AI 供应商 API Key | 基础 | — |
| 05 | ccline | 安装 ccline 状态栏工具 | 进阶 | — |
| 06 | cc-switch | Claude Code / Codex / Gemini CLI 全方位辅助工具 | 进阶 | — |
| 07 | Claude 基础配置 | 写入语言/模型/权限/环境变量配置 | 进阶 | — |
| 08 | CLAUDE.md | 生成全局 Claude Code 工作规范文件 | 进阶 | — |
| 09 | MCP Server | 配置 MCP 插件服务器 | 进阶 | — |
| 10 | CCG 工作流 | 安装 Claude Code Generator 工作流 | 进阶 | — |
| 11 | Codex CLI | 安装 OpenAI Codex CLI（多模型协作） | 进阶 | ✓ |
| 12 | Gemini CLI | 安装 Google Gemini CLI（多模型协作） | 进阶 | ✓ |

---

## API Key 配置

安装器支持以下国内 AI 供应商，无需翻墙即可使用 Claude Code：

| 供应商 | 最新模型系列 | 模型映射（2026-02 更新） | 获取 Key |
|--------|------------|------------------------|---------|
| **智谱 GLM** | GLM-5, GLM-4.7, GLM-4-Plus | 服务端自动路由（无需配置） | [open.bigmodel.cn](https://open.bigmodel.cn) |
| **MiniMax** | M2.5, M2.1, abab6.5 | opus/sonnet/haiku → MiniMax-M2.5 | [platform.minimaxi.com](https://platform.minimaxi.com) |
| **Kimi (月之暗面)** | K2.5, K2-turbo, moonshot-v1 | opus/sonnet/haiku → kimi-k2.5 | [platform.moonshot.cn](https://platform.moonshot.cn) |
| **自定义供应商** | 自定义 | 可自定义模型映射 | 手动输入 Base URL 和 API Key |

API Key 和模型映射写入 `~/.claude/settings.json`：

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

---

## 项目结构

```
claude-code-quickstart/
├── installer/
│   ├── Bootstrap-ClaudeEnv.ps1   # PS 5.1 引导入口
│   ├── Install-ClaudeEnv.ps1     # PS 7+ 主安装入口（全量安装）
│   ├── Manage-ClaudeEnv.ps1      # PS 7+ 分组安装入口（推荐）
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
│   │   └── Bootstrap.ps1         # 步骤状态模型与调度引擎
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

安装状态保存在 `%TEMP%\ClaudeEnvInstaller\install-state.json`，使用 `-Resume` 参数继续：

```powershell
# 如果使用云端执行，需要先下载脚本到本地
Invoke-RestMethod -Uri "https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/Manage-ClaudeEnv.built.ps1" -OutFile "Manage-ClaudeEnv.built.ps1"
pwsh -File ".\Manage-ClaudeEnv.built.ps1" -Resume

# 或使用本地单文件版本
pwsh -File ".\Manage-ClaudeEnv.built.ps1" -Resume

# 或源码版本
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Resume
```

> **提示**：步骤文件和函数名采用语义化命名。旧版状态文件会自动迁移，用户无需手动操作。安装失败时使用 `-Resume` 重试失败步骤即可。

**Q：想重新配置 API Key？**

API Key 配置步骤的 `SkipIfInstalled` 为 `true`，若已检测到配置则自动跳过。使用 Manage 脚本的进阶扩展模式手动选择该步骤即可重新配置：

```powershell
# 构建后的单文件版本
pwsh -File ".\Manage-ClaudeEnv.built.ps1" -Group Advanced -Mode Select

# 或源码版本
pwsh -File ".\installer\Manage-ClaudeEnv.ps1" -Group Advanced -Mode Select
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
  - `Install-ClaudeEnv.built.ps1` - 全量安装脚本（PS 7+）
  - `Manage-ClaudeEnv.built.ps1` - 分组安装脚本（PS 7+，推荐）
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
