# CLAUDE.md 配置步骤 - CCQ
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
# 命名约定：统一 ccq- 前缀（CCQ = Claude Code Quickstart），与用户自定义 rules 隔离
$script:RulesTemplates = @{}

$script:RulesTemplates['ccq-multimodel.md'] = @'
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

$script:RulesTemplates['ccq-tools.md'] = @'
# 工具速查与知识获取

## 知识获取（强制）

遇到不熟悉的知识，必须联网搜索，严禁猜测：

- 通用搜索：`mcp__exa__web_search_exa`（首选）→ `mcp__tavily__tavily_search`（次选）→ `WebSearch`（兜底）
  - 深度研究场景：`mcp__tavily__tavily_research`
  - exa 不可用时自动回退到 tavily
- 库文档：`mcp__context7__resolve-library-id` → `mcp__context7__query-docs`
- 开源项目：`mcp__deepwiki__ask_question` / `mcp__deepwiki__read_wiki_structure` / `mcp__deepwiki__read_wiki_contents`

## 工具速查表

### 代码检索

| 场景 | 推荐工具 |
|------|----------|
| 代码语义检索（首选） | `mcp__ace-tool__search_context` |
| 混合检索（语义+精确匹配） | `mcp__contextweaver__codebase-retrieval` |
| 精确字符串/正则 | `Grep` |
| 文件名匹配 | `Glob` |
| 深度代码库探索 | `Task` + `subagent_type=Explore` |

### 知识与文档

| 场景 | 推荐工具 |
|------|----------|
| 库官方文档 | `mcp__context7__resolve-library-id` → `mcp__context7__query-docs` |
| GitHub 开源项目 | `mcp__deepwiki__ask_question` / `read_wiki_structure` / `read_wiki_contents` |
| 联网搜索 | `mcp__exa__web_search_exa` → `mcp__tavily__tavily_search` → `WebSearch` |
| URL 内容提取 | `mcp__tavily__tavily_extract` |
| 综合深度研究 | `mcp__tavily__tavily_research` |
| 网站爬取/结构映射 | `mcp__tavily__tavily_crawl` / `mcp__tavily__tavily_map` |

### 开发辅助

| 场景 | 推荐工具 |
|------|----------|
| 技术方案规划 | `EnterPlanMode` 或 `Task` + `subagent_type=Plan` |

### 专项工具（按需使用）

| 场景 | 工具类别 |
|------|----------|
| 设计图解析 | `mcp__mastergo__*`（getDsl / getComponentLink / getMeta / getComponentGenerator） |
| 浏览器自动化 | `mcp__playwright__browser_*`（navigate / click / snapshot / screenshot 等） |
| Chrome 调试 | `mcp__chrome-devtools__*` |

**选择原则**：语义理解用 `ace-tool`，精确匹配用 `Grep`，联网搜索优先 `exa`
'@

$script:RulesTemplates['ccq-workflow.md'] = @'
# 工作流增强（CCG）

## 上下文检索（生成代码前执行）

**工具优先级**：

1. `mcp__ace-tool__search_context`（首选）- 纯语义搜索，适合开放性探索
2. `mcp__contextweaver__codebase-retrieval`（次选）- 混合引擎（语义+精确匹配），适合已知符号名 + 语义理解结合
3. `Glob` + `Grep`（回退）- MCP 不可用时的兜底方案

**检索策略**：

- 使用自然语言构建语义查询（Where/What/How）
- 完整性检查：获取相关类、函数、变量的完整定义与签名
- 若上下文不足，递归检索直至信息完整
- ContextWeaver 的 `technical_terms` 参数适合精确符号过滤

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
        return "$(Get-UserHome)\.claude\CLAUDE.md"
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
        return "$(Get-UserHome)\.claude\rules"
    } else {
        return "$env:HOME/.claude/rules"
    }
}

# ============================================================
# 步骤生命周期函数
# ============================================================

function Test-ClaudeMdInstalled {
    <#
    .SYNOPSIS
    检测 CLAUDE.md 及 rules 文件是否已配置
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $claudeMdPath = Get-ClaudeMdPath
    $rulesDir = Get-ClaudeRulesDir
    return Invoke-UnifiedCheck -StepId "ClaudeMd" -DisplayName "CLAUDE.md 配置" `
        -PathChecks @(
            @{ Path = $claudeMdPath; Type = "File"; ContentMatch = "# Claude Code 增强配置" },
            @{ Path = "$rulesDir\ccq-multimodel.md"; Type = "File"; ContentMatch = "# 多模型协作" },
            @{ Path = "$rulesDir\ccq-tools.md"; Type = "File"; ContentMatch = "# 工具速查与知识获取" },
            @{ Path = "$rulesDir\ccq-workflow.md"; Type = "File"; ContentMatch = "# 工作流增强" }
        ) `
        -CustomVerify {
            $content = Get-Content $claudeMdPath -Raw -ErrorAction SilentlyContinue
            $has1 = $content -match "## 一、核心原则"
            $has2 = $content -match "## 二、工作流原则"
            return ($has1 -and $has2)
        } -UseCache
}

function Install-ClaudeMd {
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

function Verify-ClaudeMd {
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
            'ccq-multimodel.md' = '# 多模型协作'
            'ccq-tools.md'      = '# 工具速查与知识获取'
            'ccq-workflow.md'   = '# 工作流增强'
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

function Update-ClaudeMd {
    <#
    .SYNOPSIS
    更新 CLAUDE.md + ccq-* rules 文件到最新版本
    .DESCRIPTION
    原子覆写 CLAUDE.md 和 ccq- 前缀的 rules 文件。
    仅操作 ccq- 前缀文件（HC-U8），用户自定义 rules 文件严禁修改。
    .RETURNS
    @{ Success; ErrorMessage; Data; UpdatedItems }
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
        UpdatedItems = @()
    }

    try {
        $updatedItems = [System.Collections.ArrayList]::new()
        $claudeMdPath = Get-ClaudeMdPath
        $rulesDir = Get-ClaudeRulesDir

        # 确保目录存在
        $claudeMdDir = Split-Path $claudeMdPath -Parent
        if (-not (Test-Path $claudeMdDir)) {
            New-Item -ItemType Directory -Path $claudeMdDir -Force | Out-Null
        }
        if (-not (Test-Path $rulesDir)) {
            New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
        }

        # 更新 CLAUDE.md 主文件
        $mainChanged = $true
        if (Test-Path $claudeMdPath) {
            $existingContent = Get-Content $claudeMdPath -Raw -ErrorAction SilentlyContinue
            $templateNormalized = $script:ClaudeMdTemplate -replace "`r`n", "`n"
            $existingNormalized = if ($existingContent) { $existingContent -replace "`r`n", "`n" } else { "" }
            if ($templateNormalized.Trim() -eq $existingNormalized.Trim()) {
                $mainChanged = $false
            }
        }

        if ($mainChanged) {
            $writeResult = Write-FileAtomically -FilePath $claudeMdPath -Content $script:ClaudeMdTemplate
            if (-not $writeResult) {
                throw "CLAUDE.md 写入失败"
            }
            [void]$updatedItems.Add("file::CLAUDE.md::overwritten")
        }

        # 清理旧版 rules 文件 (ccg- 前缀 或 无前缀的旧文件名)
        if (Test-Path $rulesDir) {
            $oldFiles = Get-ChildItem -Path (Join-Path $rulesDir "*") -Include "ccg-*.md", "multimodel.md", "tools.md", "workflow.md" -File -ErrorAction SilentlyContinue
            foreach ($oldFile in $oldFiles) {
                try {
                    Remove-Item $oldFile.FullName -Force -ErrorAction Stop
                    [void]$updatedItems.Add("file::rules/$($oldFile.Name)::deleted")
                } catch {
                    Write-UiWarn "无法删除旧 rules 文件: $($oldFile.Name) ($($_.Exception.Message))"
                }
            }
        }

        # 更新 ccq-* rules 文件
        foreach ($fileName in $script:RulesTemplates.Keys) {
            # HC-U8: 仅处理 ccq- 前缀的文件
            if (-not $fileName.StartsWith("ccq-")) {
                continue
            }

            $rulePath = Join-Path $rulesDir $fileName
            $ruleContent = $script:RulesTemplates[$fileName]

            $ruleChanged = $true
            if (Test-Path $rulePath) {
                $existingRule = Get-Content $rulePath -Raw -ErrorAction SilentlyContinue
                $ruleNormalized = $ruleContent -replace "`r`n", "`n"
                $existingRuleNormalized = if ($existingRule) { $existingRule -replace "`r`n", "`n" } else { "" }
                if ($ruleNormalized.Trim() -eq $existingRuleNormalized.Trim()) {
                    $ruleChanged = $false
                }
            }

            if ($ruleChanged) {
                $ruleWriteResult = Write-FileAtomically -FilePath $rulePath -Content $ruleContent
                if (-not $ruleWriteResult) {
                    throw "rules/$fileName 写入失败"
                }
                [void]$updatedItems.Add("file::rules/${fileName}::overwritten")
            }
        }

        # 结果
        if ($updatedItems.Count -eq 0) {
            $result.UpdatedItems = @("noop::ClaudeMd::no-change")
            Write-UiInfo "ClaudeMd 已是最新，无需更新"
        } else {
            $result.UpdatedItems = @($updatedItems)
            Write-UiSuccess "✓ ClaudeMd 已更新 ($($updatedItems.Count) 项变更)"
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 ClaudeMd 失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
