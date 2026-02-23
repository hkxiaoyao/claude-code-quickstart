# claude-code-quickstart — AI 上下文索引

> 生成时间：2026-02-20 15:24:29 | 覆盖率：92% (23/25 文件)

Windows 10/11 平台的 **Claude Code 开发环境自动化安装器**。双阶段 PowerShell 架构，PS 5.1 引导 + PS 7 主安装，12 步依赖链，支持断点续传。

---

## 架构速览

```
claude-code-quickstart/
├── installer/
│   ├── Bootstrap-ClaudeEnv.ps1   # PS 5.1 引导入口 → 检测/安装 PS7
│   ├── Install-ClaudeEnv.ps1     # PS 7+ 主安装入口（-Resume/-OneClick/-Staged）
│   ├── Manage-ClaudeEnv.ps1      # PS 7+ 分组安装入口（基础环境/进阶扩展）
│   ├── build/                    # 构建工具目录
│   │   ├── Build-SingleFile.ps1  # 单文件打包构建脚本
│   │   └── dist/                 # 构建产物输出（gitignored，由 CI 自动构建）
│   ├── core/                     # 6 个基础功能库（Ui/Process/Profile/Admin/Net/Bootstrap）
│   └── steps/                    # 12 个安装步骤模块（Step01~Step12）
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
    C --> C4[Admin.ps1] & C5[Net.ps1] & C6[Bootstrap.ps1]
    D --> D1[Step01~04<br/>基础环境]
    D --> D2[Step05~10<br/>进阶扩展]
    D --> D3[Step11~12<br/>可选多模型工具]
```

---

## 步骤依赖图

```
Step01.NodeFnm ──────────────────────────────────────── Step11.CodexCli [可选]
├── Step03.ClaudeCode                                   Step12.GeminiCli [可选]
│   ├── Step04.ApiKey
│   ├── Step05.Ccline
│   ├── Step06.CcSwitch
│   └── Step09.Mcp
└── Step10.CcgWorkflow
Step02.Git
Step07.ClaudeConfig (依赖 Step03) ── Step08.ClaudeMd
```

---

## 模块导航

| 模块 | 详细文档 | 职责 |
|------|---------|------|
| installer/ | [installer/CLAUDE.md](installer/CLAUDE.md) | 双入口脚本、安装模式、步骤注册表 |
| installer/core/ | [installer/core/CLAUDE.md](installer/core/CLAUDE.md) | 6 个核心基础库 |
| installer/steps/ | [installer/steps/CLAUDE.md](installer/steps/CLAUDE.md) | 12 个安装步骤模块 |

---

## 关键约束（HC）速查

| 约束 | 内容 |
|------|------|
| **HC-12** | Step04 管 API 连接：`env.ANTHROPIC_AUTH_TOKEN` + `env.ANTHROPIC_BASE_URL` + `modelMapping`；Step07 管常用配置：语言、模型、权限、超时、归因等（仅补缺失，不覆盖）；供应商支持 智谱GLM / MiniMax / Kimi / 自定义 |
| **HC-4** | `$PROFILE` 编辑使用标记块 `# >>> Claude Code Quickstart >>>` / `# <<< Claude Code Quickstart <<<` |
| **HC-3** | 状态文件：`%TEMP%\ClaudeEnvInstaller\install-state.json` |
| **SC-3** | 状态指示器：`[PASS]` / `[FAIL]` / `[SKIP]` |
| **SC-5** | 错误展示：友好信息 + 按 `D` 展开技术详情 |

---

## 关键文件路径

```
~/.claude/settings.json     # Claude Code 主配置（API Key + env + 权限）
~/.claude.json              # Claude Code 初始化标记（hasCompletedOnboarding）
~/.claude/CLAUDE.md         # 全局 Claude 工作规范（Step08 写入）
$PROFILE                    # PowerShell 配置文件（ccline/cc-switch PATH）
%TEMP%\ClaudeEnvInstaller\  # 安装状态 + 备份目录
```

---

## 快速调试

```powershell
# 验证全部文件语法
pwsh -File test-syntax.ps1

# 断点续传安装
pwsh -File installer/Install-ClaudeEnv.ps1 -Resume

# 查看步骤列表
pwsh -File installer/Install-ClaudeEnv.ps1 -ListSteps
```
