# CCG Workflow 安装步骤 - CCQ
# 作者: 哈雷酱 (本小姐的专业工作流管理！)
# 功能: 通过官方 npx ccg-workflow@latest init 安装 CCG Workflow

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 依赖: Ui.ps1, Process.ps1, Profile.ps1（由入口脚本 dot-source 加载）

# CCG Workflow 安装目录
$script:ClaudeDir = "$(Get-UserHome)\.claude"

# CcgWorkflow 负责的 env 默认值（仅补齐缺失项，不覆盖已有配置）
$script:CcgWorkflowEnvDefaults = @{
    "CODEAGENT_POST_MESSAGE_DELAY" = "1"
    "CODEX_TIMEOUT"                = "7200"
    "BASH_DEFAULT_TIMEOUT_MS"      = "600000"
    "BASH_MAX_TIMEOUT_MS"          = "3600000"
}

# CCG 旧规则文件已并入 ClaudeMd 主模板；此步骤只负责清理历史生成物
$script:CcgWorkflowManagedRuleFiles = @(
    "ccq-ccgworkflow.md",
    "ccq-multimodel.md",
    "ccq-tools.md",
    "ccq-workflow.md"
)

function Get-CcgWorkflowFingerprint {
    <#
    .SYNOPSIS
    计算 CcgWorkflow 步骤的组合内容指纹（引擎版本 + 历史规则清理清单）
    .DESCRIPTION
    组合指纹确保引擎版本变更、历史规则清理清单变更或 env 默认值变更都能触发更新检测。
    引擎版本统一从 config.toml 读取（与 Get-CcgWorkflowUpdateComponents 保持一致）。
    .RETURNS
    string - 组合指纹字符串，或空字符串（未安装时）
    #>
    $parts = @()

    # 引擎版本分量（统一从 config.toml 读取，与分量检测保持 single source of truth）
    $configToml = "$script:ClaudeDir\.ccg\config.toml"
    $engineVersion = "unknown"
    if (Test-Path $configToml) {
        $content = Get-Content $configToml -Raw -ErrorAction SilentlyContinue
        if ($content -match 'version\s*=\s*"([^"]+)"') {
            $engineVersion = $matches[1]
        }
    }
    $parts += "engine:$engineVersion"

    # 规则清理分量
    $parts += "rules-cleanup:" + ($script:CcgWorkflowManagedRuleFiles -join ",")

    # env 默认值分量
    $envParts = @()
    foreach ($key in ($script:CcgWorkflowEnvDefaults.Keys | Sort-Object)) {
        $envParts += "${key}=$($script:CcgWorkflowEnvDefaults[$key])"
    }
    $parts += "env:" + ($envParts -join ",")

    return Get-StringFingerprint -Text ($parts -join "`n")
}

function Get-CcgWorkflowUpdateComponents {
    <#
    .SYNOPSIS
    独立检测 CcgWorkflow 的引擎版本、历史规则文件清理状态与 env 漂移状态
    .DESCRIPTION
    拆分检测引擎（npm 版本）、历史规则文件清理和 env 三个分量，
    使 Get-UpdateStatus 和 Update-CcgWorkflow 能精准区分更新类型。
    .PARAMETER LatestVersion
    可选：预查询的 npm 最新版本（避免重复查询）
    .RETURNS
    hashtable — EngineNeedUpdate, RulesNeedUpdate, UpdateKind, StatusHint, LocalVersion, LatestVersion
    #>
    param(
        [string]$LatestVersion = ""
    )

    $result = @{
        EngineNeedUpdate = $false
        RulesNeedUpdate  = $false
        EnvNeedUpdate    = $false
        UpdateKind       = "none"
        StatusHint       = "已是最新"
        LocalVersion     = ""
        LatestVersion    = ""
    }

    # ── 引擎分量：config.toml 本地版本 vs npm 最新版本 ──
    $configToml = "$script:ClaudeDir\.ccg\config.toml"
    if (Test-Path $configToml) {
        $content = Get-Content $configToml -Raw -ErrorAction SilentlyContinue
        if ($content -match 'version\s*=\s*"([^"]+)"') {
            $result.LocalVersion = $matches[1]
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LatestVersion)) {
        $result.LatestVersion = $LatestVersion
    } else {
        $updateCheck = Test-NpmUpdateAvailable -PackageName "ccg-workflow" -CurrentVersion $result.LocalVersion -NonGlobal
        if ($updateCheck.LatestVersion) {
            $result.LatestVersion = $updateCheck.LatestVersion
        }
    }

    if ($result.LocalVersion -and $result.LatestVersion -and $result.LocalVersion -ne $result.LatestVersion) {
        $result.EngineNeedUpdate = $true
    }
    elseif (-not $result.LocalVersion -and $result.LatestVersion) {
        # 已安装但本地版本不可读（config.toml 损坏/缺失）→ 保守触发引擎更新
        $result.EngineNeedUpdate = $true
    }

    # ── 规则分量：历史规则文件清理 ──
    $rulesDir = "$script:ClaudeDir\rules"
    $managedRulesExist = $false
    foreach ($f in $script:CcgWorkflowManagedRuleFiles) {
        if (Test-Path (Join-Path $rulesDir $f)) {
            $managedRulesExist = $true
            break
        }
    }

    if ($managedRulesExist) {
        $result.RulesNeedUpdate = $true
    }

    # ── env 分量：settings.json env 键值对比 ──
    $settingsPath = "$script:ClaudeDir\settings.json"
    if (Test-Path $settingsPath) {
        try {
            $settingsRaw = Get-Content $settingsPath -Raw
            $settings = $settingsRaw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
            if ($settings -and $settings.ContainsKey("env")) {
                foreach ($entry in $script:CcgWorkflowEnvDefaults.GetEnumerator()) {
                    if (-not $settings["env"].ContainsKey($entry.Key) -or
                        $settings["env"][$entry.Key] -cne $entry.Value) {
                        $result.EnvNeedUpdate = $true
                        break
                    }
                }
            } else {
                $result.EnvNeedUpdate = $true
            }
        } catch {
            $result.EnvNeedUpdate = $true
        }
    } else {
        $result.EnvNeedUpdate = $true
    }

    # ── 综合判定 ──
    # env 变更沿用 rules-only 更新通道；RulesNeedUpdate 仅表示需要清理历史规则文件
    $rulesOrEnvNeedUpdate = $result.RulesNeedUpdate -or $result.EnvNeedUpdate
    if ($result.EngineNeedUpdate -and $rulesOrEnvNeedUpdate) {
        $result.UpdateKind = "engine+rules"
        $result.StatusHint = "引擎与规则/env 均需更新"
    } elseif ($result.EngineNeedUpdate) {
        $result.UpdateKind = "engine-only"
        if (-not $result.LocalVersion) {
            $result.StatusHint = "引擎版本不可读，建议重新安装"
        } else {
            $result.StatusHint = "引擎版本可更新 ($($result.LocalVersion) -> $($result.LatestVersion))"
        }
    } elseif ($rulesOrEnvNeedUpdate) {
        $result.UpdateKind = "rules-only"
        if ($result.RulesNeedUpdate -and $result.EnvNeedUpdate) {
            $result.StatusHint = "历史规则文件清理与 env 配置更新"
        } elseif ($result.EnvNeedUpdate) {
            $result.StatusHint = "env 配置更新"
        } else {
            $result.StatusHint = "历史规则文件清理"
        }
    }

    return $result
}

function Test-CcgWorkflowInstalled {
    <#
    .SYNOPSIS
    检测 CCG Workflow 是否已安装（基于官方目录结构判定）
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>

    $claudeDir = $script:ClaudeDir
    return Invoke-UnifiedCheck -StepId "CcgWorkflow" -DisplayName "CCG Workflow" `
        -PathChecks @(
            @{ Path = "$claudeDir\commands\ccg"; Type = "Dir"; Filter = "*.md"; MinCount = 20 },
            @{ Path = "$claudeDir\agents\ccg"; Type = "Dir" },
            @{ Path = "$claudeDir\.ccg"; Type = "Dir" },
            @{ Path = "$claudeDir\bin\codeagent-wrapper.exe"; Type = "File" }
        ) `
        -CustomVerify {
            # 从 config.toml 提取版本
            $configToml = "$claudeDir\.ccg\config.toml"
            if (Test-Path $configToml) {
                $content = Get-Content $configToml -Raw -ErrorAction SilentlyContinue
                if ($content -match 'version\s*=\s*"([^"]+)"') {
                    return $matches[1]
                }
            }
            return $true
        } -UseCache
}

function Install-CcgWorkflow {
    <#
    .SYNOPSIS
    通过官方 npx ccg-workflow@latest init 安装 CCG Workflow
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
        Data         = @{}
    }

    try {
        Write-UiPrimary "安装 CCG Workflow (官方初始化方式)..." -Level Detail

        # ── 前置检查 ──
        Refresh-SessionPath

        # 验证 Node.js
        $nodeDetails = Test-CommandAvailable -Command "node" -ReturnDetails
        if (-not $nodeDetails.Available) {
            $errorMsg = "未找到 node 命令，请检查 Node.js 安装 (NodeJS)"
            if ($nodeDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($nodeDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        # 验证 npm
        $npmDetails = Test-CommandAvailable -Command "npm" -ReturnDetails
        if (-not $npmDetails.Available) {
            $errorMsg = "未找到 npm 命令，请检查 Node.js 安装 (NodeJS)"
            if ($npmDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($npmDetails.ResolvedPath)"
            }
            if ($npmDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($npmDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        # 验证 npx
        $npxDetails = Test-CommandAvailable -Command "npx" -ReturnDetails
        if (-not $npxDetails.Available) {
            $errorMsg = "未找到 npx 命令，请检查 Node.js 安装 (NodeJS)"
            if ($npxDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($npxDetails.ResolvedPath)"
            }
            if ($npxDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($npxDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        Write-UiSuccess "环境检查: Node.js & npm 已就绪" -Level Detail

        # ── MCP 快照（安装前）──
        # mcpServers 配置在 ~/.claude.json，不在 settings.json
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"
        $mcpSnapshotBefore = $null
        if (Test-Path $claudeJsonPath) {
            $claudeJsonRaw = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
            if ($claudeJsonRaw) {
                $claudeJson = $claudeJsonRaw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($null -ne $claudeJson -and $claudeJson.ContainsKey("mcpServers")) {
                    $mcpSnapshotBefore = $claudeJson["mcpServers"] | ConvertTo-Json -Depth 10 -ErrorAction SilentlyContinue
                }
            }
        }

        # ── 执行 npx 官方初始化 ──
        Write-UiPrimary "正在通过 npx 获取最新版 CCG Workflow 引擎..." -Level Detail
        Write-UiPrimary "正在执行官方初始化 (此过程涉及远程下载，请稍候)..." -Level Detail

        $npxResult = Invoke-ExternalCommand `
            -Command "npx" `
            -Arguments @("--yes", "ccg-workflow@latest", "init", "--skip-prompt", "--skip-mcp", "--lang", "zh-CN", "--install-dir", "$script:ClaudeDir") `
            -TimeoutSeconds 300 `
            -RetryCount 3

        if ($npxResult.ExitCode -ne 0) {
            $errorDetail = $npxResult.Error
            if ([string]::IsNullOrWhiteSpace($errorDetail)) {
                $errorDetail = $npxResult.Output
            }

            # 根据错误类型提供友好提示
            if ($errorDetail -match "ETIMEDOUT|ECONNREFUSED|ENOTFOUND|network") {
                throw "无法访问 npm 仓库，请检查网络连接或设置 npm 代理镜像`n详细信息: $errorDetail"
            }
            elseif ($errorDetail -match "EACCES|EPERM|permission") {
                throw "无法在用户目录创建文件，请检查目录权限`n详细信息: $errorDetail"
            }
            else {
                throw "CCG Workflow 初始化失败 (ExitCode: $($npxResult.ExitCode))`n详细信息: $errorDetail"
            }
        }

        Write-UiSuccess "成功部署 CCG 目录结构与配置文件" -Level Detail

        # ── 清理历史 CCG 规则文件（相关原则已并入 ClaudeMd 主模板）──
        $rulesDir = "$script:ClaudeDir\rules"
        if (Test-Path $rulesDir) {
            foreach ($ruleFile in $script:CcgWorkflowManagedRuleFiles) {
                $rulePath = Join-Path $rulesDir $ruleFile
                if (Test-Path $rulePath) {
                    try {
                        Remove-Item $rulePath -Force -ErrorAction Stop
                        Write-UiInfo "已清理历史规则文件: rules/$ruleFile" -Level Detail
                    } catch {
                        Write-UiWarning "无法清理历史规则文件: rules/$ruleFile" -Level Debug
                    }
                }
            }
        }

        # ── 写入 CCG env 配置到 settings.json ──
        Write-UiPrimary "配置 CCG Workflow 环境变量..." -Level Detail
        $settingsPath = "$script:ClaudeDir\settings.json"
        $envSettings = @{}

        if (Test-Path $settingsPath) {
            try {
                $existingContent = Get-Content $settingsPath -Raw
                $envSettings = $existingContent | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if (-not $envSettings) { $envSettings = @{} }
            } catch {
                Write-UiWarning "无法解析 settings.json，跳过 env 配置（不影响主安装）" -Level Debug
                $envSettings = $null
            }
        }

        if ($null -ne $envSettings) {
            if (-not $envSettings.ContainsKey("env")) {
                $envSettings["env"] = @{}
            }

            $envAdded = 0
            foreach ($entry in $script:CcgWorkflowEnvDefaults.GetEnumerator()) {
                if (-not $envSettings["env"].ContainsKey($entry.Key)) {
                    $envSettings["env"][$entry.Key] = $entry.Value
                    $envAdded++
                }
            }

            if ($envAdded -gt 0) {
                $tempPath = "$settingsPath.tmp_$([guid]::NewGuid().ToString('N').Substring(0,8))"
                $envSettings | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
                Move-Item $tempPath $settingsPath -Force
                Write-UiInfo "已写入 $envAdded 个 CCG 环境变量到 settings.json" -Level Detail
            } else {
                Write-UiInfo "CCG 环境变量已存在，跳过写入" -Level Detail
            }
        }

        # ── MCP 快照（安装后比对）──
        if ($null -ne $mcpSnapshotBefore -and (Test-Path $claudeJsonPath)) {
            $claudeJsonRawAfter = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
            if ($claudeJsonRawAfter) {
                $claudeJsonAfter = $claudeJsonRawAfter | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($null -ne $claudeJsonAfter -and $claudeJsonAfter.ContainsKey("mcpServers")) {
                    $mcpSnapshotAfter = $claudeJsonAfter["mcpServers"] | ConvertTo-Json -Depth 10 -ErrorAction SilentlyContinue
                    if ($mcpSnapshotBefore -ne $mcpSnapshotAfter) {
                        Write-UiWarning "检测到 .claude.json 中的 mcpServers 配置在安装过程中被修改，请手动检查" -Level Detail
                    }
                }
            }
        }

        # ── 刷新 PATH ──
        Write-UiPrimary "正在刷新环境变量..." -Level Detail
        Refresh-SessionPath

        # ── 提取版本号 ──
        $configToml = "$script:ClaudeDir\.ccg\config.toml"
        if (Test-Path $configToml) {
            $configContent = Get-Content $configToml -Raw -ErrorAction SilentlyContinue
            if ($configContent -match 'version\s*=\s*"([^"]+)"') {
                $result.Data["Version"] = $matches[1]
            }
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiDanger "安装 CCG Workflow 失败: $($result.ErrorMessage)"
    }

    return $result
}

function Verify-CcgWorkflow {
    <#
    .SYNOPSIS
    验证 CCG Workflow 安装结果
    .RETURNS
    包含 Success 字段的结果对象
    #>

    $result = @{
        Success      = $false
        ErrorMessage = ""
    }

    try {
        $allPassed = $true

        # ── 文件结构验证 ──

        # 命令模板验证
        $commandsDir = "$script:ClaudeDir\commands\ccg"
        $commandFiles = Get-ChildItem $commandsDir -Filter "*.md" -ErrorAction SilentlyContinue
        $commandCount = if ($null -ne $commandFiles) { $commandFiles.Count } else { 0 }
        if ($commandCount -ge 20) {
            Write-UiInfo "  - 命令模板: 已安装 $commandCount 个 [PASS]" -Level Detail
        }
        else {
            Write-UiInfo "  - 命令模板: 仅 $commandCount 个 (期望 >= 20) [FAIL]" -Level Detail
            $allPassed = $false
        }

        # Agent 模板验证
        $agentsDir = "$script:ClaudeDir\agents\ccg"
        $agentFiles = Get-ChildItem $agentsDir -Filter "*.md" -ErrorAction SilentlyContinue
        $agentCount = if ($null -ne $agentFiles) { $agentFiles.Count } else { 0 }
        if ($agentCount -ge 4) {
            Write-UiInfo "  - Agent 模板: 已安装 $agentCount 个 [PASS]" -Level Detail
        }
        else {
            Write-UiInfo "  - Agent 模板: 仅 $agentCount 个 (期望 >= 4) [FAIL]" -Level Detail
            $allPassed = $false
        }

        # 配置文件验证 + 包版本提取
        $configToml = "$script:ClaudeDir\.ccg\config.toml"
        if (Test-Path $configToml) {
            $configContent = Get-Content $configToml -Raw -ErrorAction SilentlyContinue
            $pkgVersion = ""
            if ($configContent -match 'version\s*=\s*"([^"]+)"') {
                $pkgVersion = $matches[1]
            }
            if ($pkgVersion) {
                Write-UiInfo "  - 配置文件: config.toml 存在, ccg-workflow v$pkgVersion [PASS]" -Level Detail
            }
            else {
                Write-UiInfo "  - 配置文件: config.toml 存在 [PASS]" -Level Detail
            }
        }
        else {
            Write-UiInfo "  - 配置文件: config.toml 不存在 [FAIL]" -Level Detail
            $allPassed = $false
        }

        # 二进制文件验证
        $wrapperExe = "$script:ClaudeDir\bin\codeagent-wrapper.exe"
        $wrapperVersion = ""
        if (Test-Path $wrapperExe) {
            # 尝试获取版本号
            $versionResult = Invoke-ExternalCommand `
                -Command $wrapperExe `
                -Arguments @("--version") `
                -TimeoutSeconds 10 `
                -RetryCount 0 `
                -SuppressOutput
            if ($versionResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($versionResult.Output)) {
                $wrapperVersion = $versionResult.Output.Trim()
            }
            Write-UiInfo "  - 二进制文件: codeagent-wrapper $wrapperVersion [PASS]" -Level Detail
        }
        else {
            Write-UiInfo "  - 二进制文件: codeagent-wrapper.exe 不存在 [FAIL]" -Level Detail
            $allPassed = $false
        }

        # 会话可用性验证
        if (Test-CommandAvailable -Command "codeagent-wrapper") {
            Write-UiInfo "  - PATH 可用性: codeagent-wrapper 在 PATH 中 [PASS]" -Level Detail
        }
        else {
            Write-UiWarning "  - PATH 可用性: codeagent-wrapper 不在 PATH 中 (可能需要重启终端) [SKIP]" -Level Detail
        }

        # ── env 配置验证 ──
        $settingsPath = "$script:ClaudeDir\settings.json"
        if (Test-Path $settingsPath) {
            try {
                $settingsRaw = Get-Content $settingsPath -Raw
                $settingsObj = $settingsRaw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($settingsObj -and $settingsObj.ContainsKey("env")) {
                    $missingEnvKeys = @()
                    foreach ($key in $script:CcgWorkflowEnvDefaults.Keys) {
                        if (-not $settingsObj["env"].ContainsKey($key) -or
                            [string]::IsNullOrWhiteSpace([string]$settingsObj["env"][$key])) {
                            $missingEnvKeys += $key
                        }
                    }
                    if ($missingEnvKeys.Count -eq 0) {
                        Write-UiInfo "  - CCG 环境变量: $($script:CcgWorkflowEnvDefaults.Count) 项已配置 [PASS]" -Level Detail
                    } else {
                        Write-UiInfo "  - CCG 环境变量: 缺少 $($missingEnvKeys -join ', ') [FAIL]" -Level Detail
                        $allPassed = $false
                    }
                } else {
                    Write-UiInfo "  - CCG 环境变量: settings.json 无 env 节 [FAIL]" -Level Detail
                    $allPassed = $false
                }
            } catch {
                Write-UiInfo "  - CCG 环境变量: 读取 settings.json 失败 [SKIP]" -Level Detail
            }
        } else {
            Write-UiInfo "  - CCG 环境变量: settings.json 不存在 [SKIP]" -Level Detail
        }

        # ── MCP 保护验证 ──
        # mcpServers 配置在 ~/.claude.json，不在 settings.json
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"
        if (Test-Path $claudeJsonPath) {
            $claudeJsonRaw = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
            if ($claudeJsonRaw) {
                $claudeJson = $claudeJsonRaw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($null -ne $claudeJson -and $claudeJson.ContainsKey("mcpServers")) {
                    Write-UiInfo "  - MCP 配置: 未被覆盖 [PASS]" -Level Detail
                }
                else {
                    Write-UiInfo "  - MCP 配置: mcpServers 字段不存在 [SKIP]" -Level Detail
                }
            }
            else {
                Write-UiInfo "  - MCP 配置: .claude.json 为空 [SKIP]" -Level Detail
            }
        }
        else {
            Write-UiInfo "  - MCP 配置: .claude.json 不存在 [SKIP]" -Level Detail
        }

        # ── 最终判定 ──
        if ($allPassed) {
            Write-UiSuccess "CCG Workflow 验证通过" -Level Detail
            $result.Success = $true
        }
        else {
            $result.ErrorMessage = "CCG Workflow 部分验证项未通过，请检查上方详细信息"
        }
    }
    catch {
        $result.ErrorMessage = "验证 CCG Workflow 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

function Update-CcgWorkflow {
    <#
    .SYNOPSIS
    更新 CCG Workflow（支持引擎/规则分量独立更新）
    .DESCRIPTION
    拆分为引擎更新（npx init）和规则更新（文件同步+旧文件迁移）两个独立分支。
    "仅规则更新"场景不再提前 noop。
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
        Write-UiPrimary "更新 CCG Workflow..." -Level Detail

        # 前置检查
        Refresh-SessionPath

        $npxDetails = Test-CommandAvailable -Command "npx" -ReturnDetails
        if (-not $npxDetails.Available) {
            throw "npx 不可用，请检查 Node.js 安装"
        }

        # ── 分量检测 ──
        $components = Get-CcgWorkflowUpdateComponents
        $oldVersion = if ($components.LocalVersion) { $components.LocalVersion } else { "未知" }
        $result.Data["OldVersion"] = $oldVersion
        $result.Data["UpdateKind"] = $components.UpdateKind

        Write-UiInfo "当前版本: $oldVersion" -Level Detail
        if ($components.LatestVersion) {
            Write-UiInfo "最新版本: $($components.LatestVersion)" -Level Detail
        }

        # ── 无更新 → noop ──
        if (-not $components.EngineNeedUpdate -and -not $components.RulesNeedUpdate -and -not $components.EnvNeedUpdate) {
            Write-UiInfo "CCG Workflow 已是最新（引擎/规则/env 均无变更）" -Level Detail
            $result.UpdatedItems = @("noop::CcgWorkflow::no-change")
            $result.Data["NewVersion"] = $oldVersion
            $result.Success = $true
            return $result
        }

        Write-UiInfo "更新类型: $($components.StatusHint)" -Level Detail

        # ── 引擎更新分支 ──
        if ($components.EngineNeedUpdate) {
            # MCP 快照（更新前）— HC-U1 保护
            $claudeJsonPath = "$(Get-UserHome)\.claude.json"
            $mcpSnapshotBefore = $null
            if (Test-Path $claudeJsonPath) {
                $claudeJsonRaw = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
                if ($claudeJsonRaw) {
                    $claudeJson = $claudeJsonRaw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                    if ($null -ne $claudeJson -and $claudeJson.ContainsKey("mcpServers")) {
                        $mcpSnapshotBefore = $claudeJson["mcpServers"] | ConvertTo-Json -Depth 10 -ErrorAction SilentlyContinue
                    }
                }
            }

            # 执行 npx ccg-workflow@latest init（--skip-mcp 必须保留）
            Write-UiPrimary "正在通过 npx 获取最新版 CCG Workflow..." -Level Detail
            $npxResult = Invoke-ExternalCommand `
                -Command "npx" `
                -Arguments @("--yes", "ccg-workflow@latest", "init", "--skip-prompt", "--skip-mcp", "--lang", "zh-CN", "--install-dir", "$script:ClaudeDir") `
                -TimeoutSeconds 300 `
                -RetryCount 3

            if ($npxResult.ExitCode -ne 0) {
                $errorDetail = $npxResult.Error
                if ([string]::IsNullOrWhiteSpace($errorDetail)) {
                    $errorDetail = $npxResult.Output
                }
                throw "CCG Workflow 引擎更新失败 (ExitCode: $($npxResult.ExitCode)): $errorDetail"
            }

            # MCP 快照比对（更新后）
            if ($null -ne $mcpSnapshotBefore -and (Test-Path $claudeJsonPath)) {
                $claudeJsonRawAfter = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
                if ($claudeJsonRawAfter) {
                    $claudeJsonAfter = $claudeJsonRawAfter | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                    if ($null -ne $claudeJsonAfter -and $claudeJsonAfter.ContainsKey("mcpServers")) {
                        $mcpSnapshotAfter = $claudeJsonAfter["mcpServers"] | ConvertTo-Json -Depth 10 -ErrorAction SilentlyContinue
                        if ($mcpSnapshotBefore -ne $mcpSnapshotAfter) {
                            Write-UiWarning "检测到 .claude.json 中的 mcpServers 在更新过程中被修改，请手动检查" -Level Detail
                        }
                    }
                }
            }

            # 刷新 PATH + 获取新版本
            Refresh-SessionPath

            $configToml = "$script:ClaudeDir\.ccg\config.toml"
            $newVersion = ""
            if (Test-Path $configToml) {
                $configContentAfter = Get-Content $configToml -Raw -ErrorAction SilentlyContinue
                if ($configContentAfter -match 'version\s*=\s*"([^"]+)"') {
                    $newVersion = $matches[1]
                }
            }
            if ([string]::IsNullOrWhiteSpace($newVersion)) {
                $newVersion = "未知"
            }

            $result.Data["NewVersion"] = $newVersion

            if ($oldVersion -ne $newVersion) {
                $result.UpdatedItems += "npx::ccg-workflow::${oldVersion}->${newVersion}"
                Write-UiSuccess "CCG Workflow 引擎已更新: $oldVersion -> $newVersion" -Level Detail
            } else {
                $result.UpdatedItems += "npx::ccg-workflow::reinstalled"
                Write-UiInfo "CCG Workflow 引擎已重新安装 ($newVersion)" -Level Detail
            }
        } else {
            $result.Data["NewVersion"] = $oldVersion
        }

        # ── 规则清理分支 ──
        if ($components.RulesNeedUpdate) {
            $rulesDir = "$script:ClaudeDir\rules"
            if (Test-Path $rulesDir) {
                foreach ($ruleFile in $script:CcgWorkflowManagedRuleFiles) {
                    $rulePath = Join-Path $rulesDir $ruleFile
                    if (Test-Path $rulePath) {
                        try {
                            Remove-Item $rulePath -Force -ErrorAction Stop
                            $result.UpdatedItems += "file::rules/${ruleFile}::deleted"
                            Write-UiInfo "已删除历史规则文件: rules/$ruleFile（规则已并入 CLAUDE.md）" -Level Detail
                        } catch {
                            Write-UiWarning "无法删除历史规则文件: rules/$ruleFile" -Level Debug
                        }
                    }
                }
            }
        }

        # ── env 对齐分支 ──
        if ($components.EnvNeedUpdate) {
            $settingsPath = "$script:ClaudeDir\settings.json"
            if (Test-Path $settingsPath) {
                $settingsRaw = Get-Content $settingsPath -Raw
                $settings = $settingsRaw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                if (-not $settings) { throw "settings.json 无法解析" }

                if (-not $settings.ContainsKey("env")) {
                    $settings["env"] = @{}
                }

                foreach ($entry in $script:CcgWorkflowEnvDefaults.GetEnumerator()) {
                    $key = $entry.Key
                    if (-not $settings["env"].ContainsKey($key)) {
                        $settings["env"][$key] = $entry.Value
                        $result.UpdatedItems += "config::env.${key}::added"
                    } elseif ($settings["env"][$key] -cne $entry.Value) {
                        $oldVal = $settings["env"][$key]
                        $settings["env"][$key] = $entry.Value
                        $result.UpdatedItems += "config::env.${key}::${oldVal}->$($entry.Value)"
                    }
                }

                # 原子写入
                $tempPath = "$settingsPath.tmp_$([guid]::NewGuid().ToString('N').Substring(0,8))"
                $settings | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
                for ($retry = 0; $retry -lt 3; $retry++) {
                    try {
                        Move-Item $tempPath $settingsPath -Force
                        break
                    } catch {
                        if ($retry -eq 2) { throw }
                        Start-Sleep -Seconds ([math]::Pow(2, $retry))
                    }
                }

                Write-UiSuccess "CCG Workflow env 配置已对齐" -Level Detail
            } else {
                Write-UiWarning "settings.json 不存在，跳过 env 对齐" -Level Detail
            }
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 CCG Workflow 失败: $($_.Exception.Message)"
        Write-UiDanger $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
