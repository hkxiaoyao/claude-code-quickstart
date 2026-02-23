# MCP Server 安装步骤 - Claude Code 环境安装器
# 作者: 哈雷酱 (本小姐的专业 MCP 管理！)
# 功能: MCP Server 安装、配置和 API Key 管理

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"
. "$PSScriptRoot\..\core\Process.ps1"

# 默认运行时依赖
$script:DefaultMcpRuntimeDeps = @(
    @{
        Name = "Node.js LTS"
        Command = "node"
        MinVersion = "20.0.0"
        WingetId = "OpenJS.NodeJS.LTS"
    }
    @{
        Name = "npm"
        Command = "npm"
        MinVersion = "10.0.0"
        WingetId = "OpenJS.NodeJS.LTS"
    }
)

# MCP Server 配置定义
$script:McpServers = [ordered]@{
    "context7" = @{
        Name = "Context7"
        Description = "库文档和代码示例检索，支持最新的开发框架文档"
        McpType = "stdio"
        Command = "npx"
        Args = @("-y", "@upstash/context7-mcp")
        CredentialType = "none"
        RuntimeDeps = $script:DefaultMcpRuntimeDeps
        Category = "Documentation"
        Priority = 1
        Recommended = $true
    }
    "deepwiki" = @{
        Name = "DeepWiki"
        Description = "GitHub 仓库 AI 文档生成和问答"
        McpType = "http"
        Url = "https://mcp.deepwiki.com/mcp"
        CredentialType = "none"
        Category = "Documentation"
        Priority = 2
        Recommended = $true
    }
    "tavily" = @{
        Name = "Tavily"
        Description = "AI 驱动的实时网络搜索、抓取和研究"
        McpType = "http"
        UrlTemplate = "https://mcp.tavily.com/mcp/?tavilyApiKey={TAVILY_API_KEY}"
        CredentialType = "url-embedded"
        Credentials = @(
            @{
                Name = "TAVILY_API_KEY"
                Label = "Tavily API Key"
                Secret = $true
                Required = $true
                Url = "https://app.tavily.com/home"
            }
        )
        Category = "Search"
        Priority = 3
        Recommended = $true
    }
    "contextweaver" = @{
        Name = "ContextWeaver"
        Description = "语义代码检索引擎，基于 Tree-sitter 和向量搜索"
        McpType = "stdio"
        Command = "contextweaver"
        Args = @("mcp")
        CredentialType = "env-file"
        RuntimeDeps = $script:DefaultMcpRuntimeDeps
        PreInstall = @{
            Type = "npm-global"
            Package = "@hsingjui/contextweaver"
            CommandCheck = "contextweaver"
            InitCommand = "contextweaver init"
            InitializedPath = "$env:USERPROFILE\.contextweaver"
        }
        EnvFile = @{
            Path = "$env:USERPROFILE\.contextweaver\.env"
            DefaultProvider = "SiliconFlow"
            ProviderUrl = "https://cloud.siliconflow.cn/account/ak"
            SharedCredentialName = "SILICONFLOW_API_KEY"
            SharedKeyLabel = "SiliconFlow API Key (Embedding + Rerank 共用)"
            SharedKeyFields = @("EMBEDDINGS_API_KEY", "RERANK_API_KEY")
            Fields = @(
                @{ Key = "EMBEDDINGS_API_KEY"; Required = $true; Secret = $true }
                @{ Key = "EMBEDDINGS_BASE_URL"; Default = "https://api.siliconflow.cn/v1/embeddings" }
                @{ Key = "EMBEDDINGS_MODEL"; Default = "BAAI/bge-m3" }
                @{ Key = "EMBEDDINGS_DIMENSIONS"; Default = "1024" }
                @{ Key = "RERANK_API_KEY"; Required = $true; Secret = $true }
                @{ Key = "RERANK_BASE_URL"; Default = "https://api.siliconflow.cn/v1/rerank" }
                @{ Key = "RERANK_MODEL"; Default = "BAAI/bge-reranker-v2-m3" }
                @{ Key = "RERANK_TOP_N"; Default = "20" }
            )
        }
        Category = "Development"
        Priority = 4
        Recommended = $true
    }
    "playwright" = @{
        Name = "Playwright"
        Description = "Microsoft 官方网页自动化，基于可访问性树交互"
        McpType = "stdio"
        Command = "npx"
        Args = @("-y", "@playwright/mcp@latest")
        CredentialType = "none"
        RuntimeDeps = $script:DefaultMcpRuntimeDeps
        Category = "Automation"
        Priority = 5
        Recommended = $true
    }
    "exa" = @{
        Name = "Exa Search"
        Description = "AI 原生高质量网络搜索和内容提取"
        McpType = "stdio"
        Command = "npx"
        Args = @("-y", "exa-mcp-server")
        CredentialType = "single-key"
        ApiKeyName = "EXA_API_KEY"
        ApiKeyUrl = "https://exa.ai/"
        RuntimeDeps = $script:DefaultMcpRuntimeDeps
        Category = "Search"
        Priority = 6
        Recommended = $false
    }
    "ace-tool" = @{
        Name = "ACE Tool"
        Description = "代码上下文检索、语义搜索和 AI Prompt 增强"
        McpType = "stdio"
        Command = "npx"
        Args = @("-y", "ace-tool@latest")
        CredentialType = "args-multi"
        ArgsCredentials = @(
            @{
                ArgName = "--base-url"
                Label = "ACE Backend URL"
                Secret = $false
                Required = $true
                Url = "https://github.com/eastxiaodong/ace-tool"
            }
            @{
                ArgName = "--token"
                Label = "ACE Token"
                Secret = $true
                Required = $true
            }
        )
        RuntimeDeps = $script:DefaultMcpRuntimeDeps
        Category = "Development"
        Priority = 7
        Recommended = $false
    }
    "mastergo" = @{
        Name = "MasterGo"
        Description = "MasterGo 设计稿解析和代码生成 (需团队版)"
        McpType = "stdio"
        Command = "npx"
        Args = @("-y", "@mastergo/magic-mcp")
        CredentialType = "args-token"
        TokenArg = "--token"
        TokenLabel = "MasterGo API Token"
        TokenUrl = "https://mastergo.com/help/MG/MCP"
        RuntimeDeps = $script:DefaultMcpRuntimeDeps
        Category = "Design"
        Priority = 8
        Recommended = $false
    }
    "pencil" = @{
        Name = "Pencil"
        Description = "IDE 集成矢量设计工具，安装后自动注册 MCP"
        McpType = "software"
        CredentialType = "none"
        SoftwareInstall = @{
            WingetSearch = "Pencil"
            DownloadUrl = "https://5ykymftd1soethh5.public.blob.vercel-storage.com/Pencil-win-x64.exe"
            GuideUrl = "https://pencil.dev/"
            InstallerType = "exe"
        }
        Note = "Pencil 桌面端安装后自动注册 MCP，无需手动配置 settings.json"
        Category = "Design"
        Priority = 9
        Recommended = $false
    }
    "figma" = @{
        Name = "Figma"
        Description = "Figma 官方设计稿代码生成和变量提取"
        McpType = "http"
        Url = "https://mcp.figma.com/mcp"
        CredentialType = "none"
        Note = "首次使用时会弹出 OAuth 认证流程，无需手动配置 API Key"
        Category = "Design"
        Priority = 10
        Recommended = $false
    }
    "chrome-devtools" = @{
        Name = "Chrome DevTools"
        Description = "Chrome 浏览器自动化控制、网络监控和性能分析"
        McpType = "stdio"
        Command = "npx"
        Args = @("-y", "chrome-devtools-mcp@latest")
        CredentialType = "none"
        RuntimeDeps = $script:DefaultMcpRuntimeDeps
        Category = "Automation"
        Priority = 11
        Recommended = $false
    }
}

# ============================================================
# 辅助函数
# ============================================================

function Test-ObjectProperty {
    <#
    .SYNOPSIS
    安全检查对象属性是否存在（StrictMode 兼容）
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    return $null -ne $InputObject -and
        $null -ne $InputObject.PSObject -and
        ($InputObject.PSObject.Properties.Name -contains $PropertyName)
}

function ConvertTo-NormalizedVersion {
    param([string]$VersionText)

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $match = [regex]::Match($VersionText, '\d+(\.\d+){0,3}')
    if (-not $match.Success) {
        return $null
    }

    $parts = @($match.Value.Split('.'))
    while ($parts.Count -lt 4) {
        $parts += "0"
    }

    try {
        return [version]::new([int]$parts[0], [int]$parts[1], [int]$parts[2], [int]$parts[3])
    }
    catch {
        return $null
    }
}

function Read-McpCredentialValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [bool]$Secret = $true,
        [bool]$Required = $true,
        [string]$DefaultValue = "",
        [string]$Hint = ""
    )

    do {
        if (-not [string]::IsNullOrWhiteSpace($Hint)) {
            Write-UiInfo $Hint
        }

        if (-not [string]::IsNullOrWhiteSpace($DefaultValue)) {
            Write-UiInfo "请输入 $Label（直接回车使用默认值）:"
        }
        else {
            Write-UiInfo "请输入 ${Label}:"
        }

        if ($Secret) {
            $secureValue = Read-Host -Prompt $Label -AsSecureString
            $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
            try {
                $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
            }
        }
        else {
            $value = Read-Host -Prompt $Label
        }

        if ($null -eq $value) {
            $value = ""
        }

        $value = $value.Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            if (-not [string]::IsNullOrWhiteSpace($DefaultValue)) {
                return $DefaultValue
            }

            if ($Required) {
                Write-UiError "$Label 不能为空，请重新输入"
                continue
            }

            return ""
        }

        return $value
    } while ($true)
}

function Install-McpRuntimeDeps {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Server
    )

    $deps = @()
    if ($Server.ContainsKey("RuntimeDeps") -and $Server["RuntimeDeps"]) {
        $deps = @($Server["RuntimeDeps"])
    }
    if ($deps.Count -eq 0) {
        return @{ Success = $true; Installed = @() }
    }

    $installedDeps = @()
    foreach ($dep in $deps) {
        $depName = if ($dep.Name) { $dep.Name } else { $dep.Command }
        $command = [string]$dep.Command
        $needsInstall = $false

        if (-not (Test-CommandAvailable -Command $command)) {
            $needsInstall = $true
            Write-UiWarn "$depName 未检测到，准备安装"
        }
        elseif ($dep.MinVersion) {
            $installedVersionText = Get-CommandVersion -Command $command
            $installedVersion = ConvertTo-NormalizedVersion -VersionText $installedVersionText
            $minVersion = ConvertTo-NormalizedVersion -VersionText ([string]$dep.MinVersion)

            if ($installedVersion -and $minVersion -and $installedVersion -lt $minVersion) {
                $needsInstall = $true
                Write-UiWarn "$depName 版本过低: $installedVersionText < $($dep.MinVersion)"
            }
        }

        if ($needsInstall) {
            if (-not $dep.WingetId) {
                throw "依赖 $depName 缺少 WingetId，无法自动安装"
            }

            if (-not (Test-CommandAvailable -Command "winget")) {
                throw "winget 不可用，无法安装依赖 $depName"
            }

            Invoke-WingetInstall -PackageId $dep.WingetId -PackageName $depName -AcceptLicense -Silent | Out-Null
            Refresh-SessionPath

            if (-not (Test-CommandAvailable -Command $command)) {
                throw "依赖 $depName 安装后仍不可用"
            }

            $installedDeps += $depName
        }
    }

    return @{ Success = $true; Installed = $installedDeps }
}

function Invoke-McpPreInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Server
    )

    if (-not $Server.ContainsKey("PreInstall") -or -not $Server["PreInstall"]) {
        return @{ Success = $true; Message = "无需预安装" }
    }

    $pre = [hashtable]$Server["PreInstall"]
    switch ($pre.Type) {
        "npm-global" {
            $commandCheck = if ($pre.CommandCheck) { [string]$pre.CommandCheck } else { [string]$Server.Command }
            if (-not (Test-CommandAvailable -Command $commandCheck)) {
                Write-UiInfo "预安装 $($Server.Name): npm 全局安装 $($pre.Package)"
                Invoke-NpmGlobalInstall -PackageName $pre.Package | Out-Null
                Refresh-SessionPath
            }

            if ($pre.InitCommand) {
                $initializedPath = [string]$pre.InitializedPath
                if (-not [string]::IsNullOrWhiteSpace($initializedPath) -and (Test-Path $initializedPath)) {
                    Write-UiInfo "$($Server.Name) 已完成初始化，跳过 init"
                }
                else {
                    Write-UiInfo "执行初始化命令: $($pre.InitCommand)"
                    $tokens = @($pre.InitCommand -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    if ($tokens.Count -eq 0) {
                        throw "初始化命令为空: $($pre.InitCommand)"
                    }

                    $command = $tokens[0]
                    $arguments = @()
                    if ($tokens.Count -gt 1) {
                        $arguments = @($tokens[1..($tokens.Count - 1)])
                    }

                    $initResult = Invoke-ExternalCommand -Command $command -Arguments $arguments -TimeoutSeconds 180
                    if (-not $initResult.Success) {
                        throw "初始化命令执行失败: $($pre.InitCommand)"
                    }
                }
            }

            return @{ Success = $true; Message = "预安装完成" }
        }
        default {
            throw "不支持的预安装类型: $($pre.Type)"
        }
    }
}

function Get-McpCredentials {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Server,
        [Parameter(Mandatory = $true)]
        [hashtable]$SharedCredentials
    )

    $result = @{
        Success = $true
        Values = @{}
        EnvFileValues = @{}
        Shared = @{}
        Skipped = $false
    }

    $credentialType = if ($Server.CredentialType) { [string]$Server.CredentialType } else { "none" }
    switch ($credentialType) {
        "none" {
            return $result
        }
        "single-key" {
            if ($Server.ApiKeyUrl) {
                Write-UiInfo "$($Server.Name) 凭据获取地址: $($Server.ApiKeyUrl)"
            }

            $apiKeyName = [string]$Server.ApiKeyName
            $apiKeyValue = Read-McpCredentialValue -Label $apiKeyName -Secret $true -Required $true
            $result.Values[$apiKeyName] = $apiKeyValue
        }
        "url-embedded" {
            foreach ($credential in @($Server.Credentials)) {
                if ($credential.Url) {
                    Write-UiInfo "$($credential.Label) 获取地址: $($credential.Url)"
                }

                $value = Read-McpCredentialValue `
                    -Label ([string]$credential.Label) `
                    -Secret ([bool]$credential.Secret) `
                    -Required ([bool]$credential.Required)

                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $result.Values[[string]$credential.Name] = $value
                }
            }
        }
        "multi-field" {
            foreach ($field in @($Server.Credentials)) {
                $fieldName = [string]$field.Name
                if ([string]::IsNullOrWhiteSpace($fieldName)) {
                    continue
                }

                $sharedFrom = if ($field.ContainsKey("SharedFrom")) { [string]$field.SharedFrom } else { "" }
                if (-not [string]::IsNullOrWhiteSpace($sharedFrom) -and $SharedCredentials.ContainsKey($sharedFrom)) {
                    $result.Values[$fieldName] = [string]$SharedCredentials[$sharedFrom]
                    continue
                }

                $defaultValue = if ($field.ContainsKey("Default")) { [string]$field.Default } else { "" }
                $required = if ($field.ContainsKey("Required")) { [bool]$field.Required } else { $false }
                $secret = if ($field.ContainsKey("Secret")) { [bool]$field.Secret } else { $false }
                $fieldLabel = if ($field.ContainsKey("Label") -and $field.Label) { [string]$field.Label } else { $fieldName }

                $value = Read-McpCredentialValue `
                    -Label $fieldLabel `
                    -Secret $secret `
                    -Required $required `
                    -DefaultValue $defaultValue

                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $result.Values[$fieldName] = $value
                    if ($field.ContainsKey("Shared") -and [bool]$field.Shared) {
                        $result.Shared[$fieldName] = $value
                    }
                }
            }
        }
        "args-multi" {
            foreach ($argCredential in @($Server.ArgsCredentials)) {
                if ($argCredential.Url) {
                    Write-UiInfo "$($argCredential.Label) 获取地址: $($argCredential.Url)"
                }

                $value = Read-McpCredentialValue `
                    -Label ([string]$argCredential.Label) `
                    -Secret ([bool]$argCredential.Secret) `
                    -Required ([bool]$argCredential.Required)

                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $result.Values[[string]$argCredential.ArgName] = $value
                }
            }
        }
        "args-token" {
            if ($Server.TokenUrl) {
                Write-UiInfo "$($Server.Name) Token 获取地址: $($Server.TokenUrl)"
            }

            $tokenLabel = if ($Server.TokenLabel) { [string]$Server.TokenLabel } else { "Token" }
            $tokenValue = Read-McpCredentialValue -Label $tokenLabel -Secret $true -Required $true
            $result.Values["token"] = $tokenValue
        }
        "env-file" {
            $envFile = $Server.EnvFile
            if (-not $envFile) {
                throw "$($Server.Name) 缺少 EnvFile 配置"
            }

            if ($envFile.ProviderUrl) {
                Write-UiInfo "$($Server.Name) 凭据获取地址: $($envFile.ProviderUrl)"
            }

            $sharedCredentialName = if ($envFile.ContainsKey("SharedCredentialName")) { [string]$envFile.SharedCredentialName } else { "" }
            $sharedKeyValue = ""

            if (-not [string]::IsNullOrWhiteSpace($sharedCredentialName) -and $SharedCredentials.ContainsKey($sharedCredentialName)) {
                $sharedKeyValue = [string]$SharedCredentials[$sharedCredentialName]
                Write-UiInfo "复用共享凭据: $sharedCredentialName"
            }
            else {
                $sharedLabel = if ($envFile.SharedKeyLabel) { [string]$envFile.SharedKeyLabel } else { "共享 API Key" }
                $sharedKeyValue = Read-McpCredentialValue -Label $sharedLabel -Secret $true -Required $true
                if (-not [string]::IsNullOrWhiteSpace($sharedCredentialName)) {
                    $result.Shared[$sharedCredentialName] = $sharedKeyValue
                }
            }

            foreach ($sharedKeyField in @($envFile.SharedKeyFields)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$sharedKeyField)) {
                    $result.EnvFileValues[[string]$sharedKeyField] = $sharedKeyValue
                }
            }

            foreach ($field in @($envFile.Fields)) {
                $fieldKey = [string]$field.Key
                if ([string]::IsNullOrWhiteSpace($fieldKey)) {
                    continue
                }

                if ($result.EnvFileValues.ContainsKey($fieldKey)) {
                    continue
                }

                $defaultValue = if ($field.ContainsKey("Default")) { [string]$field.Default } else { "" }
                $required = if ($field.ContainsKey("Required")) { [bool]$field.Required } else { $false }
                $secret = if ($field.ContainsKey("Secret")) { [bool]$field.Secret } else { $false }
                $fieldLabel = if ($field.ContainsKey("Label") -and $field.Label) { [string]$field.Label } else { $fieldKey }

                $fieldValue = Read-McpCredentialValue -Label $fieldLabel -Secret $secret -Required $required -DefaultValue $defaultValue
                if (-not [string]::IsNullOrWhiteSpace($fieldValue)) {
                    $result.EnvFileValues[$fieldKey] = $fieldValue
                }
            }
        }
        default {
            throw "不支持的凭据类型: $credentialType"
        }
    }

    return $result
}

function New-McpSettingsEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Server,
        [Parameter(Mandatory = $true)]
        [hashtable]$Credentials
    )

    $mcpType = if ($Server.McpType) { [string]$Server.McpType } else { "stdio" }
    $credentialType = if ($Server.CredentialType) { [string]$Server.CredentialType } else { "none" }

    switch ($mcpType) {
        "software" {
            return $null
        }
        "http" {
            if ($credentialType -eq "url-embedded") {
                if (-not $Server.UrlTemplate) {
                    throw "$ServerId 缺少 UrlTemplate"
                }

                $resolvedUrl = [string]$Server.UrlTemplate
                foreach ($credentialName in $Credentials.Keys) {
                    $placeholder = "{0}{1}{2}" -f "{", $credentialName, "}"
                    $escapedValue = [System.Uri]::EscapeDataString([string]$Credentials[$credentialName])
                    $resolvedUrl = $resolvedUrl -replace [regex]::Escape($placeholder), $escapedValue
                }

                if ($resolvedUrl -match "\{[A-Za-z0-9_]+\}") {
                    throw "$ServerId 的 URL 仍包含未替换占位符: $resolvedUrl"
                }

                return @{
                    type = "http"
                    url = $resolvedUrl
                }
            }

            if (-not $Server.Url) {
                throw "$ServerId 缺少 Url"
            }

            return @{
                type = "http"
                url = [string]$Server.Url
            }
        }
        "stdio" {
            if (-not $Server.Command) {
                throw "$ServerId 缺少 Command"
            }

            $args = @()
            foreach ($arg in @($Server.Args)) {
                $args += [string]$arg
            }

            $entry = @{
                command = [string]$Server.Command
                args = $args
            }

            switch ($credentialType) {
                "single-key" {
                    $apiKeyName = [string]$Server.ApiKeyName
                    if (-not $Credentials.ContainsKey($apiKeyName)) {
                        throw "$ServerId 缺少凭据: $apiKeyName"
                    }

                    $entry["env"] = @{
                        $apiKeyName = [string]$Credentials[$apiKeyName]
                    }
                }
                "multi-field" {
                    $envMap = @{}
                    foreach ($credentialKey in $Credentials.Keys) {
                        $credentialValue = [string]$Credentials[$credentialKey]
                        if (-not [string]::IsNullOrWhiteSpace($credentialValue)) {
                            $envMap[$credentialKey] = $credentialValue
                        }
                    }
                    if ($envMap.Count -gt 0) {
                        $entry["env"] = $envMap
                    }
                }
                "args-multi" {
                    foreach ($argCredential in @($Server.ArgsCredentials)) {
                        $argName = [string]$argCredential.ArgName
                        $required = if ($argCredential.ContainsKey("Required")) { [bool]$argCredential.Required } else { $false }

                        if (-not $Credentials.ContainsKey($argName)) {
                            if ($required) {
                                throw "$ServerId 缺少参数凭据: $argName"
                            }
                            continue
                        }

                        $argValue = [string]$Credentials[$argName]
                        if ($required -and [string]::IsNullOrWhiteSpace($argValue)) {
                            throw "$ServerId 参数凭据为空: $argName"
                        }

                        if (-not [string]::IsNullOrWhiteSpace($argValue)) {
                            $entry["args"] += @($argName, $argValue)
                        }
                    }
                }
                "args-token" {
                    if (-not $Credentials.ContainsKey("token")) {
                        throw "$ServerId 缺少 token"
                    }

                    $tokenValue = [string]$Credentials["token"]
                    if ([string]::IsNullOrWhiteSpace($tokenValue)) {
                        throw "$ServerId token 为空"
                    }

                    $entry["args"] += "$($Server.TokenArg)=$tokenValue"
                }
            }

            return $entry
        }
        default {
            throw "不支持的 MCP 类型: $mcpType"
        }
    }
}

function Install-McpSoftware {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerId,
        [Parameter(Mandatory = $true)]
        [hashtable]$Server
    )

    $result = @{
        Success = $true
        Method = "none"
        Message = ""
    }

    if ($Server.McpType -ne "software") {
        return $result
    }

    $install = $Server.SoftwareInstall
    if (-not $install) {
        throw "$ServerId 缺少 SoftwareInstall 配置"
    }

    if (Test-CommandAvailable -Command "winget") {
        try {
            if ($install.WingetSearch) {
                $wingetArgs = @(
                    "install",
                    "--name", $install.WingetSearch,
                    "-e",
                    "--accept-package-agreements",
                    "--accept-source-agreements",
                    "--disable-interactivity"
                )
                $wingetResult = Invoke-ExternalCommand -Command "winget" -Arguments $wingetArgs -TimeoutSeconds 300
                if (-not $wingetResult.Success) {
                    throw "winget 按名称安装失败"
                }
            }
            else {
                throw "未配置 WingetSearch"
            }

            $result.Method = "winget"
            $result.Message = "winget 安装成功"
            return $result
        }
        catch {
            Write-UiWarn "$($Server.Name) winget 安装失败，将尝试下载方式: $($_.Exception.Message)"
        }
    }

    if ($install.DownloadUrl) {
        try {
            $downloadDir = "$env:TEMP\ClaudeEnvInstaller"
            if (-not (Test-Path $downloadDir)) {
                New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
            }

            $fileName = Split-Path -Path ([string]$install.DownloadUrl) -Leaf
            if ([string]::IsNullOrWhiteSpace($fileName)) {
                $fileName = "$ServerId-installer.exe"
            }
            $downloadPath = Join-Path $downloadDir $fileName

            Write-UiInfo "下载安装程序: $($install.DownloadUrl)"
            Invoke-WebRequest -Uri $install.DownloadUrl -OutFile $downloadPath -UseBasicParsing
            $process = Start-Process -FilePath $downloadPath -PassThru -Wait

            if ($process -and $process.ExitCode -ne 0) {
                throw "安装程序退出码非 0: $($process.ExitCode)"
            }

            $result.Method = "download"
            $result.Message = "下载安装成功"
            return $result
        }
        catch {
            Write-UiWarn "$($Server.Name) 下载安装失败，将进入引导安装: $($_.Exception.Message)"
        }
    }

    Write-UiInfo "请手动安装 $($Server.Name)"
    if ($install.GuideUrl) {
        Write-UiInfo "安装指引: $($install.GuideUrl)"
    }
    Read-Host "安装完成后按回车继续..."

    $result.Method = "guide"
    $result.Message = "已切换为引导安装"
    return $result
}

function Write-McpEnvFile {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Server,
        [Parameter(Mandatory = $true)]
        [hashtable]$EnvValues
    )

    try {
        if (-not $Server.EnvFile) {
            throw "缺少 EnvFile 配置"
        }

        $envPath = [string]$Server.EnvFile.Path
        if ([string]::IsNullOrWhiteSpace($envPath)) {
            throw "EnvFile.Path 为空"
        }

        $envDir = Split-Path -Path $envPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($envDir) -and -not (Test-Path $envDir)) {
            New-Item -Path $envDir -ItemType Directory -Force | Out-Null
        }

        $lines = @()
        if (Test-Path $envPath) {
            $existingLines = Get-Content -Path $envPath -ErrorAction SilentlyContinue
            if ($null -ne $existingLines) {
                $lines = @($existingLines)
            }
        }

        $keyLineIndex = @{}
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
                $keyLineIndex[$matches[1]] = $i
            }
        }

        foreach ($key in $EnvValues.Keys) {
            $value = [string]$EnvValues[$key]
            $value = $value -replace "`r", "" -replace "`n", ""
            if ([string]::IsNullOrWhiteSpace($value)) {
                continue
            }

            $line = "$key=$value"
            if ($keyLineIndex.ContainsKey($key)) {
                $lines[[int]$keyLineIndex[$key]] = $line
            }
            else {
                $lines += $line
            }
        }

        $tempPath = "$envPath.tmp"
        $lines | Set-Content -Path $tempPath -Encoding UTF8
        Move-Item -Path $tempPath -Destination $envPath -Force

        return @{ Success = $true; Path = $envPath }
    }
    catch {
        return @{
            Success = $false
            Path = ""
            ErrorMessage = $_.Exception.Message
        }
    }
}

# ============================================================
# 主要函数
# ============================================================

function Test-McpInstalled {
    <#
    .SYNOPSIS
    检测 MCP Server 是否已安装配置（支持 stdio/http/software）
    #>

    try {
        $settingsPath = Get-ClaudeSettingsPath
        if (-not (Test-Path $settingsPath)) {
            return $false
        }

        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if (-not $settings) {
            return $false
        }

        $hasMcpServers = $settings.PSObject.Properties.Name -contains "mcpServers" -and $settings.mcpServers
        $hasPermissions = $settings.PSObject.Properties.Name -contains "permissions" -and $settings.permissions -and $settings.permissions.allow

        $stdioCount = 0
        $httpCount = 0
        if ($hasMcpServers) {
            foreach ($serverId in @($settings.mcpServers.PSObject.Properties.Name)) {
                $serverConfig = $settings.mcpServers.PSObject.Properties[$serverId].Value
                $hasType = Test-ObjectProperty -InputObject $serverConfig -PropertyName "type"
                $hasUrl = Test-ObjectProperty -InputObject $serverConfig -PropertyName "url"
                $hasCommand = Test-ObjectProperty -InputObject $serverConfig -PropertyName "command"
                $hasArgs = Test-ObjectProperty -InputObject $serverConfig -PropertyName "args"

                if ($hasType -and [string]$serverConfig.type -eq "http" -and $hasUrl -and -not [string]::IsNullOrWhiteSpace([string]$serverConfig.url)) {
                    $httpCount++
                    continue
                }

                if ($hasCommand -and $hasArgs -and -not [string]::IsNullOrWhiteSpace([string]$serverConfig.command) -and $serverConfig.args) {
                    $stdioCount++
                }
            }
        }

        $softwareCount = 0
        $pencilInstalled = (Test-CommandAvailable -Command "pencil") -or (Test-Path "$env:LOCALAPPDATA\Programs\Pencil")
        if ($pencilInstalled) {
            $softwareCount = 1
        }

        if (($stdioCount + $httpCount + $softwareCount) -gt 0 -and $hasPermissions) {
            Write-UiSuccess "✓ MCP Server 已配置 (stdio: $stdioCount, http: $httpCount, software: $softwareCount)"
            return $true
        }

        return $false
    }
    catch {
        Write-UiWarn "检测 MCP Server 配置时出错: $($_.Exception.Message)"
        return $false
    }
}

function Install-Mcp {
    <#
    .SYNOPSIS
    安装 MCP Server 配置（管道模式：依赖 → 预安装 → 凭据 → 软件 → 配置）
    #>

    try {
        Write-UiInfo "配置 MCP Server..."

        $modeOptions = @(
            "一键模式 (推荐) - 自动安装核心 5 个 MCP Server",
            "自定义模式 - 手动选择需要的 MCP Server"
        )
        $modeIndex = Show-SingleSelectMenu -Options $modeOptions -Title "MCP Server 安装模式"
        if ($modeIndex -lt 0) {
            throw "未选择安装模式"
        }
        $selectedMode = if ($modeIndex -eq 0) { "quick" } else { "custom" }

        $orderedServerIds = @($script:McpServers.Keys | Sort-Object { [int]$script:McpServers[$_].Priority })
        if ($selectedMode -eq "quick") {
            $selectedServers = @($orderedServerIds | Where-Object {
                $script:McpServers[$_].Recommended
            })

            Write-UiInfo "一键模式将安装以下 MCP Server:"
            foreach ($serverId in $selectedServers) {
                $server = $script:McpServers[$serverId]
                Write-UiInfo "  - [$($server.Category)] $($server.Name) [$($server.McpType)]"
            }
        }
        else {
            $displayOptions = @()
            $serverMap = @()
            $defaultSelected = @()

            for ($i = 0; $i -lt $orderedServerIds.Count; $i++) {
                $serverId = $orderedServerIds[$i]
                $server = $script:McpServers[$serverId]
                $recommendedTag = if ($server.Recommended) { " (推荐)" } else { "" }
                $credentialTag = if ($server.CredentialType -ne "none") { " | 需凭据" } else { "" }
                $displayOptions += "[$($server.Category)] $($server.Name)$recommendedTag [$($server.McpType)]$credentialTag - $($server.Description)"
                $serverMap += $serverId
                if ($server.Recommended) {
                    $defaultSelected += $i
                }
            }

            Write-UiInfo "请选择要安装的 MCP Server:"
            $selectedIndices = Show-MultiSelectMenu -Options $displayOptions -DefaultSelected $defaultSelected -Title "MCP Server 选择"

            if (-not $selectedIndices -or $selectedIndices.Count -eq 0) {
                throw "未选择任何 MCP Server"
            }

            $selectedServers = @()
            foreach ($selectedIndex in $selectedIndices) {
                $selectedServers += $serverMap[[int]$selectedIndex]
            }
        }

        $serverStatus = @{}
        foreach ($serverId in $selectedServers) {
            $serverStatus[$serverId] = @{
                State = "待处理"
                Message = ""
            }
        }

        $activeServers = New-Object System.Collections.ArrayList
        $settingsCredentials = @{}
        $envFileCredentials = @{}
        $sharedCredentials = @{}
        $softwareInstallResult = @{}

        Write-UiInfo "阶段 1/5: 运行时依赖检查"
        foreach ($serverId in $selectedServers) {
            $server = $script:McpServers[$serverId]
            try {
                $depResult = Install-McpRuntimeDeps -Server $server
                if (@($depResult.Installed).Count -gt 0) {
                    Write-UiSuccess "$($server.Name) 依赖安装完成: $(@($depResult.Installed) -join ', ')"
                }
                $serverStatus[$serverId].State = "依赖已就绪"
                [void]$activeServers.Add($serverId)
            }
            catch {
                $serverStatus[$serverId].State = "失败"
                $serverStatus[$serverId].Message = "依赖失败: $($_.Exception.Message)"
                Write-UiWarn "跳过 $($server.Name): $($serverStatus[$serverId].Message)"
            }
        }

        Write-UiInfo "阶段 2/5: 预安装处理"
        foreach ($serverId in @($activeServers)) {
            $server = $script:McpServers[$serverId]
            try {
                $preResult = Invoke-McpPreInstall -ServerId $serverId -Server $server
                if ($preResult.Message -and $preResult.Message -ne "无需预安装") {
                    Write-UiSuccess "$($server.Name) $($preResult.Message)"
                }
                $serverStatus[$serverId].State = "预安装完成"
            }
            catch {
                $serverStatus[$serverId].State = "失败"
                $serverStatus[$serverId].Message = "预安装失败: $($_.Exception.Message)"
                Write-UiWarn "跳过 $($server.Name): $($serverStatus[$serverId].Message)"
                [void]$activeServers.Remove($serverId)
            }
        }

        Write-UiInfo "阶段 3/5: 凭据收集"
        $credentialHints = New-Object System.Collections.Generic.List[string]
        foreach ($serverId in @($activeServers)) {
            $server = $script:McpServers[$serverId]
            switch ($server.CredentialType) {
                "single-key" {
                    if ($server.ApiKeyUrl) {
                        $hint = "  - $($server.Name): $($server.ApiKeyUrl)"
                        if (-not $credentialHints.Contains($hint)) { [void]$credentialHints.Add($hint) }
                    }
                }
                "url-embedded" {
                    foreach ($item in @($server.Credentials)) {
                        if ($item.Url) {
                            $hint = "  - $($server.Name): $($item.Url)"
                            if (-not $credentialHints.Contains($hint)) { [void]$credentialHints.Add($hint) }
                        }
                    }
                }
                "multi-field" {
                    foreach ($item in @($server.Credentials)) {
                        if ($item.Url) {
                            $hint = "  - $($server.Name): $($item.Url)"
                            if (-not $credentialHints.Contains($hint)) { [void]$credentialHints.Add($hint) }
                        }
                    }
                }
                "args-multi" {
                    foreach ($item in @($server.ArgsCredentials)) {
                        if ($item.Url) {
                            $hint = "  - $($server.Name): $($item.Url)"
                            if (-not $credentialHints.Contains($hint)) { [void]$credentialHints.Add($hint) }
                        }
                    }
                }
                "args-token" {
                    if ($server.TokenUrl) {
                        $hint = "  - $($server.Name): $($server.TokenUrl)"
                        if (-not $credentialHints.Contains($hint)) { [void]$credentialHints.Add($hint) }
                    }
                }
                "env-file" {
                    if ($server.EnvFile -and $server.EnvFile.ProviderUrl) {
                        $hint = "  - $($server.Name): $($server.EnvFile.ProviderUrl)"
                        if (-not $credentialHints.Contains($hint)) { [void]$credentialHints.Add($hint) }
                    }
                }
            }
        }
        if ($credentialHints.Count -gt 0) {
            Write-UiInfo "凭据获取地址："
            foreach ($hint in $credentialHints) {
                Write-UiInfo $hint
            }
        }

        foreach ($serverId in @($activeServers)) {
            $server = $script:McpServers[$serverId]
            if ($server.CredentialType -eq "none") {
                continue
            }

            try {
                $credentialResult = Get-McpCredentials -ServerId $serverId -Server $server -SharedCredentials $sharedCredentials
                $settingsCredentials[$serverId] = $credentialResult.Values
                if ($credentialResult.EnvFileValues.Count -gt 0) {
                    $envFileCredentials[$serverId] = $credentialResult.EnvFileValues
                }
                foreach ($sharedKey in $credentialResult.Shared.Keys) {
                    $sharedCredentials[$sharedKey] = $credentialResult.Shared[$sharedKey]
                }
                $serverStatus[$serverId].State = "凭据已完成"
            }
            catch {
                $serverStatus[$serverId].State = "失败"
                $serverStatus[$serverId].Message = "凭据收集失败: $($_.Exception.Message)"
                Write-UiWarn "跳过 $($server.Name): $($serverStatus[$serverId].Message)"
                [void]$activeServers.Remove($serverId)
            }
        }

        Write-UiInfo "阶段 4/5: 软件安装"
        foreach ($serverId in @($activeServers)) {
            $server = $script:McpServers[$serverId]
            if ($server.McpType -ne "software") {
                continue
            }

            try {
                $softwareResult = Install-McpSoftware -ServerId $serverId -Server $server
                $softwareInstallResult[$serverId] = $softwareResult
                $serverStatus[$serverId].State = "软件已安装"
            }
            catch {
                $serverStatus[$serverId].State = "失败"
                $serverStatus[$serverId].Message = "软件安装失败: $($_.Exception.Message)"
                Write-UiWarn "跳过 $($server.Name): $($serverStatus[$serverId].Message)"
                [void]$activeServers.Remove($serverId)
            }
        }

        Write-UiInfo "阶段 5/5: 配置生成与写入"

        $successCount = @($selectedServers | Where-Object { $serverStatus[$_].State -ne "失败" }).Count
        if ($successCount -eq 0) {
            throw "所有 MCP Server 均处理失败"
        }

        $settingsPath = Get-ClaudeSettingsPath
        $settings = @{}

        if (Test-Path $settingsPath) {
            try {
                $existingContent = Get-Content -Path $settingsPath -Raw
                $settings = $existingContent | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                if (-not $settings) {
                    $settings = @{}
                }
                Write-UiInfo "已读取现有 settings.json，将按增量方式合并"
            }
            catch {
                Write-UiWarn "无法解析现有 settings.json，将创建新配置"
                $settings = @{}
            }
        }

        if (-not $settings.ContainsKey("mcpServers")) {
            $settings["mcpServers"] = @{}
        }

        foreach ($serverId in @($activeServers)) {
            $server = $script:McpServers[$serverId]
            $credentials = if ($settingsCredentials.ContainsKey($serverId)) { $settingsCredentials[$serverId] } else { @{} }

            if ($server.CredentialType -eq "env-file") {
                if ($envFileCredentials.ContainsKey($serverId)) {
                    $envWriteResult = Write-McpEnvFile -Server $server -EnvValues $envFileCredentials[$serverId]
                    if ($envWriteResult.Success) {
                        Write-UiSuccess "已写入 $($server.Name) .env 文件: $($envWriteResult.Path)"
                    }
                    else {
                        Write-UiWarn "$($server.Name) .env 写入失败: $($envWriteResult.ErrorMessage)"
                    }
                }
            }

            try {
                $entry = New-McpSettingsEntry -ServerId $serverId -Server $server -Credentials $credentials
                if ($entry) {
                    $settings["mcpServers"][$serverId] = $entry
                }
                $serverStatus[$serverId].State = "已配置"
            }
            catch {
                $serverStatus[$serverId].State = "失败"
                $serverStatus[$serverId].Message = "配置生成失败: $($_.Exception.Message)"
                Write-UiWarn "跳过 $($server.Name): $($serverStatus[$serverId].Message)"
            }
        }

        if (-not $settings.ContainsKey("permissions")) {
            $settings["permissions"] = @{}
        }
        if (-not $settings["permissions"].ContainsKey("allow")) {
            $settings["permissions"]["allow"] = @()
        }
        if (-not ($settings["permissions"]["allow"] -is [System.Collections.IList])) {
            $settings["permissions"]["allow"] = @($settings["permissions"]["allow"])
        }

        $mcpPermissions = @("mcp", "read", "write", "bash", "glob", "grep")
        foreach ($permission in $mcpPermissions) {
            if ($settings["permissions"]["allow"] -notcontains $permission) {
                $settings["permissions"]["allow"] += $permission
            }
        }

        foreach ($serverId in @($activeServers)) {
            $server = $script:McpServers[$serverId]
            if ($server.CredentialType -eq "single-key" -and $settingsCredentials.ContainsKey($serverId)) {
                $apiKeyName = [string]$server.ApiKeyName
                if ($settingsCredentials[$serverId].ContainsKey($apiKeyName)) {
                    if (-not $settings.ContainsKey("env")) {
                        $settings["env"] = @{}
                    }
                    $settings["env"][$apiKeyName] = [string]$settingsCredentials[$serverId][$apiKeyName]
                }
            }
        }

        $settingsDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }

        Write-UiInfo "写入 MCP Server 配置..."
        $tempPath = "$settingsPath.tmp"
        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding UTF8
        Move-Item -Path $tempPath -Destination $settingsPath -Force

        Write-UiSuccess "✓ MCP Server 配置已写入"
        Write-UiInfo "配置路径: $settingsPath"

        Write-UiInfo "配置摘要:"
        Write-UiInfo "  - 选择 MCP 数量: $($selectedServers.Count)"
        Write-UiInfo "  - 有效处理数量: $(@($activeServers).Count)"
        Write-UiInfo "  - 权限策略: $($settings.permissions.allow.Count) 项"

        foreach ($serverId in $selectedServers) {
            $server = $script:McpServers[$serverId]
            $status = if ($serverStatus[$serverId].State -eq "失败") {
                "✗ $($serverStatus[$serverId].Message)"
            }
            elseif ($server.McpType -eq "software" -and $softwareInstallResult.ContainsKey($serverId)) {
                "✓ software ($($softwareInstallResult[$serverId].Method))"
            }
            else { "✓ $($serverStatus[$serverId].State)" }
            Write-UiInfo "  - $($server.Name): $status"
        }

        foreach ($serverId in $settingsCredentials.Keys) {
            foreach ($key in $settingsCredentials[$serverId].Keys) {
                $settingsCredentials[$serverId][$key] = $null
            }
        }
        foreach ($key in $sharedCredentials.Keys) {
            $sharedCredentials[$key] = $null
        }

        return $true
    }
    catch {
        Write-UiError "配置 MCP Server 失败: $($_.Exception.Message)"
        return $false
    }
}

function Verify-Mcp {
    <#
    .SYNOPSIS
    验证 MCP Server 配置（stdio/http/software 多类型）
    #>

    try {
        $settingsPath = Get-ClaudeSettingsPath
        if (-not (Test-Path $settingsPath)) {
            throw "settings.json 不存在"
        }

        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
        if (-not (Test-ObjectProperty -InputObject $settings -PropertyName "mcpServers") -or -not $settings.mcpServers) {
            throw "缺少 MCP Server 配置"
        }

        $configuredServers = @($settings.mcpServers.PSObject.Properties.Name)
        if ($configuredServers.Count -eq 0) {
            throw "未配置任何 MCP Server"
        }

        $stdioCount = 0
        $httpCount = 0

        foreach ($serverId in $configuredServers) {
            $serverConfig = $settings.mcpServers.PSObject.Properties[$serverId].Value
            if (-not $serverConfig) {
                Write-UiWarn "跳过空配置: $serverId"
                continue
            }

            $hasType = Test-ObjectProperty -InputObject $serverConfig -PropertyName "type"
            $hasUrl = Test-ObjectProperty -InputObject $serverConfig -PropertyName "url"
            $hasCommand = Test-ObjectProperty -InputObject $serverConfig -PropertyName "command"
            $hasArgs = Test-ObjectProperty -InputObject $serverConfig -PropertyName "args"
            $typeValue = if ($hasType) { [string]$serverConfig.type } else { "" }

            if ($typeValue -eq "http") {
                $httpCount++
                if (-not $hasUrl -or [string]::IsNullOrWhiteSpace([string]$serverConfig.url)) {
                    throw "MCP Server '$serverId' 缺少 http.url"
                }
                if ([string]$serverConfig.url -match "\{[A-Za-z0-9_]+\}") {
                    throw "MCP Server '$serverId' URL 仍包含占位符: $($serverConfig.url)"
                }
            }
            elseif ($hasCommand -and -not [string]::IsNullOrWhiteSpace([string]$serverConfig.command)) {
                $stdioCount++
                if (-not $hasArgs -or -not $serverConfig.args) {
                    throw "MCP Server '$serverId' 缺少 stdio.args"
                }
            }
            else {
                Write-UiWarn "MCP Server '$serverId' 不是标准 stdio/http 配置，已跳过严格校验"
                continue
            }

            if (-not $script:McpServers.ContainsKey($serverId)) {
                continue
            }

            $serverDef = $script:McpServers[$serverId]
            $credentialType = if ($serverDef.CredentialType) { [string]$serverDef.CredentialType } else { "none" }
            $argsList = if ($hasArgs) { @($serverConfig.args) } else { @() }

            switch ($credentialType) {
                "single-key" {
                    $apiKeyName = [string]$serverDef.ApiKeyName
                    $hasServerEnv = (Test-ObjectProperty -InputObject $serverConfig -PropertyName "env") -and
                        $serverConfig.env -and
                        ($serverConfig.env.PSObject.Properties.Name -contains $apiKeyName) -and
                        -not [string]::IsNullOrWhiteSpace([string]$serverConfig.env.$apiKeyName)
                    $hasGlobalEnv = (Test-ObjectProperty -InputObject $settings -PropertyName "env") -and
                        $settings.env -and
                        ($settings.env.PSObject.Properties.Name -contains $apiKeyName) -and
                        -not [string]::IsNullOrWhiteSpace([string]$settings.env.$apiKeyName)
                    if (-not ($hasServerEnv -or $hasGlobalEnv)) {
                        Write-UiWarn "MCP Server '$serverId' 缺少 API Key: $apiKeyName"
                    }
                }
                "args-multi" {
                    foreach ($argCredential in @($serverDef.ArgsCredentials)) {
                        $argName = [string]$argCredential.ArgName
                        $required = if ($argCredential.ContainsKey("Required")) { [bool]$argCredential.Required } else { $false }
                        if (-not $required) {
                            continue
                        }

                        $argIndex = [array]::IndexOf($argsList, $argName)
                        if ($argIndex -lt 0 -or $argIndex -ge ($argsList.Count - 1)) {
                            throw "MCP Server '$serverId' 缺少必需参数: $argName"
                        }
                        if ([string]::IsNullOrWhiteSpace([string]$argsList[$argIndex + 1])) {
                            throw "MCP Server '$serverId' 参数值为空: $argName"
                        }
                    }
                }
                "args-token" {
                    $tokenPrefix = "$($serverDef.TokenArg)="
                    $hasToken = @($argsList | Where-Object {
                        $_ -is [string] -and $_.StartsWith($tokenPrefix) -and $_.Length -gt $tokenPrefix.Length
                    }).Count -gt 0
                    if (-not $hasToken) {
                        throw "MCP Server '$serverId' 缺少 token 参数: $($serverDef.TokenArg)"
                    }
                }
                "url-embedded" {
                    if ($serverConfig.type -ne "http") {
                        throw "MCP Server '$serverId' 应为 http 配置"
                    }
                    if ([string]$serverConfig.url -match "\{[A-Za-z0-9_]+\}") {
                        throw "MCP Server '$serverId' URL 占位符未替换: $($serverConfig.url)"
                    }
                }
                "env-file" {
                    $envPath = [string]$serverDef.EnvFile.Path
                    if (-not (Test-Path $envPath)) {
                        throw "MCP Server '$serverId' 缺少 .env 文件: $envPath"
                    }

                    $envContent = Get-Content -Path $envPath -Raw
                    foreach ($sharedField in @($serverDef.EnvFile.SharedKeyFields)) {
                        if ($envContent -notmatch "(?m)^\s*$([regex]::Escape([string]$sharedField))\s*=\s*.+$") {
                            throw "MCP Server '$serverId' .env 缺少必填字段: $sharedField"
                        }
                    }
                    foreach ($field in @($serverDef.EnvFile.Fields)) {
                        if ($field.ContainsKey("Required") -and [bool]$field.Required) {
                            $fieldKey = [string]$field.Key
                            if ($envContent -notmatch "(?m)^\s*$([regex]::Escape($fieldKey))\s*=\s*.+$") {
                                throw "MCP Server '$serverId' .env 缺少必填字段: $fieldKey"
                            }
                        }
                    }
                }
            }
        }

        if (-not (Test-ObjectProperty -InputObject $settings -PropertyName "permissions") -or
            -not $settings.permissions -or
            -not (Test-ObjectProperty -InputObject $settings.permissions -PropertyName "allow") -or
            -not $settings.permissions.allow) {
            throw "缺少权限配置"
        }
        $requiredPermissions = @("mcp", "read", "write")
        foreach ($permission in $requiredPermissions) {
            if ($settings.permissions.allow -notcontains $permission) {
                Write-UiWarn "⚠ 缺少权限: $permission"
            }
        }

        Write-UiSuccess "✓ MCP Server 配置验证通过"
        Write-UiInfo "  - MCP 数量: $($configuredServers.Count)"
        Write-UiInfo "  - stdio: $stdioCount"
        Write-UiInfo "  - http: $httpCount"

        if ($settings.mcpServers.PSObject.Properties.Name -contains "contextweaver") {
            $envPath = $script:McpServers["contextweaver"].EnvFile.Path
            if (Test-Path $envPath) {
                Write-UiInfo "  - contextweaver .env: ✓ ($envPath)"
            }
            else {
                throw "contextweaver 已配置但缺少 .env 文件: $envPath"
            }
        }

        return $true
    }
    catch {
        Write-UiError "验证 MCP Server 配置失败: $($_.Exception.Message)"
        return $false
    }
}

# 辅助函数
function Get-ClaudeSettingsPath {
    <#
    .SYNOPSIS
    获取 Claude Code settings.json 路径（HC-12: ~/.claude/settings.json）
    #>

    return "$env:USERPROFILE\.claude\settings.json"
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
