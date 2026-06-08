# Claude Code Quickstart (CCQ)

Windows 与 macOS 双平台的 Claude Code 开发环境自动化安装器。

> 目标：把「装环境」变成「跑脚本」——Windows 从 PowerShell 5.1 到 PowerShell 7，macOS 从 Homebrew / zsh / nvm 到 Claude Code，从基础依赖到 MCP/工作流，一次完成。

---

## 目录

- [为什么用 CCQ](#为什么用-ccq)
- [核心特性](#核心特性)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
  - [方式一：云端直接执行](#方式一云端直接执行推荐)
  - [方式二：下载单文件执行](#方式二下载单文件执行)
  - [方式三：从源码运行](#方式三从源码运行开发者)
- [安装内容（13 步 + Skills 管理）](#安装内容13-步--skills-管理)
- [Manage 管理脚本](#manage-管理脚本)
- [第三方供应商](#第三方供应商)
- [MCP Server](#mcp-server)
- [项目结构](#项目结构)
- [常见问题](#常见问题)
- [License](#license)
- [友情链接](#友情链接)

---

## 为什么用 CCQ

搭 Claude Code 环境，经常会遇到这些问题：

- Windows PowerShell 版本和编码问题
- macOS Homebrew / zsh / nvm 初始化顺序问题
- Node.js / npm / Git / CLI 工具安装顺序复杂
- 第三方供应商配置分散
- MCP Server 凭据重复录入
- 组件升级后配置漂移

CCQ 通过 Windows 双阶段脚本、macOS 原生入口与实时检测机制，把这些问题统一收敛到一个安装/管理入口。

---

## 核心特性

- **双平台入口**：Windows 使用 PS 5.1 引导 + PS 7 安装/管理，macOS 使用 `curl ... | bash` 自动切换 zsh
- **共享契约**：`installer/contracts/` 统一 StepId、Provider、MCP、ClaudeConfig、构建清单、Skills catalogue 与 UI 文案语义
- **实时检测**：每次运行都检测当前状态，已安装组件自动跳过
- **分组安装**：基础环境（必装）+ 进阶扩展（可选/按需）
- **统一面板入口**：`ccq` 可选择安装面板或管理面板；管理面板提供更新、供应商、MCP、Skills 管理
- **供应商 Profile 化**：供应商配置持久化到 `~/.claude/providers/`
- **MCP 凭据 Vault**：凭据持久化到 `~/.ccq/mcp-meta.json`
- **更新安全机制**：更新前自动快照备份，支持失败后回滚

---

## 系统要求

| 项目 | Windows | macOS |
|---|---|---|
| 操作系统 | Windows 10 1903 (18362)+ / Windows 11 | macOS 12 Monterey 或更新版本 |
| Shell / 运行时 | PowerShell 5.1 可启动，引导脚本会自动准备 PS 7 | `/bin/zsh`，云端入口兼容 `curl ... | bash` |
| 包管理器 | winget | Homebrew |
| Node.js | 安装脚本自动准备 Node.js LTS | 通过 nvm 安装 Node.js LTS |
| 权限 | 管理员权限（建议） | 普通用户即可；Homebrew 安装可能需要用户确认 |
| 网络 | 可访问 GitHub、npm registry | 可访问 GitHub、npm registry、Homebrew 源 |

---

## 快速开始

### 方式一：云端直接执行（推荐）

#### Windows

##### 1) 引导脚本（PS 5.1+，管理员）

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm 'https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/bootstrap.ps1' | iex
```

##### 2) 安装脚本（PS 7+）

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm 'https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/install.ps1' | iex
```

##### 3) 管理脚本（PS 7+）

新增快捷指令入口（历史安装用户需重新执行一次安装脚本的基础环境）：

```powershell
ccq
```

直接远程运行管理入口：

```powershell
irm 'https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/manage.ps1' | iex
```

#### macOS

首次安装入口（macOS 12+）：

```sh
curl -fsSL "https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/install.sh" | bash
```

安装完成后，新开 zsh 终端或执行 `source ~/.zshrc`，使用快捷面板：

```sh
ccq
```

也可直接运行管理入口：

```sh
curl -fsSL "https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/manage.sh" | bash
```

---

### 方式二：下载单文件执行

从 [Releases](../../releases) 下载：

Windows：

- `bootstrap.ps1`
- `install.ps1`
- `manage.ps1`

macOS：

- `install.sh`
- `manage.sh`

Windows 执行示例：

```powershell
# 引导（PS 5.1+，管理员）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\bootstrap.ps1

# 安装（PS 7+）
.\install.ps1

# 管理（PS 7+）
.\manage.ps1
```

macOS 执行示例：

```sh
bash ./install.sh
bash ./manage.sh
```

---

### 方式三：从源码运行（开发者）

Windows：

```powershell
git clone https://github.com/MrNine-666/claude-code-quickstart.git
cd claude-code-quickstart

# 引导（PS 5.1+）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\installer\windows\Bootstrap.ps1

# 安装（PS 7+）
.\installer\windows\Install.ps1

# 管理（PS 7+）
.\installer\windows\Manage.ps1
```

macOS：

```sh
git clone https://github.com/MrNine-666/claude-code-quickstart.git
cd claude-code-quickstart

# 安装
zsh installer/macos/Install.zsh

# 管理
zsh installer/macos/Manage.zsh
```

模拟 `irm | iex`（可传参，如 `-OutputMode Developer` 全量输出）：

```powershell
pwsh -File installer/build.ps1
& ([scriptblock]::Create((Get-Content "dist/install.ps1" -Raw))) -OutputMode Developer
```

模拟 macOS 构建产物入口：

```sh
sh installer/build.sh
bash dist/install.sh --list-steps
bash dist/manage.sh --action Update --list-updates
```

---

## 安装内容（13 步 + Skills 管理）

### 基础环境（必装）

1. Node.js
2. Git
3. Claude Code
4. 第三方供应商配置

### 进阶扩展（按需）

5. CCometixLine
6. Claude 基础配置
7. CLAUDE.md 配置
8. MCP Server 配置
9. CCG 工作流
10. OpenSpec CLI
11. cc-switch（可选）
12. Codex CLI（可选）
13. Antigravity CLI（可选）

Skills 不再出现在安装面板或 Advanced 选择流程中，也不参与统一 Update 更新管理。需要安装、更新或卸载 Skills 时，请进入 Manage → Skills 管理；若 Windows symlink 权限受限，可在 Skills 管理的安装流程中交互启用 copy 模式：

```powershell
pwsh -File installer/windows/Manage.ps1 -Action Skills
```

macOS 进阶可选工具说明：

- cc-switch：通过 `brew install --cask cc-switch` 安装，`brew upgrade --cask cc-switch` 更新。
- Codex CLI：通过 npm 全局安装并验证 `codex` 命令。
- Antigravity CLI：通过官方 `https://antigravity.google/cli/install.sh` 安装 `agy` 到 `~/.local/bin`。

---

## Manage 管理脚本

Windows 使用 `installer/windows/Manage.ps1` 或远程 `manage.ps1`，macOS 使用 `installer/macos/Manage.zsh` 或远程 `manage.sh`。两端都提供统一管理入口：

### 1) 更新管理（Update）

- 检测可更新组件（不包含 Skills）
- 支持交互多选更新
- 更新前自动快照备份
- 指纹预检（模板未变更自动跳过）

### 2) 供应商管理（Provider）

- 供应商 Profile 的新增 / 编辑 / 删除 / 切换
- 支持从 settings.json 同步历史配置

### 3) MCP 管理（Mcp）

- 查看状态（已启用 / 已禁用 / 未安装）
- 启用 / 禁用 / 删除
- 凭据通过 vault 持久化

### 4) Skills 管理（Skills）

- 安装 / 更新 / 卸载 Claude Code 全局 Skills
- 安装入口先单选 source；集合类 source 可继续多选子 Skills
- 与安装面板和统一 Update 解耦，避免首次安装或常规更新时自动变更 Skills

---

## 第三方供应商

支持内置供应商：

- 智谱 GLM（zhipu，默认 GLM-5.1）
- MiniMax（minimax，默认 MiniMax-M3）
- Kimi Code（moonshot，需 `sk-kimi-` 前缀 Key）
- DeepSeek（deepseek）
- 阿里云百炼（bailian，默认 `qwen3.7-plus`）
- 自定义供应商（custom）

配置会写入 `~/.claude/settings.json`（`env`，包含供应商认证/Base URL、可选模型环境键与供应商受管额外 env），并将 Profile 保存到 `~/.claude/providers/`。

---

## MCP Server

当前内置 MCP：

- Context7
- DeepWiki
- Tavily
- Playwright
- Exa Search
- ACE Tool
- MasterGo
- Figma
- Chrome DevTools

> 不同 MCP 的凭据类型不同（none / single-key / args-token / url-embedded 等），安装时会按需提示。

---

## 项目结构

```text
claude-code-quickstart/
├── dist/                              # 默认构建输出：bootstrap.ps1/install.ps1/manage.ps1/install.sh/manage.sh
├── installer/
│   ├── build.ps1                      # Windows / GitHub Actions 构建入口
│   ├── build.sh                       # macOS / Unix 本机构建入口
│   ├── contracts/                     # 跨平台业务契约
│   ├── windows/
│   │   ├── Bootstrap.ps1    # Windows PS 5.1 引导入口
│   │   ├── Install.ps1      # Windows PS 7+ 安装入口
│   │   ├── Manage.ps1       # Windows PS 7+ 管理入口
│   │   ├── core/                      # Windows PowerShell runtime core
│   │   └── steps/                     # Windows 步骤实现
│   └── macos/
│       ├── Install.zsh      # macOS 安装入口
│       ├── Manage.zsh       # macOS 管理入口
│       ├── core/                      # macOS zsh runtime core
│       └── steps/                     # macOS 步骤实现
└── test-syntax.ps1
```

---

## 常见问题

### Q1：安装失败怎么办？

直接重新运行安装脚本即可。CCQ 会实时检测并跳过已安装项。

### Q2：提示找不到 `ccq` 怎么办？

按你的场景处理：

1. **Windows 历史安装用户**
   - 重新执行一次安装脚本的基础环境，让 `ccq` 写入 `$PROFILE`

2. **Windows 刚刚执行完 install**
   - 先新开一个终端再试：

   ```powershell
   ccq
   ```

   - 如果当前终端也想立即可用，可执行：

   ```powershell
   . $PROFILE
   ccq
   ```

3. **macOS 用户**
   - 新开 zsh 终端，或执行：

   ```sh
   source ~/.zshrc
   ccq
   ```

---

## License

[MIT](LICENSE)

---

## 友情链接

- [LINUX DO](https://linux.do/)

