# Skills 安装步骤 - CCQ
# 功能: 通过 skills CLI 安装/更新/卸载 Skills

#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 依赖: Ui.ps1, Process.ps1, Profile.ps1（由入口脚本 dot-source 加载）

$script:SkillsCliScope = "global:claude-code"
$script:SkillsInstallOptions = @{
    CopyMode = $false
}
$script:SkillsCategoryOrder = @("发现", "公共", "前端", "后端", "其他")
$script:SkillsIgnoredNames = @(
    "ccg-skills",
    "collaborating-with-codex",
    "collaborating-with-gemini"
)
$script:SkillsSourceDiscoveryCache = @{}
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
    },
    @{
        Id          = "anthropics-skills"
        Category    = "公共"
        Name        = "官方 Skills"
        Source      = "anthropics/skills"
        SkillName   = ""
        Description = "Anthropic 官方 Skills 集合"
        Default     = $false
    },
    @{
        Id          = "vercel-agent-skills"
        Category    = "前端"
        Name        = "Vercel Agent Skills"
        Source      = "vercel-labs/agent-skills"
        SkillName   = ""
        Description = "Vercel Agent Skills 集合"
        Default     = $false
    },
    @{
        Id          = "vue-skills"
        Category    = "前端"
        Name        = "Vue Skills"
        Source      = "vuejs-ai/skills"
        SkillName   = ""
        Description = "Vue 开发 Skills 集合"
        Default     = $false
    },
    @{
        Id          = "ui-ux-pro-max"
        Category    = "前端"
        Name        = "UI UX Pro Max"
        Source      = "nextlevelbuilder/ui-ux-pro-max-skill"
        SkillName   = ""
        Description = "UI/UX 设计与前端体验技能"
        Default     = $false
    },
    @{
        Id          = "shadcn-ui-skills"
        Category    = "前端"
        Name        = "shadcn/ui Skills"
        Source      = "shadcn/ui"
        SkillName   = ""
        Description = "shadcn/ui 组件开发 Skills 集合"
        Default     = $false
    },
    @{
        Id          = "wot-ui-skills"
        Category    = "前端"
        Name        = "Wot UI Skills"
        Source      = "wot-ui/open-wot"
        SkillName   = ""
        Description = "Wot UI 开发 Skills 集合"
        Default     = $false
    },
    @{
        Id          = "ant-design-skills"
        Category    = "前端"
        Name        = "Ant Design Skills"
        Source      = "ant-design/ant-design-cli"
        SkillName   = ""
        Description = "Ant Design 开发 Skills 集合"
        Default     = $false
    },
    @{
        Id          = "ant-design-x-skills"
        Category    = "前端"
        Name        = "Ant Design X Skills"
        Source      = "https://github.com/ant-design/x/tree/main/packages/x-skill"
        SkillName   = ""
        Description = "Ant Design X Skills 集合"
        Default     = $false
    },
    @{
        Id          = "fastapi-skills"
        Category    = "后端"
        Name        = "FastAPI Skills"
        Source      = "https://github.com/fastapi/fastapi"
        SkillName   = "fastapi"
        Description = "FastAPI 开发 Skills"
        Default     = $false
    },
    @{
        Id          = "langchain-skills"
        Category    = "后端"
        Name        = "LangChain Skills"
        Source      = "langchain-ai/langchain-skills"
        SkillName   = ""
        Description = "LangChain 开发 Skills 集合"
        Default     = $false
    },
    @{
        Id          = "ppt-master"
        Category    = "其他"
        Name        = "PPT Master"
        Source      = "hugohe3/ppt-master"
        SkillName   = ""
        Description = "PPT 生成与演示文稿技能"
        Default     = $false
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

    .NOTES
    catalogue 只描述 source 与展示元数据；实际 Skill name 必须通过 skills CLI 动态发现。
    #>
    param()

    $catalogue = @($script:SkillsCatalogue)
    $requiredFields = @("Id", "Category", "Name", "Source", "SkillName", "Description", "Default")
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
        if ($entry.ContainsKey("ExpectedNames")) {
            throw "Skills catalogue 条目 $id 禁止写死 ExpectedNames，请通过 CLI 动态发现"
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

function Get-UniqueSkillNames {
    <#
    .SYNOPSIS
    规范化并去重 Skills 名称，保留首次出现顺序。
    #>
    param(
        [array]$Names = @()
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($Names)) {
        $value = [string]$name
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        $value = $value.Trim()
        if ($seen.Add($value)) {
            [void]$result.Add($value)
        }
    }

    return @($result)
}

function Test-SkillNameIgnored {
    <#
    .SYNOPSIS
    判断 Skill 是否由其他步骤管理，应从 Skills catalogue 检测中忽略。
    #>
    param(
        [string]$Name
    )

    foreach ($ignoredName in $script:SkillsIgnoredNames) {
        if ([string]$Name -ieq [string]$ignoredName) {
            return $true
        }
    }

    return $false
}

function Get-SkillsDiscoveryCacheKey {
    <#
    .SYNOPSIS
    生成 Skills source 动态发现缓存键。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    $source = [string]$Entry["Source"]
    $skillName = ""
    if ($Entry.ContainsKey("SkillName")) {
        $skillName = [string]$Entry["SkillName"]
    }

    return "$source`n$skillName"
}

function Get-SkillEntryDiscoveredNames {
    <#
    .SYNOPSIS
    通过 skills CLI 动态发现 catalogue 条目的实际 Skill name 集合。

    .NOTES
    catalogue 只保存 source 元数据；SkillName 仅作为 CLI 的 --skill 选择器参与动态发现。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [switch]$AllowSourceDiscovery
    )

    if (-not $AllowSourceDiscovery) {
        return @()
    }

    $cacheKey = Get-SkillsDiscoveryCacheKey -Entry $Entry
    if ($script:SkillsSourceDiscoveryCache.ContainsKey($cacheKey)) {
        return @($script:SkillsSourceDiscoveryCache[$cacheKey])
    }

    Write-UiDim "  动态发现 Skills: $($Entry['Source'])" -Level Debug
    $result = Invoke-SkillsSourceListDiscovery -Entry $Entry
    return @($result["Names"])
}

function Remove-SkillsAnsiSequences {
    <#
    .SYNOPSIS
    清理 skills CLI 文本输出中的 ANSI 控制序列。
    #>
    param(
        [string]$Text = ""
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    $escape = [string][char]27
    $clean = $Text -replace "$escape\[[0-?]*[ -/]*[@-~]", ""
    $clean = $clean -replace "[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", ""
    return $clean
}

function ConvertFrom-SkillsSourceListOutput {
    <#
    .SYNOPSIS
    从 skills add --list 输出中提取实际 Skill name。
    #>
    param(
        [string]$Text = ""
    )

    $clean = Remove-SkillsAnsiSequences -Text $Text
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($rawLine in @($clean -split "`r?`n")) {
        $line = ([string]$rawLine).Trim()
        if (-not $line.StartsWith("│")) {
            continue
        }

        $candidate = $line.TrimStart([char]0x2502).Trim()
        if ($candidate -match '^[A-Za-z0-9][A-Za-z0-9:_-]{0,79}$') {
            [void]$names.Add($candidate)
        }
    }

    return @(Get-UniqueSkillNames -Names @($names))
}

function Invoke-SkillsSourceListDiscovery {
    <#
    .SYNOPSIS
    执行一次 skills add --list 动态发现，并写入本进程缓存。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    $source = [string]$Entry["Source"]
    $skillName = [string]$Entry["SkillName"]
    $cacheKey = Get-SkillsDiscoveryCacheKey -Entry $Entry
    $result = @{
        Success      = $false
        CacheKey     = $cacheKey
        Names        = @()
        ErrorMessage = ""
        Source       = $source
        SkillName    = $skillName
    }

    if ($script:SkillsSourceDiscoveryCache.ContainsKey($cacheKey)) {
        $result.Success = $true
        $result.Names = @($script:SkillsSourceDiscoveryCache[$cacheKey])
        return $result
    }

    $arguments = @("--yes", "skills", "add", $source, "--list", "-g", "--agent", "claude-code")
    if (-not [string]::IsNullOrWhiteSpace($skillName)) {
        $arguments += @("--skill", $skillName)
    }

    try {
        $commandResult = Invoke-ExternalCommand `
            -Command "npx" `
            -Arguments $arguments `
            -SuppressOutput `
            -TimeoutSeconds 180 `
            -RetryCount 0

        $text = "$($commandResult.Output)`n$($commandResult.Error)"
        $names = @(ConvertFrom-SkillsSourceListOutput -Text $text)
        $result.Success = $true
        $result.Names = @($names)
        $script:SkillsSourceDiscoveryCache[$cacheKey] = @($names)
        return $result
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiDim "Skills source 动态发现失败: $source ($($result.ErrorMessage))" -Level Debug
        $script:SkillsSourceDiscoveryCache[$cacheKey] = @()
        return $result
    }
}

function Get-SkillsSourceDiscoveredNames {
    <#
    .SYNOPSIS
    使用 skills CLI 动态列出 source 中包含的实际 Skill name。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    $result = Invoke-SkillsSourceListDiscovery -Entry $Entry
    return @($result["Names"])
}

function Get-SkillsDiscoveryValue {
    <#
    .SYNOPSIS
    从 hashtable 或对象中安全读取动态发现结果字段。
    #>
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }
    if ($InputObject -is [hashtable] -and $InputObject.ContainsKey($Name)) {
        return $InputObject[$Name]
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }

    return $DefaultValue
}

function Invoke-SkillsCatalogueDiscoveryParallel {
    <#
    .SYNOPSIS
    使用 Start-ThreadJob 对未缓存 catalogue 条目执行有界并发动态发现。
    #>
    param(
        [array]$Entries = @(),

        [int]$MaxConcurrency = 2,

        [switch]$ShowProgress,

        [int]$TotalCount = 0
    )

    $queue = [System.Collections.Queue]::new()
    foreach ($entry in @($Entries)) {
        $queue.Enqueue($entry)
    }

    $jobs = @()
    $results = [System.Collections.Generic.List[hashtable]]::new()
    $completedCount = 0
    if ($TotalCount -le 0) {
        $TotalCount = @($Entries).Count
    }

    $jobScript = {
        param(
            [hashtable]$Entry,
            [string]$CacheKey
        )

        $source = [string]$Entry["Source"]
        $skillName = [string]$Entry["SkillName"]
        $arguments = @("--yes", "skills", "add", $source, "--list", "-g", "--agent", "claude-code")
        if (-not [string]::IsNullOrWhiteSpace($skillName)) {
            $arguments += @("--skill", $skillName)
        }

        try {
            $actualFileName = "npx"
            $actualArguments = $arguments
            try {
                $cmdInfo = Get-Command "npx" -ErrorAction Stop
                if ($cmdInfo.CommandType -eq "Application" -or $cmdInfo.CommandType -eq "ExternalScript") {
                    $extension = [System.IO.Path]::GetExtension($cmdInfo.Source).ToLower()
                    if ($extension -eq ".cmd" -or $extension -eq ".bat") {
                        $cmdPath = $cmdInfo.Source
                        if ($cmdPath -match "\s") {
                            $cmdPath = "`"$cmdPath`""
                        }
                        $fullCommand = $cmdPath
                        if ($arguments.Count -gt 0) {
                            $fullCommand += " " + ($arguments -join " ")
                        }
                        $actualFileName = "cmd.exe"
                        $actualArguments = @("/d", "/s", "/c", $fullCommand)
                    } elseif ($extension -eq ".ps1") {
                        $ps1Path = $cmdInfo.Source
                        if ($ps1Path -match "\s") {
                            $ps1Path = "`"$ps1Path`""
                        }
                        $actualFileName = "pwsh.exe"
                        $actualArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ps1Path) + $arguments
                    } elseif ($extension -eq ".exe") {
                        $actualFileName = $cmdInfo.Source
                    }
                }
            }
            catch {
                $actualFileName = "npx"
                $actualArguments = $arguments
            }

            $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $processInfo.FileName = $actualFileName
            $processInfo.Arguments = $actualArguments -join " "
            $processInfo.UseShellExecute = $false
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.CreateNoWindow = $true
            try {
                $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
            } catch { }

            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $processInfo
            try {
                [void]$process.Start()
                $outputTask = $process.StandardOutput.ReadToEndAsync()
                $errorTask = $process.StandardError.ReadToEndAsync()
                if (-not $process.WaitForExit(180000)) {
                    $process.Kill()
                    throw "skills add --list 执行超时: $source"
                }
                $process.WaitForExit()
                $outputText = $outputTask.GetAwaiter().GetResult()
                $errorText = $errorTask.GetAwaiter().GetResult()
                $exitCode = [int]$process.ExitCode
                return @{
                    Success      = ($exitCode -eq 0)
                    CacheKey     = $CacheKey
                    Source       = $source
                    SkillName    = $skillName
                    Output       = $outputText.Trim()
                    Error        = $errorText.Trim()
                    ErrorMessage = if ($exitCode -eq 0) { "" } else { "skills add --list 退出码: $exitCode" }
                }
            }
            finally {
                if ($null -ne $process) {
                    if (-not $process.HasExited) {
                        try { $process.Kill() } catch { }
                    }
                    $process.Dispose()
                }
            }
        }
        catch {
            return @{
                Success      = $false
                CacheKey     = $CacheKey
                Source       = $source
                SkillName    = $skillName
                Output       = ""
                Error        = ""
                ErrorMessage = $_.Exception.Message
            }
        }
    }

    try {
        while ($queue.Count -gt 0 -or $jobs.Count -gt 0) {
            while ($queue.Count -gt 0 -and $jobs.Count -lt $MaxConcurrency) {
                $entry = [hashtable]$queue.Dequeue()
                $cacheKey = Get-SkillsDiscoveryCacheKey -Entry $entry
                $job = Start-ThreadJob -ScriptBlock $jobScript -ArgumentList @($entry, $cacheKey)
                $jobs += @{
                    Job      = $job
                    Entry    = $entry
                    CacheKey = $cacheKey
                }
            }

            if ($jobs.Count -eq 0) {
                continue
            }

            $activeJobs = @($jobs | ForEach-Object { $_["Job"] })
            $finishedJobs = @(Wait-Job -Job $activeJobs -Any -Timeout 1)
            if ($finishedJobs.Count -eq 0) {
                continue
            }

            foreach ($finishedJob in $finishedJobs) {
                $jobItems = @($jobs | Where-Object { [int]$_["Job"].Id -eq [int]$finishedJob.Id })
                if ($jobItems.Count -eq 0) {
                    continue
                }

                $jobItem = $jobItems[0]
                $entry = [hashtable]$jobItem["Entry"]
                $cacheKey = [string]$jobItem["CacheKey"]
                $entryName = [string]$entry["Name"]
                $discovery = $null

                try {
                    $jobOutput = @(Receive-Job -Job $finishedJob -ErrorAction Stop)
                    $rawResult = if ($jobOutput.Count -gt 0) { $jobOutput[-1] } else { $null }
                    $jobSuccess = [bool](Get-SkillsDiscoveryValue -InputObject $rawResult -Name "Success" -DefaultValue $false)
                    if ($jobSuccess) {
                        $outputText = [string](Get-SkillsDiscoveryValue -InputObject $rawResult -Name "Output" -DefaultValue "")
                        $errorText = [string](Get-SkillsDiscoveryValue -InputObject $rawResult -Name "Error" -DefaultValue "")
                        $names = @(ConvertFrom-SkillsSourceListOutput -Text "$outputText`n$errorText")
                        $script:SkillsSourceDiscoveryCache[$cacheKey] = @($names)
                        $discovery = @{
                            Success      = $true
                            CacheKey     = $cacheKey
                            Names        = @($names)
                            ErrorMessage = ""
                            Source       = [string]$entry["Source"]
                            SkillName    = [string]$entry["SkillName"]
                        }
                    } else {
                        $errorMessage = [string](Get-SkillsDiscoveryValue -InputObject $rawResult -Name "ErrorMessage" -DefaultValue "并发动态发现失败")
                        Write-UiDim "Skills source 并发动态发现失败，改用串行重试: $([string]$entry['Source']) ($errorMessage)" -Level Debug
                        $discovery = Invoke-SkillsSourceListDiscovery -Entry $entry
                    }
                }
                catch {
                    Write-UiDim "Skills source 并发动态发现异常，改用串行重试: $([string]$entry['Source']) ($($_.Exception.Message))" -Level Debug
                    $discovery = Invoke-SkillsSourceListDiscovery -Entry $entry
                }
                finally {
                    Remove-Job -Job $finishedJob -Force -ErrorAction SilentlyContinue
                }

                $completedCount++
                if ($ShowProgress) {
                    if ([bool]$discovery["Success"]) {
                        Write-UiInfo "  - [$completedCount/$TotalCount] ${entryName}: 发现 $(@($discovery['Names']).Count) 个"
                    } else {
                        Write-UiWarning "  - [$completedCount/$TotalCount] ${entryName}: 发现失败，状态未知"
                    }
                }

                [void]$results.Add($discovery)
                $jobs = @($jobs | Where-Object { [int]$_["Job"].Id -ne [int]$finishedJob.Id })
            }
        }
    }
    finally {
        foreach ($jobItem in @($jobs)) {
            $job = $jobItem["Job"]
            if ($null -ne $job) {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return @($results)
}

function Resolve-SkillsCatalogueDiscovery {
    <#
    .SYNOPSIS
    批量解析 catalogue 动态发现结果，缓存命中直接复用，未命中使用有界并发预取。
    #>
    param(
        [array]$Entries = @(),

        [int]$MaxConcurrency = 2,

        [switch]$ShowProgress
    )

    $resultsByKey = @{}
    $pending = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($entry in @($Entries)) {
        $cacheKey = Get-SkillsDiscoveryCacheKey -Entry $entry
        if ($script:SkillsSourceDiscoveryCache.ContainsKey($cacheKey)) {
            $resultsByKey[$cacheKey] = @{
                Success      = $true
                CacheKey     = $cacheKey
                Names        = @($script:SkillsSourceDiscoveryCache[$cacheKey])
                ErrorMessage = ""
                Source       = [string]$entry["Source"]
                SkillName    = [string]$entry["SkillName"]
            }
        } else {
            [void]$pending.Add($entry)
        }
    }

    $pendingCount = $pending.Count
    if ($pendingCount -eq 0) {
        return $resultsByKey
    }

    if ($MaxConcurrency -lt 1) {
        $MaxConcurrency = 1
    }

    if ($ShowProgress) {
        Write-UiPrimary "正在动态发现 Skills catalogue（0/$pendingCount，最多并发 $MaxConcurrency）..."
    }

    $canUseThreadJob = $false
    try {
        $canUseThreadJob = ($null -ne (Get-Command "Start-ThreadJob" -ErrorAction SilentlyContinue))
    }
    catch {
        $canUseThreadJob = $false
    }

    if ($canUseThreadJob -and $MaxConcurrency -gt 1 -and $pendingCount -gt 1) {
        try {
            $parallelResults = @(Invoke-SkillsCatalogueDiscoveryParallel -Entries @($pending) -MaxConcurrency $MaxConcurrency -ShowProgress:$ShowProgress -TotalCount $pendingCount)
            foreach ($discovery in $parallelResults) {
                $resultsByKey[[string]$discovery["CacheKey"]] = $discovery
            }
            return $resultsByKey
        }
        catch {
            Write-UiDim "Skills catalogue 并发动态发现失败，回退串行: $($_.Exception.Message)" -Level Debug
        }
    }

    $completedCount = 0
    foreach ($entry in @($pending)) {
        $discovery = Invoke-SkillsSourceListDiscovery -Entry $entry
        $resultsByKey[[string]$discovery["CacheKey"]] = $discovery
        $completedCount++
        if ($ShowProgress) {
            $entryName = [string]$entry["Name"]
            if ([bool]$discovery["Success"]) {
                Write-UiInfo "  - [$completedCount/$pendingCount] ${entryName}: 发现 $(@($discovery['Names']).Count) 个"
            } else {
                Write-UiWarning "  - [$completedCount/$pendingCount] ${entryName}: 发现失败，状态未知"
            }
        }
    }

    return $resultsByKey
}

function Resolve-SkillsCatalogueStatuses {
    <#
    .SYNOPSIS
    批量解析 catalogue 条目状态，复用同一次动态发现结果。
    #>
    param(
        [array]$Entries = @(),

        [AllowNull()]
        [object]$InstalledRecords = $null,

        [int]$MaxConcurrency = 2,

        [switch]$ShowProgress
    )

    $records = @()
    if ($null -eq $InstalledRecords) {
        $records = @(Get-InstalledSkillRecords)
    } else {
        $records = @($InstalledRecords)
    }

    $discoveryByKey = Resolve-SkillsCatalogueDiscovery -Entries @($Entries) -MaxConcurrency $MaxConcurrency -ShowProgress:$ShowProgress
    $items = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($entry in @($Entries)) {
        $cacheKey = Get-SkillsDiscoveryCacheKey -Entry $entry
        $resolvedDiscoveredNames = @()
        if ($discoveryByKey.ContainsKey($cacheKey)) {
            $resolvedDiscoveredNames = @($discoveryByKey[$cacheKey]["Names"])
        }

        $status = Get-SkillEntryInstallStatus -Entry $entry -InstalledRecords $records -DiscoveredNames $resolvedDiscoveredNames
        [void]$items.Add(@{
            Entry  = $entry
            Status = $status
        })
    }

    return @($items)
}

function Get-InstalledSkillRecords {
    <#
    .SYNOPSIS
    通过 skills CLI 检测全局 Claude Code Skills，返回名称与路径。
    #>
    param()

    $arguments = @("--yes", "skills", "list", "-g", "-a", "claude-code", "--json")
    try {
        $commandResult = Invoke-ExternalCommand `
            -Command "npx" `
            -Arguments $arguments `
            -SuppressOutput `
            -TimeoutSeconds 120 `
            -RetryCount 0

        if (-not $commandResult.Success -or [string]::IsNullOrWhiteSpace($commandResult.Output)) {
            return @()
        }

        $items = @($commandResult.Output | ConvertFrom-Json -AsHashtable)
        $recordsByName = @{}
        foreach ($item in $items) {
            if ($null -eq $item -or -not $item.ContainsKey("name")) {
                continue
            }

            $skillName = [string]$item["name"]
            if ([string]::IsNullOrWhiteSpace($skillName) -or (Test-SkillNameIgnored -Name $skillName)) {
                continue
            }

            $agents = @()
            if ($item.ContainsKey("agents")) {
                $agents = @($item["agents"])
            }

            $path = ""
            if ($item.ContainsKey("path")) {
                $path = [string]$item["path"]
            }

            $scope = ""
            if ($item.ContainsKey("scope")) {
                $scope = [string]$item["scope"]
            }

            if (-not $recordsByName.ContainsKey($skillName)) {
                $recordsByName[$skillName] = @{
                    Name   = $skillName
                    Path   = $path
                    Scope  = $scope
                    Agents = @($agents)
                }
            }
        }

        return @($recordsByName.Values | Sort-Object { [string]$_["Name"] })
    }
    catch {
        Write-UiDim "Skills CLI 检测失败: $($_.Exception.Message)" -Level Debug
        return @()
    }
}

function Get-SkillEntryInstallStatus {
    <#
    .SYNOPSIS
    返回 catalogue 条目的结构化安装状态。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [AllowNull()]
        [object]$InstalledRecords = $null,

        [AllowNull()]
        [object]$DiscoveredNames = $null
    )

    $records = @()
    if ($null -eq $InstalledRecords) {
        $records = @(Get-InstalledSkillRecords)
    } else {
        $records = @($InstalledRecords)
    }

    $resolvedDiscoveredNames = @()
    if ($null -eq $DiscoveredNames) {
        $resolvedDiscoveredNames = @(Get-SkillEntryDiscoveredNames -Entry $Entry -AllowSourceDiscovery)
    } else {
        $resolvedDiscoveredNames = @(Get-UniqueSkillNames -Names @($DiscoveredNames))
    }
    $recordsByName = @{}
    foreach ($record in $records) {
        $recordName = [string]$record["Name"]
        if (-not [string]::IsNullOrWhiteSpace($recordName) -and -not $recordsByName.ContainsKey($recordName)) {
            $recordsByName[$recordName] = $record
        }
    }

    $matched = @()
    $installedNames = @()
    $missingNames = @()
    foreach ($discoveredName in $resolvedDiscoveredNames) {
        if ($recordsByName.ContainsKey([string]$discoveredName)) {
            $matched += $recordsByName[[string]$discoveredName]
            $installedNames += [string]$recordsByName[[string]$discoveredName]["Name"]
        } else {
            $missingNames += [string]$discoveredName
        }
    }

    $state = "Unknown"
    if ($resolvedDiscoveredNames.Count -gt 0) {
        if ($missingNames.Count -eq 0) {
            $state = "Installed"
        } elseif ($installedNames.Count -gt 0) {
            $state = "Partial"
        } else {
            $state = "NotInstalled"
        }
    }

    return @{
        State           = $state
        DiscoveredNames = @($resolvedDiscoveredNames)
        InstalledNames  = @($installedNames)
        MissingNames    = @($missingNames)
        MatchedRecords  = @($matched)
        DiscoveredCount = $resolvedDiscoveredNames.Count
        InstalledCount  = $installedNames.Count
    }
}

function Get-SkillEntryInstalledRecords {
    <#
    .SYNOPSIS
    返回 catalogue 条目已安装的具体 Skills 记录。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [AllowNull()]
        [object]$InstalledRecords = $null
    )

    $status = Get-SkillEntryInstallStatus -Entry $Entry -InstalledRecords $InstalledRecords
    return @($status["MatchedRecords"])
}

function Get-SkillEntryStatusText {
    <#
    .SYNOPSIS
    将结构化安装状态转换为用户可读文本。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Status
    )

    $installedCount = [int]$Status["InstalledCount"]
    $discoveredCount = [int]$Status["DiscoveredCount"]
    switch ([string]$Status["State"]) {
        "Installed"    { return "已安装 $installedCount/$discoveredCount" }
        "Partial"      { return "部分安装 $installedCount/$discoveredCount" }
        "NotInstalled" { return "未安装 0/$discoveredCount" }
        default         { return "未知" }
    }
}

function Get-SkillEntryStatusColor {
    <#
    .SYNOPSIS
    返回状态表显示颜色。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Status
    )

    switch ([string]$Status["State"]) {
        "Installed" { return "Success" }
        "Partial"   { return "Warning" }
        default     { return "Dim" }
    }
}

function Build-SkillsInstallArguments {
    <#
    .SYNOPSIS
    构造 skills CLI 的安装参数数组。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [bool]$CopyMode = $false
    )

    $arguments = @("--yes", "skills", "add", [string]$Entry["Source"], "--yes", "--agent", "claude-code", "-g")
    $skillName = [string]$Entry["SkillName"]
    if (-not [string]::IsNullOrWhiteSpace($skillName)) {
        $arguments += @("--skill", $skillName)
    }
    if ($CopyMode) {
        $arguments += "--copy"
    }

    return @($arguments)
}

function Build-SkillsRemoveArguments {
    <#
    .SYNOPSIS
    构造 skills CLI 的卸载参数数组。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SkillNames
    )

    $arguments = @("--yes", "skills", "remove")
    $arguments += @($SkillNames)
    $arguments += @("-g", "-a", "claude-code", "--yes")
    return @($arguments)
}

function Test-SkillEntryInstalled {
    <#
    .SYNOPSIS
    实时检测指定 Skills 条目是否已完整安装。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    $status = Get-SkillEntryInstallStatus -Entry $Entry
    return ([string]$status["State"] -eq "Installed")
}

function Test-SkillsInstalled {
    <#
    .SYNOPSIS
    检测 Skills 是否已安装。
    #>
    param()

    $result = @{
        IsInstalled = $false
        Version     = ""
        Data        = @{
            SkillsScope             = $script:SkillsCliScope
            InstalledKnownCount     = 0
            InstalledCompleteCount  = 0
            InstalledPartialCount   = 0
            InstalledKnownSkills    = @()
            InstalledCompleteSkills = @()
            InstalledPartialSkills  = @()
            InstalledSkillNames     = @()
        }
        Message     = "未检测到已知 Skills"
    }

    try {
        $catalogue = @(Get-SkillsCatalogue)
        $installedRecords = @(Get-InstalledSkillRecords)
        $statuses = @(Resolve-SkillsCatalogueStatuses -Entries $catalogue -InstalledRecords $installedRecords)
        $installedKnownSkills = @()
        $installedCompleteSkills = @()
        $installedPartialSkills = @()

        foreach ($item in $statuses) {
            $entry = $item["Entry"]
            $status = $item["Status"]
            $state = [string]$status["State"]
            if ($state -eq "Installed" -or $state -eq "Partial") {
                $installedKnownSkills += [string]$entry["Id"]
            }
            if ($state -eq "Installed") {
                $installedCompleteSkills += [string]$entry["Id"]
            }
            if ($state -eq "Partial") {
                $installedPartialSkills += [string]$entry["Id"]
            }
        }

        $installedKnownCount = $installedKnownSkills.Count
        $installedSkillNames = @($installedRecords | ForEach-Object { [string]$_["Name"] })
        $result.IsInstalled = ($installedKnownCount -gt 0)
        $result.Data["InstalledKnownCount"] = $installedKnownCount
        $result.Data["InstalledCompleteCount"] = $installedCompleteSkills.Count
        $result.Data["InstalledPartialCount"] = $installedPartialSkills.Count
        $result.Data["InstalledKnownSkills"] = @($installedKnownSkills)
        $result.Data["InstalledCompleteSkills"] = @($installedCompleteSkills)
        $result.Data["InstalledPartialSkills"] = @($installedPartialSkills)
        $result.Data["InstalledSkillNames"] = @($installedSkillNames)
        $result.Message = "已检测到 $installedKnownCount 个已知 Skills（完整 $($installedCompleteSkills.Count)，部分 $($installedPartialSkills.Count)）"
    }
    catch {
        $result.Message = "检测 Skills 时出错: $($_.Exception.Message)"
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
    $installedRecords = @(Get-InstalledSkillRecords)
    $orderedEntries = @($catalogue | Sort-Object `
        @{ Expression = { [array]::IndexOf($script:SkillsCategoryOrder, [string]$_["Category"]) } },
        @{ Expression = { [string]$_["Name"] } })

    Write-UiPrimary "正在检测 Skills 状态..."
    $statusItems = @(Resolve-SkillsCatalogueStatuses -Entries $orderedEntries -InstalledRecords $installedRecords -ShowProgress)
    $options = [System.Collections.Generic.List[string]]::new()
    $entryMap = [System.Collections.Generic.List[hashtable]]::new()
    $defaultSelected = [System.Collections.Generic.List[int]]::new()

    for ($i = 0; $i -lt $statusItems.Count; $i++) {
        $item = $statusItems[$i]
        $entry = $item["Entry"]
        $status = $item["Status"]
        $statusText = Get-SkillEntryStatusText -Status $status
        $description = [string]$entry["Description"]
        if ([int]$status["DiscoveredCount"] -gt 1) {
            $description += "（集合）"
        }

        $category = [string]$entry["Category"]
        $name = [string]$entry["Name"]
        $displayText = "$category / $name（$statusText）- $description"
        [void]$options.Add($displayText)
        [void]$entryMap.Add($entry)

        if (([bool]$entry["Default"]) -and [string]$status["State"] -ne "Installed") {
            [void]$defaultSelected.Add($i)
        }
    }

    $selectedRaw = Show-MultiSelectMenu `
        -Title "Skills - 选择要安装/更新的 Skills" `
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
    安装或更新单个 Skills catalogue 条目，并记录实际新增/缺失的 Skill name。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry,

        [bool]$CopyMode = $false
    )

    $entryId = [string]$Entry["Id"]
    $entryName = [string]$Entry["Name"]
    $beforeRecords = @(Get-InstalledSkillRecords)
    $beforeStatus = Get-SkillEntryInstallStatus -Entry $Entry -InstalledRecords $beforeRecords
    $wasState = [string]$beforeStatus["State"]
    $actionText = switch ($wasState) {
        "Installed" { "更新/重装" }
        "Partial"   { "补齐/更新" }
        default     { "安装" }
    }

    $result = @{
        Success      = $false
        Skipped      = $false
        Id           = $entryId
        Name         = $entryName
        ErrorMessage = ""
        ErrorDetails = ""
        Data         = @{
            WasState             = $wasState
            WasInstalled         = ($wasState -eq "Installed")
            DiscoveredNames      = @($beforeStatus["DiscoveredNames"])
            BeforeInstalledNames = @($beforeStatus["InstalledNames"])
            BeforeMissingNames   = @($beforeStatus["MissingNames"])
            AfterState           = "Unknown"
            AfterInstalledNames  = @()
            AfterMissingNames    = @()
            AddedNames           = @()
        }
    }

    $arguments = @(Build-SkillsInstallArguments -Entry $Entry -CopyMode $CopyMode)
    $preview = "npx $($arguments -join ' ')"
    Write-UiPrimary "  - 正在${actionText} $entryName" -Level Detail
    Write-UiInfo "    当前状态: $(Get-SkillEntryStatusText -Status $beforeStatus)" -Level Detail
    Write-UiInfo "    命令: $preview" -Level Debug

    try {
        $commandResult = Invoke-ExternalCommand `
            -Command "npx" `
            -Arguments $arguments `
            -TimeoutSeconds 600 `
            -RetryCount 1

        if ($commandResult.ExitCode -eq 0) {
            $afterRecords = @(Get-InstalledSkillRecords)
            $afterStatus = Get-SkillEntryInstallStatus -Entry $Entry -InstalledRecords $afterRecords
            $beforeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($record in $beforeRecords) {
                [void]$beforeSet.Add([string]$record["Name"])
            }

            $addedNames = @(
                $afterRecords |
                    Where-Object { -not $beforeSet.Contains([string]$_["Name"]) } |
                    ForEach-Object { [string]$_["Name"] }
            )

            $result.Success = $true
            $result.Data["Command"] = $preview
            $result.Data["AfterState"] = [string]$afterStatus["State"]
            $result.Data["AfterInstalledNames"] = @($afterStatus["InstalledNames"])
            $result.Data["AfterMissingNames"] = @($afterStatus["MissingNames"])
            $result.Data["AddedNames"] = @(Get-UniqueSkillNames -Names $addedNames)

            Write-UiSuccess "  - $entryName ${actionText}成功"
            Write-UiInfo "    安装后状态: $(Get-SkillEntryStatusText -Status $afterStatus)" -Level Detail
            if ($result.Data["AddedNames"].Count -gt 0) {
                Write-UiInfo "    本次新增: $($result.Data['AddedNames'] -join ', ')" -Level Detail
            }
            if ([string]$afterStatus["State"] -eq "Partial") {
                Write-UiWarning "    仍缺失: $(@($afterStatus['MissingNames']) -join ', ')" -Level Detail
            }

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

    Write-UiWarning "  - $entryName ${actionText}失败 [FAIL]: $($result.ErrorMessage)" -Level Detail
    return $result
}

function Install-Skills {
    <#
    .SYNOPSIS
    安装或更新用户选择的 Skills。
    #>
    param()

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        Write-UiPrimary "安装/更新 Skills..." -Level Detail
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

        Write-UiInfo "安装目标: skills CLI 全局 Claude Code scope" -Level Detail
        Write-UiInfo "Agent: claude-code；范围: -g" -Level Detail

        $copyMode = Resolve-SkillsCopyMode
        if ($copyMode) {
            Write-UiInfo "copy 模式: 已启用 (--copy)" -Level Detail
        } else {
            Write-UiInfo "copy 模式: 未启用" -Level Detail
        }

        $selectedEntries = @(Show-SkillsSelectMenu)
        if ($selectedEntries.Count -eq 0) {
            Write-UiWarning "未选择任何 Skills，跳过安装/更新"
            $result.Success = $true
            $result.Data = @{
                SelectedIds         = @()
                InstalledIds        = @()
                UpdatedIds          = @()
                PartialIds          = @()
                SkippedIds          = @()
                FailedIds           = @()
                AddedSkillNames     = @()
                InstalledSkillNames = @()
                MissingSkillNames   = @()
                EntryResults        = @()
                CopyMode            = $copyMode
                SkippedReason       = "no-selection"
            }
            $script:LastSkillsInstallData = $result.Data
            return $result
        }

        $installedIds = @()
        $updatedIds = @()
        $partialIds = @()
        $skippedIds = @()
        $failedIds = @()
        $failedMessages = @()
        $addedSkillNames = @()
        $installedSkillNames = @()
        $missingSkillNames = @()
        $entryResults = @()
        $selectedIds = @($selectedEntries | ForEach-Object { [string]$_["Id"] })

        foreach ($entry in $selectedEntries) {
            $entryResult = Install-SkillEntry -Entry $entry -CopyMode $copyMode
            $entryResults += $entryResult
            if ([bool]$entryResult.Success) {
                if ([bool]$entryResult.Skipped) {
                    $skippedIds += [string]$entryResult.Id
                } else {
                    $afterState = [string]$entryResult.Data["AfterState"]
                    if ($afterState -eq "Partial") {
                        $partialIds += [string]$entryResult.Id
                    }

                    if ([string]$entryResult.Data["WasState"] -eq "NotInstalled" -or [string]$entryResult.Data["WasState"] -eq "Unknown") {
                        $installedIds += [string]$entryResult.Id
                    } else {
                        $updatedIds += [string]$entryResult.Id
                    }

                    $addedSkillNames += @($entryResult.Data["AddedNames"])
                    $installedSkillNames += @($entryResult.Data["AfterInstalledNames"])
                    $missingSkillNames += @($entryResult.Data["AfterMissingNames"])
                }
            } else {
                $failedIds += [string]$entryResult.Id
                $failedMessages += "$($entryResult.Id): $($entryResult.ErrorMessage)"
            }
        }

        $result.Data = @{
            SelectedIds         = @($selectedIds)
            InstalledIds        = @($installedIds)
            UpdatedIds          = @($updatedIds)
            PartialIds          = @($partialIds)
            SkippedIds          = @($skippedIds)
            FailedIds           = @($failedIds)
            AddedSkillNames     = @(Get-UniqueSkillNames -Names $addedSkillNames)
            InstalledSkillNames = @(Get-UniqueSkillNames -Names $installedSkillNames)
            MissingSkillNames   = @(Get-UniqueSkillNames -Names $missingSkillNames)
            EntryResults        = @($entryResults)
            CopyMode            = $copyMode
        }
        $script:LastSkillsInstallData = $result.Data

        if ($failedIds.Count -gt 0) {
            $result.ErrorMessage = "以下 Skills 安装/更新失败: $($failedIds -join ', ')"
            if ($failedMessages.Count -gt 0) {
                $result.ErrorMessage += "`n$($failedMessages -join "`n")"
            }
            return $result
        }

        if ($partialIds.Count -gt 0) {
            Write-UiWarning "以下 Skills 条目仅部分安装: $($partialIds -join ', ')" -Level Detail
        }
        Write-UiSuccess "Skills 安装/更新完成" -Level Detail
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "安装/更新 Skills 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Verify-Skills {
    <#
    .SYNOPSIS
    验证本次成功安装或更新的 Skills。
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

        $changedIds = @()
        if ($installData.ContainsKey("InstalledIds")) {
            $changedIds += @($installData["InstalledIds"])
        }
        if ($installData.ContainsKey("UpdatedIds")) {
            $changedIds += @($installData["UpdatedIds"])
        }
        if ($installData.ContainsKey("PartialIds")) {
            $changedIds += @($installData["PartialIds"])
        }
        $changedIds = @(Get-UniqueSkillNames -Names $changedIds)

        if ($changedIds.Count -eq 0) {
            Write-UiInfo "  - 本次无 Skills 需要验证 [SKIP]" -Level Detail
            $result.Success = $true
            return $result
        }

        $catalogue = @(Get-SkillsCatalogue)
        $entryById = @{}
        foreach ($entry in $catalogue) {
            $entryById[[string]$entry["Id"]] = $entry
        }

        $installedRecords = @(Get-InstalledSkillRecords)
        $changedEntries = @()
        foreach ($id in $changedIds) {
            if ($entryById.ContainsKey([string]$id)) {
                $changedEntries += $entryById[[string]$id]
            }
        }

        $statusItems = @(Resolve-SkillsCatalogueStatuses -Entries $changedEntries -InstalledRecords $installedRecords)
        $failed = @()
        foreach ($item in $statusItems) {
            $entry = $item["Entry"]
            $status = $item["Status"]
            $statusText = Get-SkillEntryStatusText -Status $status
            if ([string]$status["State"] -eq "Installed") {
                Write-UiInfo "  - $([string]$entry['Name']): $statusText" -Level Detail
            } else {
                $missing = @($status["MissingNames"])
                Write-UiInfo "  - $([string]$entry['Name']): $statusText [FAIL]" -Level Detail
                if ($missing.Count -gt 0) {
                    Write-UiInfo "    缺失: $($missing -join ', ')" -Level Detail
                }
                $failed += [string]$entry["Id"]
            }
        }

        if ($failed.Count -gt 0) {
            $result.ErrorMessage = "以下 Skills 验证失败或仅部分安装: $($failed -join ', ')"
            return $result
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "验证 Skills 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Show-SkillsStatusTable {
    <#
    .SYNOPSIS
    显示受控 catalogue 的 Skills 安装状态。
    #>
    param()

    $catalogue = @(Get-SkillsCatalogue)
    $installedRecords = @(Get-InstalledSkillRecords)
    $orderedEntries = @($catalogue | Sort-Object `
        @{ Expression = { [array]::IndexOf($script:SkillsCategoryOrder, [string]$_["Category"]) } },
        @{ Expression = { [string]$_["Name"] } })

    Write-Host ""
    Write-UiPrimary "正在检测 Skills 状态..."
    $statusItems = @(Resolve-SkillsCatalogueStatuses -Entries $orderedEntries -InstalledRecords $installedRecords -ShowProgress)

    Write-Host ""
    Write-UiPrimary "Skills 状态："
    Write-Host ""

    $colWidths = @(16, 8, 24, 40)
    $headerLine = "  " +
        (Format-DisplayPad "状态" $colWidths[0]) + " " +
        (Format-DisplayPad "类别" $colWidths[1]) + " " +
        (Format-DisplayPad "名称" $colWidths[2]) + " " +
        (Format-DisplayPad "已安装 Skill" $colWidths[3])
    Write-UiInfo $headerLine
    $sepWidth = ($colWidths | Measure-Object -Sum).Sum + $colWidths.Count - 1
    Write-UiDim ("  " + [string]::new("-", $sepWidth))

    foreach ($item in $statusItems) {
        $entry = $item["Entry"]
        $status = $item["Status"]
        $statusText = Get-SkillEntryStatusText -Status $status
        $installedNames = @($status["InstalledNames"])
        $matchedNames = if ($installedNames.Count -gt 0) {
            $installedNames -join ", "
        } else {
            "-"
        }
        if ($matchedNames.Length -gt $colWidths[3]) {
            $matchedNames = $matchedNames.Substring(0, $colWidths[3] - 3) + "..."
        }

        $color = Get-SkillEntryStatusColor -Status $status
        $line = "  " +
            (Format-DisplayPad $statusText $colWidths[0]) + " " +
            (Format-DisplayPad ([string]$entry["Category"]) $colWidths[1]) + " " +
            (Format-DisplayPad ([string]$entry["Name"]) $colWidths[2]) + " " +
            (Format-DisplayPad $matchedNames $colWidths[3])
        Write-UiOutput $line -Type $color
    }

    $knownNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $statusItems) {
        $status = $item["Status"]
        foreach ($name in @($status["DiscoveredNames"])) {
            [void]$knownNames.Add([string]$name)
        }
    }

    $unknownRecords = @()
    foreach ($record in $installedRecords) {
        if (-not $knownNames.Contains([string]$record["Name"])) {
            $unknownRecords += $record
        }
    }

    if ($unknownRecords.Count -gt 0) {
        Write-Host ""
        $unknownNames = @($unknownRecords | ForEach-Object { [string]$_["Name"] })
        Write-UiDim "未纳入 catalogue 的已安装 Skills：$($unknownNames -join ', ')"
    }
    Write-Host ""
}

function Show-SkillsUninstallMenu {
    <#
    .SYNOPSIS
    选择要卸载的 Skills catalogue 条目。
    #>
    param()

    $catalogue = @(Get-SkillsCatalogue)
    $installedRecords = @(Get-InstalledSkillRecords)
    $orderedEntries = @($catalogue | Sort-Object `
        @{ Expression = { [array]::IndexOf($script:SkillsCategoryOrder, [string]$_["Category"]) } },
        @{ Expression = { [string]$_["Name"] } })

    Write-UiPrimary "正在检测可卸载 Skills..."
    $statusItems = @(Resolve-SkillsCatalogueStatuses -Entries $orderedEntries -InstalledRecords $installedRecords -ShowProgress)
    $installedEntries = @()

    foreach ($item in $statusItems) {
        $status = $item["Status"]
        if ([int]$status["InstalledCount"] -gt 0) {
            $installedEntries += $item
        }
    }

    if ($installedEntries.Count -eq 0) {
        Write-UiWarning "未检测到可卸载的 Skills"
        return @()
    }

    $ordered = @($installedEntries | Sort-Object `
        @{ Expression = { $entry = $_["Entry"]; [array]::IndexOf($script:SkillsCategoryOrder, [string]$entry["Category"]) } },
        @{ Expression = { $entry = $_["Entry"]; [string]$entry["Name"] } })

    $options = [System.Collections.Generic.List[string]]::new()
    $entryMap = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($item in $ordered) {
        $entry = $item["Entry"]
        $status = $item["Status"]
        $statusText = Get-SkillEntryStatusText -Status $status
        $matchedNames = (@($status["InstalledNames"]) -join ", ")
        [void]$options.Add("$([string]$entry['Category']) / $([string]$entry['Name'])（$statusText；将卸载: $matchedNames）")
        [void]$entryMap.Add($entry)
    }

    $selectedRaw = Show-MultiSelectMenu `
        -Title "Skills - 选择要卸载的 Skills" `
        -Options ([string[]]$options.ToArray()) `
        -DefaultSelected @()

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

function Uninstall-SkillEntry {
    <#
    .SYNOPSIS
    通过 skills CLI 卸载单个 catalogue 条目对应的已安装 Skill。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    $entryId = [string]$Entry["Id"]
    $entryName = [string]$Entry["Name"]
    $result = @{
        Success      = $false
        Id           = $entryId
        Name         = $entryName
        RemovedNames = @()
        FailedNames  = @()
        ErrorMessage = ""
        ErrorDetails = ""
    }

    $status = Get-SkillEntryInstallStatus -Entry $Entry
    $skillNames = @($status["InstalledNames"])
    if ($skillNames.Count -eq 0) {
        Write-UiInfo "  - $entryName 未安装，跳过 [SKIP]" -Level Detail
        $result.Success = $true
        return $result
    }

    $arguments = @(Build-SkillsRemoveArguments -SkillNames ([string[]]$skillNames))
    $preview = "npx $($arguments -join ' ')"
    Write-UiPrimary "  - 正在卸载 $entryName" -Level Detail
    Write-UiInfo "    目标 Skills: $($skillNames -join ', ')" -Level Detail
    Write-UiInfo "    命令: $preview" -Level Debug

    try {
        $commandResult = Invoke-ExternalCommand `
            -Command "npx" `
            -Arguments $arguments `
            -SuppressOutput `
            -TimeoutSeconds 300 `
            -RetryCount 0

        if ($commandResult.Success) {
            $afterStatus = Get-SkillEntryInstallStatus -Entry $Entry
            $remainingNames = @($afterStatus["InstalledNames"])
            if ($remainingNames.Count -eq 0) {
                $result.RemovedNames = @($skillNames)
                $result.Success = $true
                Write-UiSuccess "  - $entryName 卸载完成" -Level Detail
                return $result
            }

            $removedNames = @($skillNames | Where-Object { $remainingNames -notcontains $_ })
            $result.RemovedNames = @($removedNames)
            $result.FailedNames = @($remainingNames)
            $result.ErrorMessage = "以下 Skills 卸载后仍被检测到: $($remainingNames -join ', ')"
            return $result
        }

        $errorText = $commandResult.Error
        if ([string]::IsNullOrWhiteSpace($errorText)) {
            $errorText = $commandResult.Output
        }
        $result.FailedNames = @($skillNames)
        $result.ErrorMessage = Get-SkillsInstallFriendlyError -ExitCode $commandResult.ExitCode -ErrorText $errorText
        $result.ErrorDetails = $errorText
    }
    catch {
        $result.FailedNames = @($skillNames)
        $result.ErrorMessage = "卸载 $entryName 失败: $($_.Exception.Message)"
        $result.ErrorDetails = $_.Exception.Message
    }

    Write-UiWarning "  - $entryName 卸载失败 [FAIL]: $($result.ErrorMessage)" -Level Detail
    return $result
}

function Uninstall-Skills {
    <#
    .SYNOPSIS
    卸载用户选择的 Skills。
    #>
    param()

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        $selectedEntries = @(Show-SkillsUninstallMenu)
        if ($selectedEntries.Count -eq 0) {
            Write-UiWarning "未选择任何 Skills，跳过卸载"
            $result.Success = $true
            $result.Data = @{ RemovedNames = @(); FailedNames = @() }
            return $result
        }

        Write-Host ""
        Write-UiWarning "将通过 skills CLI 卸载选中的全局 Claude Code Skills"
        $confirm = Show-SingleSelectMenu `
            -Title "确认卸载选中的 Skills？" `
            -Options @("是，卸载", "否，取消") `
            -DefaultIndex 1

        if ($confirm -ne 0) {
            Write-UiDim "已取消卸载"
            $result.Success = $true
            $result.Data = @{ RemovedNames = @(); FailedNames = @(); SkippedReason = "cancelled" }
            return $result
        }

        $removedNames = @()
        $failedNames = @()
        foreach ($entry in $selectedEntries) {
            $entryResult = Uninstall-SkillEntry -Entry $entry
            $removedNames += @($entryResult.RemovedNames)
            $failedNames += @($entryResult.FailedNames)
        }

        $result.Data = @{
            RemovedNames = @($removedNames)
            FailedNames  = @($failedNames)
        }

        if ($failedNames.Count -gt 0) {
            $result.ErrorMessage = "以下 Skills 卸载失败: $($failedNames -join ', ')"
            return $result
        }

        Write-UiSuccess "Skills 卸载完成"
        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "卸载 Skills 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Show-SkillsManageMenu {
    <#
    .SYNOPSIS
    Skills 管理菜单：查看状态、安装/更新、卸载。
    #>
    param()

    while ($true) {
        Show-SkillsStatusTable

        $choice = Show-SingleSelectMenu `
            -Title "Skills 管理" `
            -Options @(
                "安装/更新 Skills（已安装项可选中重复安装）",
                "卸载 Skills",
                "返回"
            ) `
            -DefaultIndex 0

        if ($choice -eq -1 -or $choice -eq 2) {
            return
        }

        switch ($choice) {
            0 {
                $installResult = Install-Skills
                if (-not [bool]$installResult.Success) {
                    Write-UiWarning $installResult.ErrorMessage
                }
            }
            1 {
                $uninstallResult = Uninstall-Skills
                if (-not [bool]$uninstallResult.Success) {
                    Write-UiWarning $uninstallResult.ErrorMessage
                }
            }
        }

        Write-Host ""
        Write-UiDim "按任意键返回 Skills 管理..."
        $null = [Console]::ReadKey($true)
    }
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
