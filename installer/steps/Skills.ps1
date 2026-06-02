# Claude Code Skills 安装步骤 - CCQ
# 功能: 通过 skills CLI 安装 Claude Code Skills

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 依赖: Ui.ps1, Process.ps1, Profile.ps1（由入口脚本 dot-source 加载）

$script:ClaudeSkillsDir = "$(Get-UserHome)\.claude\skills"
$script:SkillsInstallOptions = @{
    CopyMode = $false
}
$script:SkillsCategoryOrder = @("发现", "公共", "前端", "后端", "其他")
$script:LastSkillsInstallData = @{}

$script:SkillsCatalogue = @(
    @{
        Id          = "find-skills"
        Category    = "发现"
        Name        = "find-skills"
        Source      = "vercel-labs/skills"
        SkillName   = "find-skills"
        Description = "Skills 发现辅助技能"
        Default     = $true
        DetectName  = "find-skills"
    },
    @{
        Id          = "anthropics-skills"
        Category    = "公共"
        Name        = "官方 Skills"
        Source      = "anthropics/skills"
        SkillName   = ""
        Description = "Anthropic 官方 Skills 集合"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "vercel-agent-skills"
        Category    = "前端"
        Name        = "Vercel Agent Skills"
        Source      = "vercel-labs/agent-skills"
        SkillName   = ""
        Description = "Vercel Agent Skills 集合"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "vue-skills"
        Category    = "前端"
        Name        = "Vue Skills"
        Source      = "vuejs-ai/skills"
        SkillName   = ""
        Description = "Vue 开发 Skills 集合"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "ui-ux-pro-max"
        Category    = "前端"
        Name        = "UI UX Pro Max"
        Source      = "nextlevelbuilder/ui-ux-pro-max-skill"
        SkillName   = ""
        Description = "UI/UX 设计与前端体验技能"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "shadcn-ui-skills"
        Category    = "前端"
        Name        = "shadcn/ui Skills"
        Source      = "shadcn/ui"
        SkillName   = ""
        Description = "shadcn/ui 组件开发 Skills 集合"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "wot-ui-skills"
        Category    = "前端"
        Name        = "Wot UI Skills"
        Source      = "wot-ui/open-wot"
        SkillName   = ""
        Description = "Wot UI 开发 Skills 集合"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "ant-design-skills"
        Category    = "前端"
        Name        = "Ant Design Skills"
        Source      = "ant-design/ant-design-cli"
        SkillName   = ""
        Description = "Ant Design 开发 Skills 集合"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "ant-design-x-skills"
        Category    = "前端"
        Name        = "Ant Design X Skills"
        Source      = "https://github.com/ant-design/x/tree/main/packages/x-skill"
        SkillName   = ""
        Description = "Ant Design X Skills 集合"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "fastapi-skills"
        Category    = "后端"
        Name        = "FastAPI Skills"
        Source      = "https://github.com/fastapi/fastapi"
        SkillName   = "fastapi"
        Description = "FastAPI 开发 Skills"
        Default     = $false
        DetectName  = "fastapi"
    },
    @{
        Id          = "langchain-skills"
        Category    = "后端"
        Name        = "LangChain Skills"
        Source      = "langchain-ai/langchain-skills"
        SkillName   = ""
        Description = "LangChain 开发 Skills 集合"
        Default     = $false
        DetectName  = ""
    },
    @{
        Id          = "ppt-master"
        Category    = "其他"
        Name        = "PPT Master"
        Source      = "hugohe3/ppt-master"
        SkillName   = ""
        Description = "PPT 生成与演示文稿技能"
        Default     = $false
        DetectName  = ""
    }
)

function Set-SkillsInstallOptions {
    param(
        [bool]$CopyMode = $false
    )

    $script:SkillsInstallOptions.CopyMode = [bool]$CopyMode
}

function Get-SkillsCatalogue {
    <#
    .SYNOPSIS
    返回受控 Skills catalogue，并校验字段完整性。
    #>
    param()

    $catalogue = @($script:SkillsCatalogue)
    $requiredFields = @("Id", "Category", "Name", "Source", "SkillName", "Description", "Default", "DetectName")
    $seenIds = @{}

    foreach ($entry in $catalogue) {
        foreach ($field in $requiredFields) {
            if (-not $entry.ContainsKey($field)) {
                throw "Skills catalogue 条目缺少字段: $field"
            }
        }

        $id = [string]$entry["Id"]
        if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[a-z0-9-]+$') {
            throw "Skills catalogue ID 不合法: $id"
        }
        if ($seenIds.ContainsKey($id)) {
            throw "Skills catalogue ID 重复: $id"
        }
        $seenIds[$id] = $true

        $category = [string]$entry["Category"]
        if ($script:SkillsCategoryOrder -notcontains $category) {
            throw "Skills catalogue 类别不受支持: $category"
        }

        foreach ($field in @("Name", "Source", "Description")) {
            if ([string]::IsNullOrWhiteSpace([string]$entry[$field])) {
                throw "Skills catalogue 条目 $id 的字段 $field 不能为空"
            }
        }
    }

    return @($catalogue)
}

function Build-SkillsInstallArguments {
    <#
    .SYNOPSIS
    构造 skills CLI 的参数数组。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [bool]$CopyMode = $false
    )

    $arguments = @("--yes", "skills", "add", [string]$Entry["Source"], "--yes", "--agent", "claude-code", "--global")
    $skillName = [string]$Entry["SkillName"]
    if (-not [string]::IsNullOrWhiteSpace($skillName)) {
        $arguments += @("--skill", $skillName)
    }
    if ($CopyMode) {
        $arguments += "--copy"
    }

    return @($arguments)
}

function Test-SkillEntryInstalled {
    <#
    .SYNOPSIS
    实时检测指定 Skills 条目是否已安装。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    if (-not $Entry.ContainsKey("DetectName")) {
        return $false
    }

    $detectName = [string]$Entry["DetectName"]
    if ([string]::IsNullOrWhiteSpace($detectName)) {
        return $false
    }

    $skillPath = Join-Path $script:ClaudeSkillsDir $detectName
    return (Test-Path $skillPath -PathType Container)
}

function Test-SkillsInstalled {
    <#
    .SYNOPSIS
    检测 Claude Code Skills 是否已安装。
    #>
    param()

    $result = @{
        IsInstalled = $false
        Version     = ""
        Data        = @{
            SkillsDir            = $script:ClaudeSkillsDir
            InstalledKnownCount  = 0
            InstalledKnownSkills = @()
        }
        Message     = "未检测到已知 Skills"
    }

    try {
        $catalogue = @(Get-SkillsCatalogue)
        $installedKnownSkills = @()

        foreach ($entry in $catalogue) {
            if (Test-SkillEntryInstalled -Entry $entry) {
                $installedKnownSkills += [string]$entry["Id"]
            }
        }

        $installedKnownCount = $installedKnownSkills.Count
        $result.IsInstalled = ($installedKnownCount -gt 0)
        $result.Data["InstalledKnownCount"] = $installedKnownCount
        $result.Data["InstalledKnownSkills"] = @($installedKnownSkills)
        $result.Message = "已检测到 $installedKnownCount 个已知 Skills"
    }
    catch {
        $result.Message = "检测 Claude Code Skills 时出错: $($_.Exception.Message)"
    }

    return $result
}

function Show-SkillsSelectMenu {
    <#
    .SYNOPSIS
    显示 Skills catalogue 多选菜单。
    #>
    param()

    $catalogue = @(Get-SkillsCatalogue)
    $orderedEntries = @($catalogue | Sort-Object `
        @{ Expression = { [array]::IndexOf($script:SkillsCategoryOrder, [string]$_["Category"]) } },
        @{ Expression = { [string]$_["Name"] } })

    $options = [System.Collections.Generic.List[string]]::new()
    $entryMap = [System.Collections.Generic.List[hashtable]]::new()
    $defaultSelected = [System.Collections.Generic.List[int]]::new()

    for ($i = 0; $i -lt $orderedEntries.Count; $i++) {
        $entry = $orderedEntries[$i]
        $isInstalled = Test-SkillEntryInstalled -Entry $entry
        $tag = if ($isInstalled) { "[PASS]" } else { "[    ]" }
        $description = [string]$entry["Description"]
        if ([string]::IsNullOrWhiteSpace([string]$entry["SkillName"])) {
            $description += "（集合）"
        }

        $category = [string]$entry["Category"]
        $name = [string]$entry["Name"]
        $displayText = "$tag $category / $name - $description"
        [void]$options.Add($displayText)
        [void]$entryMap.Add($entry)

        if (([bool]$entry["Default"]) -and -not $isInstalled) {
            [void]$defaultSelected.Add($i)
        }
    }

    $selectedRaw = Show-MultiSelectMenu `
        -Title "Claude Code Skills - 选择要安装的 Skills" `
        -Options ([string[]]$options.ToArray()) `
        -DefaultSelected ([int[]]$defaultSelected.ToArray())

    if ($null -eq $selectedRaw) {
        return @()
    }

    $selectedIndices = @($selectedRaw)
    if ($selectedIndices.Count -eq 1 -and $selectedIndices[0] -is [array]) {
        $selectedIndices = @($selectedIndices[0])
    }
    if ($selectedIndices.Count -eq 0) {
        return @()
    }

    $selectedEntries = @()
    foreach ($idx in $selectedIndices) {
        if ($idx -ge 0 -and $idx -lt $entryMap.Count) {
            $selectedEntries += $entryMap[$idx]
        }
    }

    return @($selectedEntries)
}

function Resolve-SkillsCopyMode {
    <#
    .SYNOPSIS
    解析是否启用 skills CLI copy 模式。
    #>
    param()

    if ([bool]$script:SkillsInstallOptions.CopyMode) {
        return $true
    }

    $choice = Show-SingleSelectMenu `
        -Title "是否启用 Skills copy 模式？" `
        -Options @(
            "不启用 copy 模式（默认）",
            "启用 copy 模式（追加 --copy，适合 symlink 权限受限）"
        ) `
        -DefaultIndex 0

    return ($choice -eq 1)
}

function Get-SkillsInstallFriendlyError {
    <#
    .SYNOPSIS
    将 skills CLI 错误输出分类为友好提示。
    #>
    param(
        [int]$ExitCode,
        [string]$ErrorText = ""
    )

    if ($ErrorText -match 'ETIMEDOUT|ECONNREFUSED|ENOTFOUND|network|fetch failed') {
        return "无法访问 npm/GitHub，请检查网络连接或代理设置"
    }
    if ($ErrorText -match 'EACCES|EPERM|permission|symlink') {
        return "文件权限或 symlink 创建失败，可重跑并启用 -SkillsCopy"
    }
    if ($ErrorText -match 'not found|No matching|404') {
        return "Skills source 或指定 skill 可能已变更，请检查 catalogue"
    }

    return "Skills 安装失败 (ExitCode: $ExitCode)"
}

function Install-SkillEntry {
    <#
    .SYNOPSIS
    安装单个 Skills catalogue 条目。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [bool]$CopyMode = $false
    )

    $entryId = [string]$Entry["Id"]
    $entryName = [string]$Entry["Name"]
    $result = @{
        Success      = $false
        Skipped      = $false
        Id           = $entryId
        Name         = $entryName
        ErrorMessage = ""
        ErrorDetails = ""
        Data         = @{}
    }

    if (Test-SkillEntryInstalled -Entry $Entry) {
        Write-UiInfo "  - $entryName 已安装 [PASS]" -Level Detail
        $result.Success = $true
        $result.Skipped = $true
        return $result
    }

    $arguments = @(Build-SkillsInstallArguments -Entry $Entry -CopyMode $CopyMode)
    $preview = "npx $($arguments -join ' ')"
    Write-UiPrimary "  - 正在安装 $entryName" -Level Detail
    Write-UiInfo "    命令: $preview" -Level Debug

    try {
        $commandResult = Invoke-ExternalCommand `
            -Command "npx" `
            -Arguments $arguments `
            -TimeoutSeconds 600 `
            -RetryCount 1

        if ($commandResult.ExitCode -eq 0) {
            Write-UiSuccess "  - $entryName 安装成功 [PASS]" -Level Detail
            $result.Success = $true
            $result.Data["Command"] = $preview
            return $result
        }

        $errorText = $commandResult.Error
        if ([string]::IsNullOrWhiteSpace($errorText)) {
            $errorText = $commandResult.Output
        }
        $result.ErrorMessage = Get-SkillsInstallFriendlyError -ExitCode $commandResult.ExitCode -ErrorText $errorText
        $result.ErrorDetails = $errorText
    }
    catch {
        $errorText = $_.Exception.Message
        $result.ErrorMessage = Get-SkillsInstallFriendlyError -ExitCode -1 -ErrorText $errorText
        $result.ErrorDetails = $errorText
    }

    Write-UiWarning "  - $entryName 安装失败 [FAIL]: $($result.ErrorMessage)" -Level Detail
    return $result
}

function Install-Skills {
    <#
    .SYNOPSIS
    安装用户选择的 Claude Code Skills。
    #>
    param()

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        Write-UiPrimary "安装 Claude Code Skills..." -Level Detail
        Refresh-SessionPath

        foreach ($cmd in @("node", "npm", "npx")) {
            $details = Test-CommandAvailable -Command $cmd -ReturnDetails
            if (-not $details.Available) {
                $errorMsg = "未找到 $cmd 命令，请先完成 NodeJS 步骤"
                if ($details.ResolvedPath) {
                    $errorMsg += "`n  解析路径: $($details.ResolvedPath)"
                }
                if ($details.ErrorMessage) {
                    $errorMsg += "`n  错误详情: $($details.ErrorMessage)"
                }
                throw $errorMsg
            }
        }

        Write-UiInfo "安装目标: $script:ClaudeSkillsDir" -Level Detail
        Write-UiInfo "Agent: claude-code；范围: --global" -Level Detail

        $copyMode = Resolve-SkillsCopyMode
        if ($copyMode) {
            Write-UiInfo "copy 模式: 已启用 (--copy)" -Level Detail
        } else {
            Write-UiInfo "copy 模式: 未启用" -Level Detail
        }

        $selectedEntries = @(Show-SkillsSelectMenu)
        if ($selectedEntries.Count -eq 0) {
            Write-UiWarning "未选择任何 Skills，跳过安装"
            $result.Success = $true
            $result.Data = @{
                SelectedIds   = @()
                InstalledIds  = @()
                SkippedIds    = @()
                FailedIds     = @()
                CopyMode      = $copyMode
                SkippedReason = "no-selection"
            }
            $script:LastSkillsInstallData = $result.Data
            return $result
        }

        $installedIds = @()
        $skippedIds = @()
        $failedIds = @()
        $failedMessages = @()
        $selectedIds = @($selectedEntries | ForEach-Object { [string]$_["Id"] })

        foreach ($entry in $selectedEntries) {
            $entryResult = Install-SkillEntry -Entry $entry -CopyMode $copyMode
            if ([bool]$entryResult.Success) {
                if ([bool]$entryResult.Skipped) {
                    $skippedIds += [string]$entryResult.Id
                } else {
                    $installedIds += [string]$entryResult.Id
                }
            } else {
                $failedIds += [string]$entryResult.Id
                $failedMessages += "$($entryResult.Id): $($entryResult.ErrorMessage)"
            }
        }

        $result.Data = @{
            SelectedIds  = @($selectedIds)
            InstalledIds = @($installedIds)
            SkippedIds   = @($skippedIds)
            FailedIds    = @($failedIds)
            CopyMode     = $copyMode
        }
        $script:LastSkillsInstallData = $result.Data

        if ($failedIds.Count -gt 0) {
            $result.ErrorMessage = "以下 Skills 安装失败: $($failedIds -join ', ')"
            if ($failedMessages.Count -gt 0) {
                $result.ErrorMessage += "`n$($failedMessages -join "`n")"
            }
            return $result
        }

        Write-UiSuccess "Claude Code Skills 安装完成" -Level Detail
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "安装 Claude Code Skills 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Verify-Skills {
    <#
    .SYNOPSIS
    验证本次成功安装的 Claude Code Skills。
    #>
    param()

    $result = @{
        Success      = $false
        ErrorMessage = ""
    }

    try {
        $installData = $script:LastSkillsInstallData
        if ($installData.ContainsKey("SkippedReason") -and [string]$installData["SkippedReason"] -eq "no-selection") {
            Write-UiInfo "  - 未选择 Skills，验证跳过 [SKIP]" -Level Detail
            $result.Success = $true
            return $result
        }

        $installedIds = @()
        if ($installData.ContainsKey("InstalledIds")) {
            $installedIds = @($installData["InstalledIds"])
        }

        if ($installedIds.Count -eq 0) {
            Write-UiInfo "  - 本次无新增 Skills 需要验证 [SKIP]" -Level Detail
            $result.Success = $true
            return $result
        }

        $catalogue = @(Get-SkillsCatalogue)
        $entryById = @{}
        foreach ($entry in $catalogue) {
            $entryById[[string]$entry["Id"]] = $entry
        }

        $failed = @()
        foreach ($id in $installedIds) {
            if (-not $entryById.ContainsKey([string]$id)) {
                continue
            }

            $entry = $entryById[[string]$id]
            $detectName = [string]$entry["DetectName"]
            if ([string]::IsNullOrWhiteSpace($detectName)) {
                Write-UiInfo "  - $([string]$entry['Name']): 集合安装结果由 skills CLI 决定 [SKIP]" -Level Detail
                continue
            }

            if (Test-SkillEntryInstalled -Entry $entry) {
                Write-UiInfo "  - $([string]$entry['Name']): 目录检测通过 [PASS]" -Level Detail
            } else {
                Write-UiInfo "  - $([string]$entry['Name']): 未检测到目录 $detectName [FAIL]" -Level Detail
                $failed += [string]$id
            }
        }

        if ($failed.Count -gt 0) {
            $result.ErrorMessage = "以下 Skills 验证失败: $($failed -join ', ')"
            return $result
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证 Claude Code Skills 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
