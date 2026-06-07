# installer/ — 安装器入口层

> 面包屑：[根目录](../CLAUDE.md) › installer/
> 生成时间：2026-06-07 (Windows canonical 目录 + 双本机构建入口)

---

## 文件职责

| 路径/文件 | 平台/运行时 | 职责 |
|------|---------|------|
| `windows/Bootstrap-ClaudeEnv.ps1` | Windows / PS 5.1+ | 前置检测：Windows 版本 → winget → Windows Terminal → PS 7 安装 → Git Bash UTF-8 |
| `windows/Install-ClaudeEnv.ps1` | Windows / PS 7.0+ | Windows 安装入口：Basic / Advanced 分组安装，动态加载 `windows/core/` 与 `windows/steps/` |
| `windows/Manage-ClaudeEnv.ps1` | Windows / PS 7.0+ | Windows 管理入口：Update / Provider / MCP / Skills |
| `windows/core/` | Windows / PowerShell | Windows runtime core：UI、Process、Profile、Registry、Bootstrap、MCP、Provider |
| `windows/steps/` | Windows / PowerShell | Windows 14 个步骤实现，StepId 与 macOS 保持一致 |
| `contracts/` | JSON 契约 | 跨平台 StepId、分组、依赖、Provider、MCP、ClaudeConfig、模板与构建清单 |
| `macos/Install-ClaudeEnv.zsh` | macOS / bash→zsh | macOS 安装入口：合并 Bootstrap 前置检测，支持 `curl ... | bash` 后自动切换 `/bin/zsh` |
| `macos/Manage-ClaudeEnv.zsh` | macOS / zsh | macOS 管理入口：Update / Provider / MCP / Skills |
| `build.ps1` | PowerShell 7+ | Windows / GitHub Actions 构建入口，输出 `dist/` 下五个短 artifact |
| `build.sh` | POSIX sh + node | macOS / Unix 本机构建入口，支持无 `pwsh` 的结构检查 |

旧源码入口 `installer/Bootstrap-ClaudeEnv.ps1`、`installer/Install-ClaudeEnv.ps1`、`installer/Manage-ClaudeEnv.ps1` 和旧构建入口 `installer/build/Build-SingleFile.ps1` 不作为支持路径保留。

---

## 云端短 artifact

```text
Windows
├── bootstrap.ps1  # PS 5.1+ 引导入口
├── install.ps1    # PS 7+ 安装入口
└── manage.ps1     # PS 7+ 管理入口

macOS
├── install.sh     # bash→zsh 安装入口
└── manage.sh      # bash→zsh 管理入口
```

首次安装命令：

```powershell
irm https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/bootstrap.ps1 | iex
```

```sh
curl -fsSL https://github.com/MrNine-666/claude-code-quickstart/releases/latest/download/install.sh | bash
```

安装后的 `ccq` Profile 快捷函数仍作为面板入口，但内部远程调用 `install.*` / `manage.*`，不再引用长 `.built.*` 文件名或 `ccq-*` artifact。

---

## Windows 源码调试命令

```powershell
# 验证全部 PowerShell 文件语法
pwsh -File test-syntax.ps1

# 引导 / 安装 / 管理
powershell -File installer/windows/Bootstrap-ClaudeEnv.ps1
pwsh -File installer/windows/Install-ClaudeEnv.ps1
pwsh -File installer/windows/Manage-ClaudeEnv.ps1

# 查看步骤列表与可更新项
pwsh -File installer/windows/Install-ClaudeEnv.ps1 -ListSteps
pwsh -File installer/windows/Manage-ClaudeEnv.ps1 -Action Update -ListUpdates
```

---

## macOS 源码调试命令

```sh
# 安装 / 管理
zsh installer/macos/Install-ClaudeEnv.zsh
zsh installer/macos/Manage-ClaudeEnv.zsh

# 查看步骤列表与可更新项
zsh installer/macos/Install-ClaudeEnv.zsh --list-steps
zsh installer/macos/Manage-ClaudeEnv.zsh --action Update --list-updates
```

macOS 硬约束：最低 macOS 12+；使用 Homebrew + nvm；Profile 写入 `~/.zprofile` / `~/.zshrc`；禁止调用 winget、注册表、MSI/EXE、Windows Terminal 或 Windows `$PROFILE`。

---

## 构建命令

```powershell
# Windows / CI 主构建入口
pwsh -File installer/build.ps1 -Platform All
pwsh -File installer/build.ps1 -Platform Windows
pwsh -File installer/build.ps1 -Platform MacOS
```

```sh
# macOS / Unix 本机构建入口
sh installer/build.sh --platform all
sh installer/build.sh --platform windows
sh installer/build.sh --platform macos
sh installer/build.sh --check
```

默认输出目录为 repo 根目录 `dist/`，产物集合必须仅包含：`bootstrap.ps1`、`install.ps1`、`manage.ps1`、`install.sh`、`manage.sh`。

---

## 加载边界

- Windows core 加载顺序：`Ui.ps1` → `Process.ps1` → `Profile.ps1` → `Admin.ps1` → `Net.ps1` → `Registry.ps1` → `Bootstrap.ps1` → `McpManager.ps1` → `Provider.ps1`。
- Windows steps 由 `Get-StepFiles` 从 `installer/contracts/steps.json` 生成，路径必须是 `windows/steps/*.ps1`。
- macOS steps 使用 `MacOSStepFile`，路径必须是 `macos/steps/*.zsh`。
- Provider / MCP / ClaudeConfig 优先读取 `installer/contracts/*.json`，内联 fallback 只用于 release artifact 或 contracts 不可用场景，并由 `installer/contracts/Test-Contracts.ps1` 校验一致性。
