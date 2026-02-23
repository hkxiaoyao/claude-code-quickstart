# CLAUDE.md 配置步骤 - Claude Code 环境安装器
# 作者: 哈雷酱 (本小姐的完美文档管理！)
# 功能: 用户级 CLAUDE.md 配置文件写入 + rules/ 拆分文件管理

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"

# ============================================================
# 模板定义
# ============================================================

# CLAUDE.md 主文件模板（~80 行，确保在 token 截断限制内完整可见）
$script:ClaudeMdTemplate = @'
# Claude Code 增强配置 (CCG Enhanced)

## 一、核心原则

### 调研优先（强制）
修改代码前必须：1) 检索相关代码 2) 识别复用机会 3) 追踪调用链影响范围

### 修改前三问
1. 这是真问题还是臆想？（拒绝过度设计）
2. 有现成代码可复用吗？（优先复用）
3. 会破坏什么调用关系？（保护依赖链）

### 红线原则
- 禁止 copy-paste 重复代码；禁止破坏现有功能；禁止对错误方案妥协
- 禁止盲目执行不加思考；禁止基于假设回答（必须检索验证）
- 关键路径必须有错误处理

### 安全检查
- 禁止硬编码密钥/密码/token；不提交 .env / credentials 等敏感文件
- 用户输入在系统边界必须验证

### 代码风格
- **KISS** - 能简单就不复杂 | **DRY** - 零容忍重复，必须复用
- **保护调用链** - 修改函数签名时同步更新所有调用点
- 完成后清理：临时文件、废弃代码、未使用导入、调试日志

---

## 二、工作流原则

1. **先检索，后生成** - 生成代码前必须先调用 search_context
2. **增强需求** - 复杂任务先明确需求边界
3. **智能路由** - 根据任务类型选择 Codex/Gemini/Claude
4. **交叉验证** - 关键决策可使用双模型并行分析
5. **代码主权** - Codex/Gemini 仅负责分析、规划、审查；所有代码实现由 Claude 完成

---

## 三、任务分级

| 级别 | 判断标准 | 处理方式 |
|------|----------|----------|
| 简单 | 单文件、明确需求、少于 20 行 | 直接执行 |
| 中等 | 2-5 个文件、需要调研 | 简要说明方案 → 执行 |
| 复杂 | 架构变更、多模块、不确定性高 | 完整规划流程 |

### 复杂任务流程
1. **RESEARCH** - 调研代码，不提建议
2. **PLAN** - 列出方案，等待用户确认
3. **EXECUTE** - 严格按计划执行
4. **REVIEW** - 完成后自检

触发：用户说"进入X模式"或任务符合复杂标准时自动启用

---

## 四、交互与环境

### 何时询问用户
- 存在多个合理方案时；需求不明确或有歧义时
- 改动范围超出预期时；发现潜在风险时

### 何时直接执行
- 需求明确且方案唯一；小范围修改（少于 20 行）；用户已确认过类似操作

### 敢于说不
发现问题直接指出，不妥协于错误方案

### 环境特定（Windows / PowerShell）
- 不支持 `&&`，使用 `;` 分隔命令
- 中文路径用引号包裹
- 管道传参：`"内容" | command` 替代 heredoc

### 输出设置
- 中文响应；禁用表情符号；禁止截断输出
'@

# Rules 拆分文件模板（写入 ~/.claude/rules/ 目录，Claude Code 无条件加载）
$script:RulesTemplates = @{}

$script:RulesTemplates['ccg-multimodel.md'] = @'
# 多模型协作

## 后端任务 → Codex

```powershell
"[任务描述]" | codeagent-wrapper --backend codex - [工作目录]
```

适用：后端 logic、算法实现、数据库操作、API 开发、性能优化、调试分析

## 前端任务 → Gemini

```powershell
"[任务描述]" | codeagent-wrapper --backend gemini - [工作目录]
```

适用：UI/UX 组件、CSS 样式、响应式布局、前端交互逻辑

## 会话复用

每次调用返回 `SESSION_ID: xxx`，后续用 `resume xxx` 复用上下文：

```powershell
"[后续任务]" | codeagent-wrapper --backend <codex|gemini> resume <SESSION_ID> - [工作目录]
```

## 并行调用

使用 `run_in_background: true` 启动后台任务，用 `TaskOutput` 等待结果。
必须等所有模型返回后才能进入下一阶段。

```python
# 示例：并行启动 Codex 和 Gemini
Bash(command='"任务描述" | codeagent-wrapper --backend codex ...', run_in_background=True)
Bash(command='"任务描述" | codeagent-wrapper --backend gemini ...', run_in_background=True)

# 等待结果
TaskOutput(task_id="<TASK_ID>", block=True, timeout=600000)
```
'@

$script:RulesTemplates['ccg-tools.md'] = @'
# 工具速查与知识获取

## 知识获取（强制）

遇到不熟悉的知识，必须联网搜索，严禁猜测：

- 通用搜索：`mcp__exa__web_search_exa` / `WebSearch`
- 库文档：`mcp___upstash_context7-mcp__resolve-library-id` → `query-docs`
- 开源项目：`mcp__mcp-deepwiki__deepwiki_fetch`

## 设计图数据获取

当用户明确说根据设计图，并输入 MasterGo 链接时：

- 使用：`mcp__mastergo__mcp__getDsl`

## 工具速查表

| 场景 | 推荐工具 |
|------|----------|
| 代码语义检索 | `mcp__ace-tool__search_context` |
| 精确字符串/正则 | `Grep` |
| 文件名匹配 | `Glob` |
| 代码库探索 | `Task` + `subagent_type=Explore` |
| 技术方案规划 | `EnterPlanMode` 或 `Task` + `subagent_type=Plan` |
| 库官方文档 | `mcp___upstash_context7-mcp__query-docs` |
| 开源项目文档 | `mcp__mcp-deepwiki__deepwiki_fetch` |
| 联网搜索 | `mcp__exa__web_search_exa` / `WebSearch` |
| 快捷操作 | Skill（`/commit`、`/debug`、`/review` 等） |

**选择原则**：语义理解用 `ace-tool`，精确匹配用 `Grep`
'@

$script:RulesTemplates['ccg-workflow.md'] = @'
# 工作流增强（CCG）

## 上下文检索（生成代码前执行）

**工具**：`mcp__ace-tool__search_context`

**检索策略**：

- 使用自然语言构建语义查询（Where/What/How）
- 完整性检查：获取相关类、函数、变量的完整定义与签名
- 若上下文不足，递归检索直至信息完整

## Prompt 增强（复杂任务推荐）

**工具**：`mcp__ace-tool__enhance_prompt`

**触发**：用户使用 `-enhance` 标记，或任务模糊需要结构化

## 需求对齐

若检索后需求仍有模糊空间，输出引导性问题列表，直至需求边界清晰（无遗漏、无冗余）。
'@

# ============================================================
# 辅助函数
# ============================================================

function Get-ClaudeMdPath {
    <#
    .SYNOPSIS
    获取用户级 CLAUDE.md 路径
    #>

    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        return "$env:USERPROFILE\.claude\CLAUDE.md"
    } else {
        return "$env:HOME/.claude/CLAUDE.md"
    }
}

function Get-ClaudeRulesDir {
    <#
    .SYNOPSIS
    获取用户级 rules 目录路径
    #>

    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        return "$env:USERPROFILE\.claude\rules"
    } else {
        return "$env:HOME/.claude/rules"
    }
}

# ============================================================
# 步骤生命周期函数
# ============================================================

function Test-Step08Installed {
    <#
    .SYNOPSIS
    检测 CLAUDE.md 及 rules 文件是否已配置
    #>

    try {
        $claudeMdPath = Get-ClaudeMdPath
        if (-not (Test-Path $claudeMdPath)) {
            return $false
        }

        $content = Get-Content $claudeMdPath -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($content)) {
            return $false
        }

        # 检查主文件关键标识
        $hasHeader = $content -match "# Claude Code 增强配置"
        $hasCoreSection = $content -match "## 一、核心原则"
        $hasWorkflowSection = $content -match "## 二、工作流原则"

        if (-not ($hasHeader -and $hasCoreSection -and $hasWorkflowSection)) {
            return $false
        }

        # 检查 rules 文件存在性和内容完整性
        $rulesDir = Get-ClaudeRulesDir

        # 每个 rules 文件的关键标识（与 Verify 对齐）
        $rulesValidation = @{
            'ccg-multimodel.md' = '# 多模型协作'
            'ccg-tools.md'      = '# 工具速查与知识获取'
            'ccg-workflow.md'   = '# 工作流增强'
        }

        foreach ($fileName in $rulesValidation.Keys) {
            $rulePath = Join-Path $rulesDir $fileName

            # 检查文件存在
            if (-not (Test-Path $rulePath)) {
                return $false
            }

            # 检查文件内容标识
            $ruleContent = Get-Content $rulePath -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($ruleContent)) {
                return $false
            }

            $keyMarker = $rulesValidation[$fileName]
            if ($ruleContent -notmatch [regex]::Escape($keyMarker)) {
                return $false
            }
        }

        Write-UiSuccess "CLAUDE.md + rules/ 已配置"
        return $true
    }
    catch {
        Write-UiError "检测 CLAUDE.md 配置时出错: $($_.Exception.Message)"
        return $false
    }
}

function Install-Step08 {
    <#
    .SYNOPSIS
    安装 CLAUDE.md 配置 + rules 拆分文件
    #>

    $result = @{ Success = $false; ErrorMessage = ""; Data = @{} }

    try {
        Write-UiInfo "配置用户级 CLAUDE.md..."

        $claudeMdPath = Get-ClaudeMdPath

        # 确保 .claude 目录存在
        $claudeMdDir = Split-Path $claudeMdPath -Parent
        if (-not (Test-Path $claudeMdDir)) {
            New-Item -ItemType Directory -Path $claudeMdDir -Force | Out-Null
            Write-UiInfo "已创建目录: $claudeMdDir"
        }

        # 备份并写入 CLAUDE.md
        if (Test-Path $claudeMdPath) {
            Write-UiWarn "检测到现有 CLAUDE.md 文件"
            $backupPath = "$claudeMdPath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Copy-Item $claudeMdPath $backupPath -Force
            Write-UiInfo "已备份现有文件到: $backupPath"
        }

        Write-UiInfo "写入 CLAUDE.md 配置..."
        $writeResult = Write-FileAtomically -FilePath $claudeMdPath -Content $script:ClaudeMdTemplate

        if (-not $writeResult) {
            throw "CLAUDE.md 写入失败"
        }

        $lineCount = ($script:ClaudeMdTemplate -split "`n").Count
        Write-UiSuccess "CLAUDE.md 已写入 ($lineCount 行)"

        # 创建 rules 目录并写入拆分文件
        $rulesDir = Get-ClaudeRulesDir
        if (-not (Test-Path $rulesDir)) {
            New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
            Write-UiInfo "已创建目录: $rulesDir"
        }

        foreach ($fileName in $script:RulesTemplates.Keys) {
            $rulePath = Join-Path $rulesDir $fileName
            $ruleContent = $script:RulesTemplates[$fileName]

            # 备份已存在的 rules 文件
            if (Test-Path $rulePath) {
                $ruleBackup = "$rulePath.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                Copy-Item $rulePath $ruleBackup -Force
                Write-UiInfo "已备份: $fileName"
            }

            $ruleWriteResult = Write-FileAtomically -FilePath $rulePath -Content $ruleContent

            if (-not $ruleWriteResult) {
                throw "rules/$fileName 写入失败"
            }

            Write-UiInfo "已写入: rules/$fileName"
        }

        Write-UiSuccess "CLAUDE.md + rules/ 配置已完成"
        Write-UiInfo "配置路径: $claudeMdPath"
        Write-UiInfo "规则目录: $rulesDir"

        # 显示配置摘要
        Write-UiInfo "配置摘要:"
        Write-UiInfo "  - 主文件行数: $lineCount"
        Write-UiInfo "  - rules 文件: $($script:RulesTemplates.Count) 个"
        Write-UiInfo "  - 核心原则: 5 项（调研优先/三问/红线/安全/风格）"
        Write-UiInfo "  - 工作流原则: 5 条"
        Write-UiInfo "  - 拆分内容: 多模型协作 / 工具速查 / 工作流增强"

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiError "配置 CLAUDE.md 失败: $($result.ErrorMessage)"
    }

    return $result
}

function Verify-Step08 {
    <#
    .SYNOPSIS
    验证 CLAUDE.md 配置及 rules 文件
    #>

    $result = @{ Success = $false; ErrorMessage = "" }

    try {
        # ---- 验证 CLAUDE.md 主文件 ----
        $claudeMdPath = Get-ClaudeMdPath
        if (-not (Test-Path $claudeMdPath)) {
            throw "CLAUDE.md 文件不存在"
        }

        $content = Get-Content $claudeMdPath -Raw
        if ([string]::IsNullOrWhiteSpace($content)) {
            throw "CLAUDE.md 文件为空"
        }

        # 验证关键章节（瘦身后 4 个章节）
        $sections = @(
            "# Claude Code 增强配置",
            "## 一、核心原则",
            "## 二、工作流原则",
            "## 三、任务分级",
            "## 四、交互与环境"
        )

        $missingSection = @()
        foreach ($section in $sections) {
            if ($content -notmatch [regex]::Escape($section)) {
                $missingSection += $section
            }
        }

        if ($missingSection.Count -gt 0) {
            throw "CLAUDE.md 缺少章节: $($missingSection -join ', ')"
        }

        # 验证文件大小
        $fileSize = (Get-Item $claudeMdPath).Length
        if ($fileSize -lt 500) {
            throw "CLAUDE.md 文件过小，可能不完整"
        }

        # ---- 验证 rules 文件 ----
        $rulesDir = Get-ClaudeRulesDir

        # 每个 rules 文件的关键标识
        $rulesValidation = @{
            'ccg-multimodel.md' = '# 多模型协作'
            'ccg-tools.md'      = '# 工具速查与知识获取'
            'ccg-workflow.md'   = '# 工作流增强'
        }

        foreach ($fileName in $rulesValidation.Keys) {
            $rulePath = Join-Path $rulesDir $fileName

            if (-not (Test-Path $rulePath)) {
                throw "rules 文件不存在: $fileName"
            }

            $ruleContent = Get-Content $rulePath -Raw
            if ([string]::IsNullOrWhiteSpace($ruleContent)) {
                throw "rules 文件为空: $fileName"
            }

            $keyMarker = $rulesValidation[$fileName]
            if ($ruleContent -notmatch [regex]::Escape($keyMarker)) {
                throw "rules 文件缺少关键标识: $fileName (期望: $keyMarker)"
            }
        }

        Write-UiSuccess "CLAUDE.md + rules/ 配置验证通过"
        Write-UiInfo "  - 主文件大小: $([math]::Round($fileSize / 1024, 2)) KB"
        Write-UiInfo "  - 章节完整性: 通过"
        Write-UiInfo "  - rules 文件: $($rulesValidation.Count) 个均有效"

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiError "验证 CLAUDE.md 配置失败: $($result.ErrorMessage)"
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
