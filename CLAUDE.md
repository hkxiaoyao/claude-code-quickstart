# claude-code-quickstart — AI 上下文索引

> 生成时间：2026-02-23 | 覆盖率：92% (24/26 文件)

Windows 10/11 平台的 **Claude Code 开发环境自动化安装器**。双阶段 PowerShell 架构，PS 5.1 引导 + PS 7 主安装，12 步依赖链，支持断点续传。

---

## 架构速览

```
claude-code-quickstart/
├── installer/
│   ├── Bootstrap-ClaudeEnv.ps1   # PS 5.1 引导入口 → 检测/安装 PS7
│   ├── Install-ClaudeEnv.ps1     # PS 7+ 主安装入口（维护中）
│   ├── Manage-ClaudeEnv.ps1      # PS 7+ 分组安装入口（基础环境/进阶扩展）
│   ├── build/                    # 构建工具目录
│   │   ├── Build-SingleFile.ps1  # 单文件打包构建脚本
│   │   └── dist/                 # 构建产物输出（gitignored，由 CI 自动构建）
│   ├── core/                     # 7 个基础功能库（Ui/Process/Profile/Admin/Net/Registry/Bootstrap）
│   └── steps/                    # 12 个安装步骤模块（语义化命名）
└── test-syntax.ps1               # PS7 全量语法校验工具
```

```mermaid
graph TD
    A[Bootstrap-ClaudeEnv.ps1<br/>PS 5.1] -->|安装 PS7 后引导| B[Install-ClaudeEnv.ps1<br/>PS 7+]
    A -->|安装 PS7 后引导| M[Manage-ClaudeEnv.ps1<br/>PS 7+ 分组安装]
    B --> C[core/]
    B --> D[steps/]
    M --> C
    M --> D
    C --> C1[Ui.ps1] & C2[Process.ps1] & C3[Profile.ps1]
    C --> C4[Admin.ps1] & C5[Net.ps1] & C6[Registry.ps1] & C7[Bootstrap.ps1]
    D --> D1[NodeFnm~ApiKey<br/>基础环境]
    D --> D2[Ccline~CcgWorkflow<br/>进阶扩展]
    D --> D3[CodexCli/GeminiCli<br/>可选多模型工具]
```

---

## 步骤依赖图

```
NodeFnm ──────────────────────────────────────── CodexCli [可选]
├── ClaudeCode                                   GeminiCli [可选]
│   ├── ApiKey
│   ├── Ccline
│   ├── CcSwitch
│   └── Mcp
└── CcgWorkflow
Git
ClaudeConfig (依赖 ClaudeCode)
ClaudeMd (无依赖)
```

---

## 模块导航

| 模块 | 详细文档 | 职责 |
|------|---------|------|
| installer/ | [installer/CLAUDE.md](installer/CLAUDE.md) | 双入口脚本、安装模式、步骤注册表 |
| installer/core/ | [installer/core/CLAUDE.md](installer/core/CLAUDE.md) | 7 个核心基础库（含 Registry） |
| installer/steps/ | [installer/steps/CLAUDE.md](installer/steps/CLAUDE.md) | 12 个安装步骤模块 |

---

## 关键约束（HC）速查

| 约束 | 内容 |
|------|------|
| **HC-12** | ApiKey 管 API 连接：`env.ANTHROPIC_AUTH_TOKEN` + `env.ANTHROPIC_BASE_URL` + `modelMapping`；ClaudeConfig 管常用配置：语言、模型、权限、超时、归因等（仅补缺失，不覆盖）；供应商支持 智谱GLM / MiniMax / Kimi / 自定义 |
| **HC-4** | `$PROFILE` 编辑使用标记块 `# >>> Claude Code Quickstart >>>` / `# <<< Claude Code Quickstart <<<` |
| **HC-3** | 状态文件：`%TEMP%\ClaudeEnvInstaller\install-state.json`（支持旧 StepId 自动迁移） |
| **SC-3** | 状态指示器：`[PASS]` / `[FAIL]` / `[SKIP]` |
| **SC-5** | 错误展示：友好信息 + 按 `D` 展开技术详情 |

---

## 关键文件路径

```
~/.claude/settings.json     # Claude Code 主配置（API Key + env + 权限）
~/.claude.json              # Claude Code 初始化标记（hasCompletedOnboarding）
~/.claude/CLAUDE.md         # 全局 Claude 工作规范（ClaudeMd 写入）
$PROFILE                    # PowerShell 配置文件（ccline PATH）
%TEMP%\ClaudeEnvInstaller\  # 安装状态 + 备份目录
```

---

## 快速调试

```powershell
# 验证全部文件语法
pwsh -File test-syntax.ps1

# 断点续传安装
pwsh -File installer/Manage-ClaudeEnv.ps1 -Resume

# 查看步骤列表
pwsh -File installer/Manage-ClaudeEnv.ps1 -ListSteps
```
