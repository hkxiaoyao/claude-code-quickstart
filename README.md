# Claude Code Quickstart

> Windows 10/11 平台的 Claude Code 开发环境**自动化安装器**

一键完成从零到 Claude Code 的全套环境配置：Node.js、Git、Claude Code CLI、多 AI 供应商 API Key 配置、MCP 插件、CCG 工作流等 13 个步骤，**全程自动化，支持断点续传**。

---

## 特性

- **双阶段架构**：PS 5.1 引导脚本 → PS 7 主安装脚本，兼容未升级 PowerShell 的系统
- **单文件分发**：支持构建为独立可执行的单文件脚本，无需携带整个源码目录
- **依赖自动排序**：步骤按拓扑依赖顺序执行，无需手动关心安装顺序
- **断点续传**：安装中途失败或中断后，使用 `-Resume` 从断点继续，无需重头再来
- **两种安装模式**：一键安装全部组件 / 分阶段手动选择需要的组件
- **国内 AI 供应商适配**：支持智谱 GLM、MiniMax、Kimi（月之暗面），开箱即用
- **完整回滚机制**：每个步骤安装失败后自动尝试回滚，保持系统干净

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

### 方式一：使用构建后的单文件脚本（推荐）

**适用场景**：快速分发、无需 Git 克隆、单文件即可运行

#### 第一步：下载并运行引导脚本

从 [Releases](../../releases) 下载 `Bootstrap-ClaudeEnv.built.ps1`，以**管理员身份**打开 PowerShell，运行：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\Bootstrap-ClaudeEnv.built.ps1
```

#### 第二步：运行主安装脚本

引导完成后，下载 `Install-ClaudeEnv.built.ps1`，在 **PowerShell 7**（`pwsh`）中运行：

```powershell
pwsh -File ".\Install-ClaudeEnv.built.ps1"
```

按提示选择安装模式后，全程自动完成。

---

### 方式二：从源码运行（开发者模式）

**适用场景**：需要自定义修改、参与开发、调试安装器

#### 第一步：克隆仓库并运行引导脚本

```powershell
git clone https://github.com/your-repo/claude-code-quickstart.git
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
pwsh -File ".\installer\Install-ClaudeEnv.ps1"
```

按提示选择安装模式后，全程自动完成。

---

## 安装模式

> **提示**：以下命令中的脚本路径根据你的使用方式选择：
> - 构建后的单文件：`.\Install-ClaudeEnv.built.ps1`
> - 源码模式：`.\installer\Install-ClaudeEnv.ps1`

### 一键安装（推荐）

```powershell
# 构建后的单文件版本
pwsh -File ".\Install-ClaudeEnv.built.ps1" -OneClick

# 或源码版本
pwsh -File ".\installer\Install-ClaudeEnv.ps1" -OneClick
```

自动按依赖顺序安装全部 13 个步骤（含可选的 Codex CLI 和 Gemini CLI）。

### 分阶段安装

```powershell
# 构建后的单文件版本
pwsh -File ".\Install-ClaudeEnv.built.ps1" -Staged

# 或源码版本
pwsh -File ".\installer\Install-ClaudeEnv.ps1" -Staged
```

弹出多选菜单，用 `↑↓` 导航、`空格` 选择/取消、`Enter` 确认。必选步骤默认勾选，可选步骤默认不勾选。

### 断点续传

```powershell
# 构建后的单文件版本
pwsh -File ".\Install-ClaudeEnv.built.ps1" -Resume

# 或源码版本
pwsh -File ".\installer\Install-ClaudeEnv.ps1" -Resume
```

从上次失败或中断的步骤继续，已成功的步骤自动跳过。

### 查看步骤列表

```powershell
# 构建后的单文件版本
pwsh -File ".\Install-ClaudeEnv.built.ps1" -ListSteps

# 或源码版本
pwsh -File ".\installer\Install-ClaudeEnv.ps1" -ListSteps
```

---

## 安装内容

| # | 步骤 | 说明 | 可选 |
|---|------|------|:----:|
| 01 | 代理配置检测 | 评估网络环境，识别代理配置 | — |
| 02 | Node.js (fnm) | 安装 fnm 版本管理器 + Node.js LTS | — |
| 03 | Git | 安装 Git，配置中文支持 | — |
| 04 | Claude Code | 全局安装 `@anthropic-ai/claude-code` | — |
| 05 | ccline | 安装 ccline 状态栏工具 | — |
| 06 | cc-switch | 安装 cc-switch 版本切换工具 | — |
| 07 | API Key 配置 | 配置 AI 供应商 API Key | — |
| 08 | Claude 基础配置 | 写入语言/模型/权限/状态栏配置 | — |
| 09 | CLAUDE.md | 生成全局 Claude Code 工作规范文件 | — |
| 10 | MCP Server | 配置 MCP 插件服务器 | — |
| 11 | CCG 工作流 | 安装 Claude Code Generator 工作流 | — |
| 12 | Codex CLI | 安装 OpenAI Codex CLI（多模型协作） | ✓ |
| 13 | Gemini CLI | 安装 Google Gemini CLI（多模型协作） | ✓ |

---

## API Key 配置

安装器支持以下国内 AI 供应商，无需翻墙即可使用 Claude Code：

| 供应商 | 模型系列 | 获取 Key |
|--------|---------|---------|
| **智谱 GLM** | GLM-4 系列 | [open.bigmodel.cn](https://open.bigmodel.cn) |
| **MiniMax** | abab6.5 系列 | [platform.minimaxi.com](https://platform.minimaxi.com) |
| **Kimi (月之暗面)** | moonshot-v1 系列 | [platform.moonshot.cn](https://platform.moonshot.cn) |

API Key 写入 `~/.claude/settings.json`：

```json
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "your-api-key",
    "ANTHROPIC_BASE_URL": "https://api.xxx.com/v1/"
  }
}
```

---

## 项目结构

```
claude-code-quickstart/
├── installer/
│   ├── Bootstrap-ClaudeEnv.ps1   # PS 5.1 引导入口
│   ├── Install-ClaudeEnv.ps1     # PS 7+ 主安装入口
│   ├── build/                    # 构建工具目录
│   │   ├── Build-SingleFile.ps1  # 单文件打包构建脚本
│   │   └── dist/                 # 构建产物输出目录
│   │       ├── Bootstrap-ClaudeEnv.built.ps1   # 引导脚本单文件版本
│   │       └── Install-ClaudeEnv.built.ps1     # 主安装脚本单文件版本
│   ├── core/                     # 核心功能模块
│   │   ├── Ui.ps1                # TUI 组件（彩色输出、菜单、进度条）
│   │   ├── Process.ps1           # 外部命令执行封装
│   │   ├── Profile.ps1           # $PROFILE 安全编辑
│   │   ├── Admin.ps1             # 管理员权限管理
│   │   ├── Net.ps1               # 网络检测与代理配置
│   │   └── Bootstrap.ps1         # 步骤状态模型与调度引擎
│   └── steps/                    # 安装步骤模块
│       ├── Step01.Proxy.ps1
│       ├── Step02.NodeFnm.ps1
│       ├── ...
│       └── Step13.GeminiCli.ps1
└── test-syntax.ps1               # 语法全量校验工具
```

---

## 安装后使用

```powershell
# 启动 Claude Code
claude

# 查看帮助
claude --help

# 切换 Claude Code 版本（需已安装 cc-switch）
cc-switch

# 使用 Codex CLI（需已安装）
codex --help

# 使用 Gemini CLI（需已安装）
gemini --help
```

---

## 常见问题

**Q：安装中途失败了怎么办？**

安装状态保存在 `%TEMP%\ClaudeEnvInstaller\install-state.json`，使用 `-Resume` 参数继续：

```powershell
# 构建后的单文件版本
pwsh -File ".\Install-ClaudeEnv.built.ps1" -Resume

# 或源码版本
pwsh -File ".\installer\Install-ClaudeEnv.ps1" -Resume
```

**Q：想重新配置 API Key？**

Step07（API Key 配置）的 `SkipIfInstalled` 为 `false`，每次安装都会重新运行。直接 `-Staged` 模式只勾选 Step07 即可：

```powershell
# 构建后的单文件版本
pwsh -File ".\Install-ClaudeEnv.built.ps1" -Staged

# 或源码版本
pwsh -File ".\installer\Install-ClaudeEnv.ps1" -Staged
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
- ✓ 生成两个单文件脚本到 `installer/build/dist/` 目录：
  - `Bootstrap-ClaudeEnv.built.ps1` - 引导脚本（PS 5.1+）
  - `Install-ClaudeEnv.built.ps1` - 主安装脚本（PS 7+）
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
