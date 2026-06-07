#Requires -Version 7.0
# Test-Contracts.ps1 - 跨平台契约一致性检查
# 功能: 验证 installer/contracts JSON 契约与 Windows/macOS canonical runtime 不冲突

param(
    [string]$InstallerRoot = (Resolve-Path "$PSScriptRoot\..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Issues = [System.Collections.Generic.List[string]]::new()
$script:InstallerRoot = (Resolve-Path $InstallerRoot).Path
$script:RepoRoot = (Split-Path -Parent $script:InstallerRoot)
$script:WindowsRoot = Join-Path $script:InstallerRoot 'windows'
$script:CoreRoot = Join-Path $script:WindowsRoot 'core'
$script:StepsRoot = Join-Path $script:WindowsRoot 'steps'

function Read-ContractJson {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $PSScriptRoot $RelativePath
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "契约文件不存在: $path"
    }

    return (Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable -ErrorAction Stop)
}

function ConvertTo-PlainObject {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $result[[string]$key] = ConvertTo-PlainObject $Value[$key]
        }
        return $result
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-PlainObject $_ })
    }

    return $Value
}

function ConvertTo-ComparableJson {
    param([AllowNull()][object]$Value)

    return (ConvertTo-PlainObject $Value | ConvertTo-Json -Depth 80 -Compress)
}

function Add-Issue {
    param([Parameter(Mandatory)][string]$Message)

    [void]$script:Issues.Add($Message)
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Expected,
        [AllowNull()][object]$Actual
    )

    $expectedJson = ConvertTo-ComparableJson $Expected
    $actualJson = ConvertTo-ComparableJson $Actual
    if ($expectedJson -ne $actualJson) {
        Add-Issue "$Name 不一致`n  Expected: $expectedJson`n  Actual:   $actualJson"
    }
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Leaf', 'Container')]
        [string]$PathType = 'Leaf'
    )

    if (-not (Test-Path $Path -PathType $PathType)) {
        Add-Issue "$Name 不存在: $Path"
    }
}

function Assert-PathAbsent {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path
    )

    if (Test-Path $Path) {
        Add-Issue "$Name 不应作为支持路径存在: $Path"
    }
}

function Invoke-ContractCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    try {
        & $ScriptBlock
    } catch {
        Add-Issue "$Name 失败: $($_.Exception.Message)"
    }
}

function New-IndexByKey {
    param(
        [Parameter(Mandatory)][array]$Items,
        [Parameter(Mandatory)][string]$KeyName
    )

    $index = @{}
    foreach ($item in @($Items)) {
        if ($item -isnot [System.Collections.IDictionary] -or -not $item.ContainsKey($KeyName)) {
            Add-Issue "索引项缺少字段 ${KeyName}: $(ConvertTo-ComparableJson $item)"
            continue
        }
        $key = [string]$item[$KeyName]
        if ($index.ContainsKey($key)) {
            Add-Issue "索引字段 ${KeyName} 重复: $key"
            continue
        }
        $index[$key] = $item
    }
    return $index
}

function Select-HashtableFields {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Item,
        [Parameter(Mandatory)][string[]]$Fields
    )

    $result = [ordered]@{}
    foreach ($field in $Fields) {
        if ($Item.ContainsKey($field)) {
            $result[$field] = $Item[$field]
        }
    }
    return $result
}

function Test-StepsContract {
    param([Parameter(Mandatory)][hashtable]$Contract)

    $registry = @(Get-StepRegistry)
    $contractSteps = @($Contract['Steps'])

    Assert-Equal 'steps.count' $registry.Count $contractSteps.Count

    $registryIndex = New-IndexByKey -Items $registry -KeyName 'StepId'
    $contractIndex = New-IndexByKey -Items $contractSteps -KeyName 'StepId'

    $stepFields = @(
        'StepId', 'StepName', 'Description', 'StepFile', 'SubModules',
        'TestFunction', 'InstallFunction', 'VerifyFunction', 'UpdateFunction',
        'SkipIfInstalled', 'SkipIfInstalledWhenAutoAdded', 'IsOptional',
        'Order', 'Dependencies', 'Group'
    )

    foreach ($stepId in @($registryIndex.Keys | Sort-Object)) {
        if (-not $contractIndex.ContainsKey($stepId)) {
            Add-Issue "steps.$stepId 缺少 contracts 条目"
            continue
        }
        $expected = Select-HashtableFields -Item $registryIndex[$stepId] -Fields $stepFields
        $actual = Select-HashtableFields -Item $contractIndex[$stepId] -Fields $stepFields
        Assert-Equal "steps.$stepId" $expected $actual
    }

    foreach ($stepId in @($contractIndex.Keys | Sort-Object)) {
        if (-not $registryIndex.ContainsKey($stepId)) {
            Add-Issue "steps.$stepId 未在 Registry.ps1 中定义"
        }
    }

    foreach ($step in $contractSteps) {
        $stepId = [string]$step['StepId']
        $stepFile = [string]$step['StepFile']
        if ($stepFile -notmatch '^windows/steps/.+\.ps1$') {
            Add-Issue "steps.$stepId StepFile 必须指向 windows/steps/*.ps1，实际: $stepFile"
        } else {
            Assert-PathExists "steps.$stepId StepFile" (Join-Path $script:InstallerRoot $stepFile)
        }

        if ($step.ContainsKey('SubModules') -and $null -ne $step['SubModules']) {
            foreach ($subModule in @($step['SubModules'])) {
                $subPath = [string]$subModule
                if ([string]::IsNullOrWhiteSpace($subPath)) { continue }
                if ($subPath -notmatch '^windows/steps/.+\.ps1$') {
                    Add-Issue "steps.$stepId SubModules 必须指向 windows/steps/*.ps1，实际: $subPath"
                } else {
                    Assert-PathExists "steps.$stepId SubModule" (Join-Path $script:InstallerRoot $subPath)
                }
            }
        }

        $macOSStepFile = [string]$step['MacOSStepFile']
        if ([string]::IsNullOrWhiteSpace($macOSStepFile)) {
            Add-Issue "steps.$stepId 缺少 MacOSStepFile"
        } elseif ($macOSStepFile -notmatch '^macos/steps/.+\.zsh$') {
            Add-Issue "steps.$stepId MacOSStepFile 必须指向 macos/steps/*.zsh，实际: $macOSStepFile"
        } else {
            Assert-PathExists "steps.$stepId MacOSStepFile" (Join-Path $script:InstallerRoot $macOSStepFile)
        }
    }

    $groups = Get-StepGroups
    Assert-Equal 'groups.Basic.Label' $groups['Basic']['Label'] $Contract['Groups']['Basic']['Label']
    Assert-Equal 'groups.Basic.Description' $groups['Basic']['Description'] $Contract['Groups']['Basic']['Description']
    Assert-Equal 'groups.Basic.InstallMode' $groups['Basic']['InstallMode'] $Contract['Groups']['Basic']['InstallMode']
    Assert-Equal 'groups.Basic.StepIds' @($groups['Basic']['StepIds']) @($Contract['Groups']['Basic']['StepIds'])
    Assert-Equal 'groups.Advanced.Label' $groups['Advanced']['Label'] $Contract['Groups']['Advanced']['Label']
    Assert-Equal 'groups.Advanced.Description' $groups['Advanced']['Description'] $Contract['Groups']['Advanced']['Description']
    Assert-Equal 'groups.Advanced.InstallMode' $groups['Advanced']['InstallMode'] $Contract['Groups']['Advanced']['InstallMode']
    Assert-Equal 'groups.Advanced.StepIds' @($groups['Advanced']['StepIds']) @($Contract['Groups']['Advanced']['StepIds'])

    Assert-Equal 'directory.installer-root' 'installer' $Contract['DirectoryPolicy']['InstallerRoot']
    Assert-Equal 'directory.must-not-rename' 'src' $Contract['DirectoryPolicy']['MustNotRenameTo']
    Assert-Equal 'directory.runtime-core.windows' 'installer/windows/core' $Contract['DirectoryPolicy']['RuntimeCoreDirectories']['Windows']
    Assert-Equal 'directory.runtime-core.macos' 'installer/macos/core' $Contract['DirectoryPolicy']['RuntimeCoreDirectories']['MacOS']
}

function Test-ProvidersContract {
    param([Parameter(Mandatory)][hashtable]$Contract)

    $managedEnv = $Contract['ManagedEnv']
    Assert-Equal 'providers.model-env-keys' @($script:ProviderManagedModelEnvKeys) @($managedEnv['ProviderManagedModelEnvKeys'])
    Assert-Equal 'providers.model-env-labels' $script:ProviderModelEnvLabels $managedEnv['ProviderModelEnvLabels']
    Assert-Equal 'providers.extra-env-keys' @($script:ProviderManagedExtraEnvKeys) @($managedEnv['ProviderManagedExtraEnvKeys'])
    Assert-Equal 'providers.legacy-model-key' $script:LegacyProviderModelKey $managedEnv['LegacyProviderModelKey']

    $providerFields = @(
        'Name', 'Description', 'BaseUrl', 'PlatformUrl',
        'ModelEnv', 'ExtraEnv', 'RequireModelConfig'
    )
    $contractProviders = $Contract['BuiltinProviders']
    Assert-Equal 'providers.keys' @($script:BuiltinProviders.Keys | Sort-Object) @($contractProviders.Keys | Sort-Object)

    foreach ($key in @($script:BuiltinProviders.Keys | Sort-Object)) {
        if (-not $contractProviders.ContainsKey($key)) {
            Add-Issue "providers.$key 缺少 contracts 条目"
            continue
        }
        $expected = Select-HashtableFields -Item $script:BuiltinProviders[$key] -Fields $providerFields
        $actual = Select-HashtableFields -Item $contractProviders[$key] -Fields $providerFields
        Assert-Equal "providers.$key" $expected $actual
    }

    Invoke-ContractCheck 'providers.fallback' {
        Assert-ProviderFallbackConsistency -ContractConfig (ConvertTo-ProviderRuntimeConfig -Contract $Contract)
    }
}

function Resolve-McpServerComparable {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Server)

    $fields = @(
        'Name', 'Description', 'McpType', 'Command', 'Args', 'CredentialType',
        'Url', 'UrlTemplate', 'Credentials', 'ApiKeyName', 'ApiKeyUrl',
        'ArgsCredentials', 'TokenArg', 'TokenLabel', 'TokenUrl', 'Note',
        'Category', 'Priority', 'Recommended'
    )
    $result = Select-HashtableFields -Item $Server -Fields $fields
    if ($Server.ContainsKey('RuntimeDeps')) {
        if ((ConvertTo-ComparableJson $Server['RuntimeDeps']) -eq (ConvertTo-ComparableJson $script:DefaultMcpRuntimeDeps)) {
            $result['RuntimeDepsRef'] = 'DefaultMcpRuntimeDeps'
        } else {
            $result['RuntimeDeps'] = $Server['RuntimeDeps']
        }
    }
    return $result
}

function Test-McpContract {
    param([Parameter(Mandatory)][hashtable]$Contract)

    Assert-Equal 'mcp.meta.file-name' $script:McpMetaFileName $Contract['McpMeta']['FileName']
    Assert-Equal 'mcp.meta.schema-version' $script:McpMetaSchemaVersion $Contract['McpMeta']['SchemaVersion']
    Assert-Equal 'mcp.runtime-deps' @($script:DefaultMcpRuntimeDeps) @($Contract['DefaultMcpRuntimeDeps'])

    $contractServers = $Contract['McpServers']
    Assert-Equal 'mcp.servers.keys' @($script:McpServers.Keys | Sort-Object) @($contractServers.Keys | Sort-Object)
    foreach ($serverId in @($script:McpServers.Keys | Sort-Object)) {
        if (-not $contractServers.ContainsKey($serverId)) {
            Add-Issue "mcp.servers.$serverId 缺少 contracts 条目"
            continue
        }
        $expected = Resolve-McpServerComparable -Server $script:McpServers[$serverId]
        $actual = Select-HashtableFields -Item $contractServers[$serverId] -Fields @(
            'Name', 'Description', 'McpType', 'Command', 'Args', 'CredentialType',
            'Url', 'UrlTemplate', 'Credentials', 'ApiKeyName', 'ApiKeyUrl',
            'ArgsCredentials', 'TokenArg', 'TokenLabel', 'TokenUrl', 'Note',
            'Category', 'Priority', 'Recommended', 'RuntimeDepsRef', 'RuntimeDeps'
        )
        Assert-Equal "mcp.servers.$serverId" $expected $actual
    }

    $contractCategories = $Contract['McpRulesCategories']
    Assert-Equal 'mcp.rules.keys' @($script:McpRulesCategories.Keys | Sort-Object) @($contractCategories.Keys | Sort-Object)
    foreach ($category in @($script:McpRulesCategories.Keys | Sort-Object)) {
        if (-not $contractCategories.ContainsKey($category)) {
            Add-Issue "mcp.rules.$category 缺少 contracts 条目"
            continue
        }
        Assert-Equal "mcp.rules.$category" $script:McpRulesCategories[$category] $contractCategories[$category]
    }

    Invoke-ContractCheck 'mcp.fallback' {
        Assert-McpFallbackConsistency -ContractConfig (ConvertTo-McpRuntimeConfig -Contract $Contract)
    }
}

function Test-ClaudeConfigContract {
    param([Parameter(Mandatory)][hashtable]$Contract)

    Assert-Equal 'claude-config.env-defaults' $script:ClaudeConfigEnvDefaults $Contract['ClaudeConfigEnvDefaults']
    Assert-Equal 'claude-config.deprecated-env-keys' @($script:ClaudeConfigDeprecatedEnvKeys) @($Contract['ClaudeConfigDeprecatedEnvKeys'])
    Assert-Equal 'claude-config.base-permissions' @($script:ClaudeConfigBasePermissions) @($Contract['ClaudeConfigBasePermissions'])
    Assert-Equal 'claude-config.language' '简体中文' $Contract['TopLevelDefaults']['language']
    Assert-Equal 'claude-config.always-thinking' $true $Contract['TopLevelDefaults']['alwaysThinkingEnabled']
    Assert-Equal 'claude-config.plans-directory' '.claude/plan' $Contract['TopLevelDefaults']['plansDirectory']

    Invoke-ContractCheck 'claude-config.fallback' {
        Assert-ClaudeConfigFallbackConsistency -ContractConfig (ConvertTo-ClaudeConfigRuntimeConfig -Contract $Contract)
    }
}

function Test-TemplatesContract {
    param([Parameter(Mandatory)][hashtable]$Contract)

    $templateIds = @($Contract['Templates'] | ForEach-Object { [string]$_['Id'] })
    foreach ($requiredId in @(
        'claude-md.global.windows',
        'claude-md.global.macos',
        'mcp-rules.search',
        'mcp-rules.documentation',
        'mcp-rules.development'
    )) {
        if ($templateIds -notcontains $requiredId) {
            Add-Issue "templates 缺少条目: $requiredId"
        }
    }

    foreach ($template in @($Contract['Templates'])) {
        $id = [string]$template['Id']
        $source = [string]$template['Source']
        if ($source -match '^installer/(core|steps)/') {
            Add-Issue "templates.$id Source 仍引用旧 Windows 路径: $source"
            continue
        }
        if ($source -match '^installer/windows/' -or $source -match '^installer/macos/') {
            Assert-PathExists "templates.$id Source" (Join-Path $script:RepoRoot $source)
        }
    }
}

function Test-BuildManifestContract {
    param([Parameter(Mandatory)][hashtable]$Contract)

    Assert-Equal 'build.default-output-directory' 'dist' $Contract['DefaultOutputDirectory']

    $windowsArtifacts = @($Contract['Windows']['Artifacts'])
    $macOSArtifacts = @($Contract['MacOS']['Artifacts'])
    $windowsOutputs = @($windowsArtifacts | ForEach-Object { [string]$_['OutputFile'] })
    $macOSOutputs = @($macOSArtifacts | ForEach-Object { [string]$_['OutputFile'] })
    $allOutputs = @($windowsOutputs + $macOSOutputs)

    Assert-Equal 'build.windows.outputs' @('bootstrap.ps1', 'install.ps1', 'manage.ps1') $windowsOutputs
    Assert-Equal 'build.macos.outputs' @('install.sh', 'manage.sh') $macOSOutputs
    Assert-Equal 'build.all.outputs' @('bootstrap.ps1', 'install.ps1', 'manage.ps1', 'install.sh', 'manage.sh') $allOutputs

    foreach ($output in $allOutputs) {
        if ($output -in @('ccq.ps1', 'ccq.sh') -or $output -match '^ccq-' -or $output -match '\.built\.') {
            Add-Issue "build artifact 名称不应使用旧支持形态: $output"
        }
    }

    foreach ($artifact in $windowsArtifacts) {
        $role = [string]$artifact['Role']
        $entryFile = [string]$artifact['EntryFile']
        if ($entryFile -notmatch '^windows/.+\.ps1$') {
            Add-Issue "build.Windows.$role EntryFile 必须指向 windows/*.ps1，实际: $entryFile"
        } else {
            Assert-PathExists "build.Windows.$role EntryFile" (Join-Path $script:InstallerRoot $entryFile)
        }
        foreach ($coreFile in @($artifact['CoreFiles'])) {
            $corePath = [string]$coreFile
            if ($corePath -notmatch '^windows/core/.+\.ps1$') {
                Add-Issue "build.Windows.$role CoreFiles 必须指向 windows/core/*.ps1，实际: $corePath"
            } else {
                Assert-PathExists "build.Windows.$role CoreFile" (Join-Path $script:InstallerRoot $corePath)
            }
        }
    }

    foreach ($artifact in $macOSArtifacts) {
        $role = [string]$artifact['Role']
        $entryFile = [string]$artifact['EntryFile']
        if ($entryFile -notmatch '^macos/.+\.zsh$') {
            Add-Issue "build.MacOS.$role EntryFile 必须指向 macos/*.zsh，实际: $entryFile"
        } else {
            Assert-PathExists "build.MacOS.$role EntryFile" (Join-Path $script:InstallerRoot $entryFile)
        }
    }

    Assert-PathExists 'build.ps1' (Join-Path $script:InstallerRoot 'build.ps1')
    Assert-PathExists 'build.sh' (Join-Path $script:InstallerRoot 'build.sh')

    $buildPs1 = Get-Content -Path (Join-Path $script:InstallerRoot 'build.ps1') -Raw -Encoding UTF8
    $buildSh = Get-Content -Path (Join-Path $script:InstallerRoot 'build.sh') -Raw -Encoding UTF8
    if ($buildPs1 -notmatch 'contracts[\\/]build\.json') {
        Add-Issue 'installer/build.ps1 未读取共享构建清单 contracts/build.json'
    }
    if ($buildSh -notmatch "readJson\('contracts/build\.json'\)") {
        Add-Issue 'installer/build.sh 未读取共享构建清单 contracts/build.json'
    }
}

function Test-CanonicalSourceLayout {
    Assert-PathExists 'WindowsRoot' $script:WindowsRoot -PathType Container
    Assert-PathExists 'Windows core root' $script:CoreRoot -PathType Container
    Assert-PathExists 'Windows steps root' $script:StepsRoot -PathType Container

    foreach ($legacyPath in @(
        'Bootstrap-ClaudeEnv.ps1',
        'Install-ClaudeEnv.ps1',
        'Manage-ClaudeEnv.ps1',
        'core',
        'steps',
        'build/Build-SingleFile.ps1'
    )) {
        Assert-PathAbsent "legacy.$legacyPath" (Join-Path $script:InstallerRoot $legacyPath)
    }

    $distPath = Join-Path $script:RepoRoot 'dist'
    if (Test-Path $distPath -PathType Container) {
        foreach ($file in @(Get-ChildItem -Path $distPath -File)) {
            if ($file.Name -in @('ccq.ps1', 'ccq.sh') -or $file.Name -match '^ccq-' -or $file.Name -match '\.built\.') {
                Add-Issue "dist 中存在旧 artifact: $($file.Name)"
            }
        }
    }
}

# dot-source 必须发生在脚本作用域；若放在函数内，Registry/Provider 等函数会随函数返回而失效。
. (Join-Path $script:CoreRoot 'Ui.ps1')
. (Join-Path $script:CoreRoot 'Process.ps1')
. (Join-Path $script:CoreRoot 'Profile.ps1')
. (Join-Path $script:CoreRoot 'Admin.ps1')
. (Join-Path $script:CoreRoot 'Net.ps1')
. (Join-Path $script:CoreRoot 'Registry.ps1')
. (Join-Path $script:CoreRoot 'McpManager.ps1')
. (Join-Path $script:CoreRoot 'Provider.ps1')
. (Join-Path $script:StepsRoot 'ClaudeConfig.ps1')

function Main {
    if (-not (Test-Path $script:InstallerRoot -PathType Container)) {
        throw "InstallerRoot 不是有效目录: $script:InstallerRoot"
    }

    Test-CanonicalSourceLayout
    Test-StepsContract -Contract (Read-ContractJson 'steps.json')
    Test-ProvidersContract -Contract (Read-ContractJson 'providers.json')
    Test-McpContract -Contract (Read-ContractJson 'mcp-servers.json')
    Test-ClaudeConfigContract -Contract (Read-ContractJson 'claude-config.json')
    Test-TemplatesContract -Contract (Read-ContractJson 'templates/index.json')
    Test-BuildManifestContract -Contract (Read-ContractJson 'build.json')

    if ($script:Issues.Count -gt 0) {
        Write-Host "[FAIL] contracts 一致性检查失败 ($($script:Issues.Count) 项)" -ForegroundColor Red
        foreach ($issue in $script:Issues) {
            Write-Host "- $issue" -ForegroundColor Red
        }
        exit 1
    }

    Write-Host "[PASS] contracts 一致性检查通过" -ForegroundColor Green
}

Main
