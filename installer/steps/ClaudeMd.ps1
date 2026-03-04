# CLAUDE.md 配置步骤 - CCQ
# 作者: 哈雷酱 (本小姐的完美文档管理！)
# 功能: 用户级 CLAUDE.md 配置文件写入（仅管理主文件）

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
# Claude  Code 增强配置 (CCG Enhanced)

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

# ============================================================
# 步骤生命周期函数
# ============================================================

function Test-ClaudeMdInstalled {
    <#
    .SYNOPSIS
    检测 CLAUDE.md 是否已配置（仅检查主文件）
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $claudeMdPath = Get-ClaudeMdPath
    return Invoke-UnifiedCheck -StepId "ClaudeMd" -DisplayName "CLAUDE.md 配置" `
        -PathChecks @(
            @{ Path = $claudeMdPath; Type = "File"; ContentMatch = "# Claude  Code 增强配置" }
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
    安装 CLAUDE.md 配置（仅主文件）
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

        Write-UiInfo "配置路径: $claudeMdPath"

        # 显示配置摘要
        Write-UiInfo "配置摘要:"
        Write-UiInfo "  - 主文件行数: $lineCount"
        Write-UiInfo "  - 核心原则: 5 项（调研优先/三问/红线/安全/风格）"
        Write-UiInfo "  - 工作流原则: 5 条"

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
    验证 CLAUDE.md 配置（仅主文件）
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
            "# Claude  Code 增强配置",
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

        Write-UiSuccess "CLAUDE.md 配置验证通过"
        Write-UiInfo "  - 主文件大小: $([math]::Round($fileSize / 1024, 2)) KB"
        Write-UiInfo "  - 章节完整性: 通过"

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
    更新 CLAUDE.md 到最新版本（仅主文件）
    .DESCRIPTION
    原子覆写 CLAUDE.md。不再管理 rules 文件（已迁移到 CcgWorkflow 和 McpManager）。
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

        # 确保目录存在
        $claudeMdDir = Split-Path $claudeMdPath -Parent
        if (-not (Test-Path $claudeMdDir)) {
            New-Item -ItemType Directory -Path $claudeMdDir -Force | Out-Null
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

        # 结果
        if ($updatedItems.Count -eq 0) {
            $result.UpdatedItems = @("noop::ClaudeMd::no-change")
            Write-UiInfo "ClaudeMd 已是最新，无需更新"
        } else {
            $result.UpdatedItems = @($updatedItems)
            Write-UiSuccess "ClaudeMd 已更新 ($($updatedItems.Count) 项变更)"
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
