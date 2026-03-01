# CCG Workflow 安装步骤 - CCQ
# 作者: 哈雷酱 (本小姐的专业工作流管理！)
# 功能: 通过官方 npx ccg-workflow@latest init 安装 CCG Workflow

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Process.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"

# CCG Workflow 安装目录
$script:ClaudeDir = "$(Get-UserHome)\.claude"

function Test-CcgWorkflowInstalled {
    <#
    .SYNOPSIS
    检测 CCG Workflow 是否已安装（基于官方目录结构判定）
    .RETURNS
    包含 IsInstalled 字段的结果对象
    #>

    $result = @{
        IsInstalled = $false
        Version     = ""
        Data        = @{}
        Message     = ""
    }

    try {
        # 检查 commands\ccg 目录存在且有 .md 文件
        $commandsDir = "$script:ClaudeDir\commands\ccg"
        if (-not (Test-Path $commandsDir)) {
            $result.Message = "命令模板目录不存在: $commandsDir"
            return $result
        }
        $commandFiles = Get-ChildItem $commandsDir -Filter "*.md" -ErrorAction SilentlyContinue
        if ($null -eq $commandFiles -or $commandFiles.Count -eq 0) {
            $result.Message = "命令模板目录为空: $commandsDir"
            return $result
        }

        # 检查 agents\ccg 目录存在
        $agentsDir = "$script:ClaudeDir\agents\ccg"
        if (-not (Test-Path $agentsDir)) {
            $result.Message = "Agent 模板目录不存在: $agentsDir"
            return $result
        }

        # 检查 .ccg 配置目录存在
        $ccgConfigDir = "$script:ClaudeDir\.ccg"
        if (-not (Test-Path $ccgConfigDir)) {
            $result.Message = "CCG 配置目录不存在: $ccgConfigDir"
            return $result
        }

        # 检查 codeagent-wrapper.exe 二进制文件存在
        $wrapperExe = "$script:ClaudeDir\bin\codeagent-wrapper.exe"
        if (-not (Test-Path $wrapperExe)) {
            $result.Message = "二进制文件不存在: $wrapperExe"
            return $result
        }

        # 所有检查通过，从 config.toml 获取 ccg-workflow 包版本
        $version = ""
        $configToml = "$script:ClaudeDir\.ccg\config.toml"
        if (Test-Path $configToml) {
            $configContent = Get-Content $configToml -Raw -ErrorAction SilentlyContinue
            if ($configContent -match 'version\s*=\s*"([^"]+)"') {
                $version = $matches[1]
            }
        }

        Write-UiSuccess "CCG Workflow 已安装 ($($commandFiles.Count) 个命令模板)"
        $result.IsInstalled = $true
        $result.Version     = $version
        $result.Data        = @{ CommandCount = $commandFiles.Count }
        $result.Message     = "CCG Workflow 已安装"
    }
    catch {
        $result.Message = "检测 CCG Workflow 时出错: $($_.Exception.Message)"
        Write-UiError $result.Message
    }

    return $result
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
        Write-UiInfo "安装 CCG Workflow (官方初始化方式)..."

        # ── 前置检查 ──
        Refresh-SessionPath

        # 验证 Node.js
        $nodeDetails = Test-CommandAvailable -Command "node" -ReturnDetails
        if (-not $nodeDetails.Available) {
            $errorMsg = "未找到 node 命令，请检查 Node.js 安装 (NodeFnm)"
            if ($nodeDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($nodeDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        # 验证 npm
        $npmDetails = Test-CommandAvailable -Command "npm" -ReturnDetails
        if (-not $npmDetails.Available) {
            $errorMsg = "未找到 npm 命令，请检查 Node.js 安装 (NodeFnm)"
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
            $errorMsg = "未找到 npx 命令，请检查 Node.js 安装 (NodeFnm)"
            if ($npxDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($npxDetails.ResolvedPath)"
            }
            if ($npxDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($npxDetails.ErrorMessage)"
            }
            throw $errorMsg
        }

        Write-UiSuccess "环境检查: Node.js & npm 已就绪"

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
        Write-UiInfo "正在通过 npx 获取最新版 CCG Workflow 引擎..."
        Write-UiInfo "正在执行官方初始化 (此过程涉及远程下载，请稍候)..."

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

        Write-UiSuccess "成功部署 CCG 目录结构与配置文件"

        # ── MCP 快照（安装后比对）──
        if ($null -ne $mcpSnapshotBefore -and (Test-Path $claudeJsonPath)) {
            $claudeJsonRawAfter = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
            if ($claudeJsonRawAfter) {
                $claudeJsonAfter = $claudeJsonRawAfter | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($null -ne $claudeJsonAfter -and $claudeJsonAfter.ContainsKey("mcpServers")) {
                    $mcpSnapshotAfter = $claudeJsonAfter["mcpServers"] | ConvertTo-Json -Depth 10 -ErrorAction SilentlyContinue
                    if ($mcpSnapshotBefore -ne $mcpSnapshotAfter) {
                        Write-UiWarn "检测到 .claude.json 中的 mcpServers 配置在安装过程中被修改，请手动检查"
                    }
                }
            }
        }

        # ── 刷新 PATH ──
        Write-UiInfo "正在刷新环境变量..."
        Refresh-SessionPath

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-UiError "安装 CCG Workflow 失败: $($result.ErrorMessage)"
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
            Write-UiInfo "  - 命令模板: 已安装 $commandCount 个 [PASS]"
        }
        else {
            Write-UiInfo "  - 命令模板: 仅 $commandCount 个 (期望 >= 20) [FAIL]"
            $allPassed = $false
        }

        # Agent 模板验证
        $agentsDir = "$script:ClaudeDir\agents\ccg"
        $agentFiles = Get-ChildItem $agentsDir -Filter "*.md" -ErrorAction SilentlyContinue
        $agentCount = if ($null -ne $agentFiles) { $agentFiles.Count } else { 0 }
        if ($agentCount -ge 4) {
            Write-UiInfo "  - Agent 模板: 已安装 $agentCount 个 [PASS]"
        }
        else {
            Write-UiInfo "  - Agent 模板: 仅 $agentCount 个 (期望 >= 4) [FAIL]"
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
                Write-UiInfo "  - 配置文件: config.toml 存在, ccg-workflow v$pkgVersion [PASS]"
            }
            else {
                Write-UiInfo "  - 配置文件: config.toml 存在 [PASS]"
            }
        }
        else {
            Write-UiInfo "  - 配置文件: config.toml 不存在 [FAIL]"
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
            Write-UiInfo "  - 二进制文件: codeagent-wrapper $wrapperVersion [PASS]"
        }
        else {
            Write-UiInfo "  - 二进制文件: codeagent-wrapper.exe 不存在 [FAIL]"
            $allPassed = $false
        }

        # 会话可用性验证
        if (Test-CommandAvailable -Command "codeagent-wrapper") {
            Write-UiInfo "  - PATH 可用性: codeagent-wrapper 在 PATH 中 [PASS]"
        }
        else {
            Write-UiWarn "  - PATH 可用性: codeagent-wrapper 不在 PATH 中 (可能需要重启终端) [SKIP]"
        }

        # ── MCP 保护验证 ──
        # mcpServers 配置在 ~/.claude.json，不在 settings.json
        $claudeJsonPath = "$(Get-UserHome)\.claude.json"
        if (Test-Path $claudeJsonPath) {
            $claudeJsonRaw = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
            if ($claudeJsonRaw) {
                $claudeJson = $claudeJsonRaw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($null -ne $claudeJson -and $claudeJson.ContainsKey("mcpServers")) {
                    Write-UiInfo "  - MCP 配置: 未被覆盖 [PASS]"
                }
                else {
                    Write-UiInfo "  - MCP 配置: mcpServers 字段不存在 [SKIP]"
                }
            }
            else {
                Write-UiInfo "  - MCP 配置: .claude.json 为空 [SKIP]"
            }
        }
        else {
            Write-UiInfo "  - MCP 配置: .claude.json 不存在 [SKIP]"
        }

        # ── 最终判定 ──
        if ($allPassed) {
            Write-UiSuccess "CCG Workflow 验证通过"
            $result.Success = $true
        }
        else {
            $result.ErrorMessage = "CCG Workflow 部分验证项未通过，请检查上方详细信息"
        }
    }
    catch {
        $result.ErrorMessage = "验证 CCG Workflow 失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

function Update-CcgWorkflow {
    <#
    .SYNOPSIS
    更新 CCG Workflow（重新执行官方 init）
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
        Write-UiInfo "更新 CCG Workflow..."

        # 前置检查
        Refresh-SessionPath

        $npxDetails = Test-CommandAvailable -Command "npx" -ReturnDetails
        if (-not $npxDetails.Available) {
            throw "npx 不可用，请检查 Node.js 安装"
        }

        # ── 获取当前本地版本（从 config.toml）──
        $oldVersion = ""
        $configToml = "$script:ClaudeDir\.ccg\config.toml"
        if (Test-Path $configToml) {
            $configContent = Get-Content $configToml -Raw -ErrorAction SilentlyContinue
            if ($configContent -match 'version\s*=\s*"([^"]+)"') {
                $oldVersion = $matches[1]
            }
        }
        if ([string]::IsNullOrWhiteSpace($oldVersion)) {
            $oldVersion = "未知"
        }
        Write-UiInfo "当前版本: $oldVersion"

        # ── 查询 npm 最新版本（非全局包，使用 npm view）──
        $updateCheck = Test-NpmUpdateAvailable -PackageName "ccg-workflow" -CurrentVersion $oldVersion -NonGlobal
        if ($updateCheck.LatestVersion) {
            Write-UiInfo "最新版本: $($updateCheck.LatestVersion)"
        }
        if ($updateCheck.Available -eq $false) {
            Write-UiInfo "CCG Workflow 已是最新版本 ($oldVersion)"
            $result.UpdatedItems = @("noop::CcgWorkflow::no-change")
            $result.Data["OldVersion"] = $oldVersion
            $result.Data["NewVersion"] = $oldVersion
            $result.Success = $true
            return $result
        }
        if ($null -eq $updateCheck.Available) {
            Write-UiWarn "无法查询 npm 最新版本，将继续执行更新"
        }

        # ── MCP 快照（更新前）— HC-U1 保护 ──
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

        # ── 执行 npx ccg-workflow@latest init（--skip-mcp 必须保留）──
        Write-UiInfo "正在通过 npx 获取最新版 CCG Workflow..."
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
            throw "CCG Workflow 更新失败 (ExitCode: $($npxResult.ExitCode)): $errorDetail"
        }

        # ── MCP 快照比对（更新后）──
        if ($null -ne $mcpSnapshotBefore -and (Test-Path $claudeJsonPath)) {
            $claudeJsonRawAfter = Get-Content $claudeJsonPath -Raw -ErrorAction SilentlyContinue
            if ($claudeJsonRawAfter) {
                $claudeJsonAfter = $claudeJsonRawAfter | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($null -ne $claudeJsonAfter -and $claudeJsonAfter.ContainsKey("mcpServers")) {
                    $mcpSnapshotAfter = $claudeJsonAfter["mcpServers"] | ConvertTo-Json -Depth 10 -ErrorAction SilentlyContinue
                    if ($mcpSnapshotBefore -ne $mcpSnapshotAfter) {
                        Write-UiWarn "检测到 .claude.json 中的 mcpServers 在更新过程中被修改，请手动检查"
                    }
                }
            }
        }

        # ── 刷新 PATH + 获取新版本 ──
        Refresh-SessionPath

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

        $result.Data["OldVersion"] = $oldVersion
        $result.Data["NewVersion"] = $newVersion

        # ── 构建 UpdatedItems ──
        if ($oldVersion -eq $newVersion) {
            $result.UpdatedItems = @("noop::CcgWorkflow::no-change")
            Write-UiInfo "CCG Workflow 已是最新版本 ($newVersion)"
        }
        else {
            $result.UpdatedItems = @("npx::ccg-workflow::${oldVersion}->${newVersion}")
            Write-UiSuccess "✓ CCG Workflow 已更新: $oldVersion -> $newVersion"
        }

        $result.Success = $true
    }
    catch {
        $result.ErrorMessage = "更新 CCG Workflow 失败: $($_.Exception.Message)"
        Write-UiError $result.ErrorMessage
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
