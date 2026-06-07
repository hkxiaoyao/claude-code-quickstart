# installer/macos

macOS 原生安装与管理实现目录。该目录使用 zsh + Homebrew + nvm 提供与 Windows 安装器等价的 Claude Code 环境安装、管理和更新体验。

---

## 入口

| 文件 | 职责 |
|------|------|
| `Install-ClaudeEnv.zsh` | macOS 安装入口，合并 Bootstrap 前置检测，支持 Basic / Advanced 分组和 `ccq` 快捷函数注册 |
| `Manage-ClaudeEnv.zsh` | macOS 管理入口，提供 Update / Provider / MCP / Skills 四类管理能力 |
| `core/*.zsh` | macOS runtime core：UI、命令执行、Profile、平台检测、Homebrew、JSON、Registry、生命周期 |
| `steps/*.zsh` | macOS 14 个步骤实现，StepId 与 Windows 保持一致 |

云端首次安装入口：

```sh
curl -fsSL "https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/install.sh" | bash
```

`curl ... | bash` 入口只负责兼容常见远程执行形态；脚本主体会自动切换到 `/bin/zsh`。

---

## 关键约束

- 最低系统版本：macOS 12+。
- 包管理器：Homebrew。
- Node.js：通过 nvm 安装 LTS。
- Profile 写入：
  - Homebrew shellenv 写入 `~/.zprofile`。
  - nvm 初始化与 `ccq` 快捷函数写入 `~/.zshrc`。
  - 所有写入必须使用 `# >>> Claude Code Quickstart >>>` 托管块。
- 配置 schema 与 Windows 共享：`~/.claude/settings.json`、`~/.claude.json`、`~/.claude/providers/`、`~/.ccq/mcp-meta.json`。
- 禁止调用 Windows 专属机制：winget、注册表、MSI/EXE、Windows Terminal、Windows `$PROFILE`。
- 可选工具无自动路径或失败时返回 `ManualRequired` / `Unsupported`，不得计入 Success。

---

## 调试命令

```sh
# 查看步骤列表
zsh installer/macos/Install-ClaudeEnv.zsh --list-steps

# 安装基础环境
zsh installer/macos/Install-ClaudeEnv.zsh --group Basic

# 一键安装进阶必选组件
zsh installer/macos/Install-ClaudeEnv.zsh --group Advanced --mode OneClick

# 选择安装进阶组件
zsh installer/macos/Install-ClaudeEnv.zsh --group Advanced --mode Select

# 查看可更新组件
zsh installer/macos/Manage-ClaudeEnv.zsh --action Update --list-updates

# 管理供应商 / MCP / Skills
zsh installer/macos/Manage-ClaudeEnv.zsh --action Provider
zsh installer/macos/Manage-ClaudeEnv.zsh --action Mcp
zsh installer/macos/Manage-ClaudeEnv.zsh --action Skills
```

构建 macOS 单文件产物：

```sh
sh installer/build.sh --platform macos
```

也可通过 PowerShell 构建入口生成：

```powershell
pwsh -File installer/build.ps1 -Platform MacOS
```

生成产物：

- `dist/install.sh`
- `dist/manage.sh`
