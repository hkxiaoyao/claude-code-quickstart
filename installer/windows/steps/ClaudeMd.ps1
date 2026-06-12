# CLAUDE.md 配置步骤 - CCQ
# 作者: 哈雷酱 (本小姐的完美文档管理！)
# 功能: 用户级 CLAUDE.md 配置文件写入（仅管理主文件）

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 依赖: Ui.ps1, Profile.ps1（由入口脚本 dot-source 加载）

# ============================================================
# 模板定义
# ============================================================

# ── 契约模板加载（contracts-first + inline fallback）──

function Get-ClaudeMdContractsRoot {
    # irm|iex 场景下 $PSScriptRoot 为空，直接返回空触发 fallback
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return ""
    }

    $currentDir = $PSScriptRoot
    for ($i = 0; $i -lt 3; $i++) {
        $currentDir = Split-Path -Parent $currentDir
        if ([string]::IsNullOrWhiteSpace($currentDir)) {
            break
        }
        if (Test-Path (Join-Path $currentDir "installer\contracts\templates")) {
            return (Join-Path $currentDir "installer\contracts\templates")
        }
    }
    return ""
}

function Get-ClaudeMdTemplateContent {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('base', 'platform-windows', 'platform-macos')]
        [string]$TemplateName
    )

    $contractsRoot = Get-ClaudeMdContractsRoot
    if (-not [string]::IsNullOrWhiteSpace($contractsRoot)) {
        $templatePath = Join-Path $contractsRoot "claude-md.$TemplateName.md"
        if (Test-Path $templatePath) {
            try {
                return Get-Content $templatePath -Raw -Encoding UTF8
            } catch {
                Write-UiWarning "读取 claude-md.$TemplateName.md 失败，使用 inline fallback: $($_.Exception.Message)"
            }
        }
    }

    # Fallback: 返回 inline 模板
    return $null
}

# CLAUDE.md 主文件模板（~80 行，确保在 token 截断限制内完整可见）
$script:ClaudeMdTemplate = @'
# Claude Code 增强配置

## 一、核心原则

### 调研优先（强制）
修改代码或配置前必须先检索验证：确认入口、可复用实现、调用链和影响范围；上下文不足时继续检索，仍不明确则提问。

### 修改前三问
1. 这是真问题还是臆想？（拒绝过度设计）
2. 现有实现能否复用或扩展？（优先复用）
3. 会影响哪些调用关系、配置或用户流程？（保护依赖链）

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

## 二、工作流原则

1. **先检索，后生成** - 修改代码或配置前，必须先检索相关代码/文档，确认入口、复用点、调用链和影响范围；上下文不足时继续检索，仍不明确则提问
2. **事实必须验证** - 代码库事实用本地检索验证；第三方库、框架、SDK、CLI、云服务、版本迁移和配置语法用文档或联网工具验证，禁止猜测
3. **需求先对齐** - 复杂任务或检索后仍有歧义时，先明确关键边界、验收标准和不做范围，再进入实现
4. **高风险先确认** - 删除、提交、推送、重置、批量修改、依赖变更、生产 API、权限/环境配置等操作必须先获得用户明确确认

## 三、任务分级

| 级别 | 判断标准 | 处理方式 |
|------|----------|----------|
| 简单 | 单文件、明确需求、少于 20 行 | 除高风险操作外可直接执行 |
| 中等 | 2-5 个文件、需要调研 | 简要说明方案 → 等待用户确认 → 执行 |
| 复杂 | 架构变更、多模块、不确定性高 | 调研后生成具体 Markdown plan 文件 → 等待用户确认 → 执行 |

### 复杂任务流程
1. **RESEARCH** - 调研代码、调用链、复用点和影响范围，不急于给方案
2. **PLAN FILE** - 采用 ccg-plan 风格生成具体 Markdown 计划文件；不使用 Claude Code 内置 Plan Mode
3. **CONFIRM** - 等待用户确认计划文件后再执行
4. **EXECUTE** - 严格按确认后的计划执行
5. **REVIEW** - 完成后自检

触发：用户说"进入X模式"或任务符合复杂标准时自动启用

## 四、交互与环境

### 何时询问用户
- 存在多个合理方案时；需求不明确或有歧义时
- 改动范围超出预期时；发现潜在风险时

### 何时直接执行
- 需求明确、方案唯一、非高风险、非破坏性，且属于小范围修改（少于 20 行）时直接执行

### 敢于说不
发现问题直接指出，不妥协于错误方案

### 环境特定（Windows / PowerShell）
- 不支持 `&&`，使用 `;` 分隔命令
- 中文路径用引号包裹
- 管道传参：`"内容" | command` 替代 heredoc

### 输出设置
- 中文响应；禁用表情符号；禁止截断输出

## 五、偏好与记忆写入

### 写入位置决策
- **只在当前仓库成立的偏好 / 团队约束 / 项目约束** → 优先写入该项目的 `CLAUDE.md`（项目根或对应模块），保持项目自洽
- **跨多个项目都成立的真实用户偏好 / 个人协作偏好** → 才考虑写入 memory（`~/.claude/projects/<proj>/memory/`）
- 判断不清时，先问"换个项目这条还成立吗？"：成立 → memory；不成立 → 项目 `CLAUDE.md`

### 反例（禁止写入 memory）
- 项目特定的架构、路径、依赖、命令、约束（HC-*/SC-* 等）
- 临时任务状态、调试解决方案、git 历史可推导的信息
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

function Get-ClaudeMdFingerprint {
    <#
    .SYNOPSIS
    计算 ClaudeMd 步骤的内容指纹（供 Manage 更新指纹预检使用）
    .RETURNS
    string - 基于模板内容的 SHA-256 指纹
    #>
    $finalTemplate = Get-ClaudeMdAssembledTemplate
    return Get-StringFingerprint -Text $finalTemplate
}

function Get-ClaudeMdAssembledTemplate {
    <#
    .SYNOPSIS
    拼装完整 CLAUDE.md 内容（base + platform-windows）
    .DESCRIPTION
    优先从契约模板文件拼装，失败时降级到 inline fallback。
    拼装后的内容用于指纹计算和实际写入。
    .RETURNS
    string - 完整的 CLAUDE.md 内容
    #>

    # 尝试从契约模板拼装
    $baseContent = Get-ClaudeMdTemplateContent -TemplateName 'base'
    $platformContent = Get-ClaudeMdTemplateContent -TemplateName 'platform-windows'

    if ($baseContent -and $platformContent) {
        # 成功从契约读取，拼装返回
        return $baseContent.TrimEnd() + "`n`n" + $platformContent.TrimEnd() + "`n"
    }

    # 降级到 inline fallback
    return $script:ClaudeMdTemplate
}

# ============================================================
# 步骤生命周期函数
# ============================================================

function Test-ClaudeMdInstalled {
    <#
    .SYNOPSIS
    检测 CLAUDE.md 是否已配置（仅检查基础安装态）
    .DESCRIPTION
    只检查主文件存在 + 主标题标识存在。
    章节完整性和模板版本漂移由 Update（指纹比对）处理，
    避免因大幅模板变更而误判为"未安装"导致被踢出更新候选。
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $claudeMdPath = Get-ClaudeMdPath
    return Invoke-UnifiedCheck -StepId "ClaudeMd" -DisplayName "CLAUDE.md 配置" `
        -PathChecks @(
            @{ Path = $claudeMdPath; Type = "File"; ContentMatch = "# Claude Code 增强配置" }
        ) -UseCache
}

function Install-ClaudeMd {
    <#
    .SYNOPSIS
    安装 CLAUDE.md 配置（仅主文件）
    #>

    $result = @{ Success = $false; ErrorMessage = ""; Data = @{} }

    try {
        Write-UiPrimary "配置用户级 CLAUDE.md..." -Level Detail

        $claudeMdPath = Get-ClaudeMdPath

        # 确保 .claude 目录存在
        $claudeMdDir = Split-Path $claudeMdPath -Parent
        if (-not (Test-Path $claudeMdDir)) {
            New-Item -ItemType Directory -Path $claudeMdDir -Force | Out-Null
            Write-UiInfo "已创建目录: $claudeMdDir" -Level Detail
        }

        Write-UiPrimary "写入 CLAUDE.md 配置..." -Level Detail
        $assembledTemplate = Get-ClaudeMdAssembledTemplate
        $writeResult = Write-FileAtomically -FilePath $claudeMdPath -Content $assembledTemplate

        if (-not $writeResult) {
            throw "CLAUDE.md 写入失败"
        }

        $lineCount = ($assembledTemplate -split "`n").Count
        Write-UiSuccess "CLAUDE.md 已写入 ($lineCount 行)" -Level Detail

        Write-UiInfo "配置路径: $claudeMdPath" -Level Detail

        # 显示配置摘要
        Write-UiInfo "配置摘要:" -Level Detail
        Write-UiInfo "  - 主文件行数: $lineCount" -Level Detail
        Write-UiInfo "  - 核心原则: 5 项（调研优先/三问/红线/安全/风格）" -Level Detail
        Write-UiInfo "  - 工作流原则: 4 条" -Level Detail
        Write-UiInfo "  - 任务分级: 简单/中等/复杂" -Level Detail

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiDanger "配置 CLAUDE.md 失败: $($result.ErrorMessage)"
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

        # 验证关键章节（主文件 5 个章节）
        $sections = @(
            "# Claude Code 增强配置",
            "## 一、核心原则",
            "## 二、工作流原则",
            "## 三、任务分级",
            "## 四、交互与环境",
            "## 五、偏好与记忆写入"
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

        Write-UiSuccess "CLAUDE.md 配置验证通过" -Level Detail
        Write-UiInfo "  - 主文件大小: $([math]::Round($fileSize / 1024, 2)) KB" -Level Detail
        Write-UiInfo "  - 章节完整性: 通过" -Level Detail

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiDanger "验证 CLAUDE.md 配置失败: $($result.ErrorMessage)"
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
            Write-UiDim "ClaudeMd 已是最新，无需更新" -Level Debug
        } else {
            $result.UpdatedItems = @($updatedItems)
            Write-UiSuccess "ClaudeMd 已更新 ($($updatedItems.Count) 项变更)" -Level Detail
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 ClaudeMd 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
