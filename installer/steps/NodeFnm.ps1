# NodeFnm.ps1 - Node.js 通过 fnm 安装和配置
# 作者: 哈雷酱 (本小姐的 Node.js 管理杰作！)
# 功能: 使用 fnm 安装和管理 Node.js，配置 $PROFILE 而不写入环境变量

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$scriptRoot\core\Process.ps1"
. "$scriptRoot\core\Profile.ps1"
. "$scriptRoot\core\Ui.ps1"
. "$scriptRoot\core\Net.ps1"

# 全局配置
$script:RequiredNodeVersion = "20"  # Node.js LTS 版本
$script:FnmVersion = "latest"

function Get-NodeCommandSource {
    <#
    .SYNOPSIS
    根据命令路径推断 Node.js 来源（fnm/nvm/direct/unknown）
    .PARAMETER ResolvedPath
    命令的完整路径
    .PARAMETER NvmHome
    NVM_HOME 环境变量值
    .PARAMETER DirectNodePath
    直接安装的 Node.js 路径
    .RETURNS
    来源标识字符串
    #>
    param(
        [string]$ResolvedPath,
        [string]$NvmHome,
        [string]$DirectNodePath
    )

    if ([string]::IsNullOrWhiteSpace($ResolvedPath)) { return "unknown" }

    $normalizedPath = $ResolvedPath.Replace("/", "\").Trim().ToLower()

    # 检测 fnm
    if ($normalizedPath -match '\\\.fnm\\' -or $normalizedPath -match '\\fnm\\node-versions\\') {
        return "fnm"
    }

    # 检测 nvm
    if (-not [string]::IsNullOrWhiteSpace($NvmHome)) {
        $normalizedNvmHome = $NvmHome.Replace("/", "\").TrimEnd("\").ToLower()
        if ($normalizedPath.StartsWith($normalizedNvmHome)) { return "nvm" }
    }
    if ($normalizedPath -match '\\nvm\\') { return "nvm" }

    # 检测直接安装
    if (-not [string]::IsNullOrWhiteSpace($DirectNodePath)) {
        $normalizedDirectNodePath = $DirectNodePath.Replace("/", "\").TrimEnd("\").ToLower()
        if ($normalizedPath.StartsWith($normalizedDirectNodePath)) { return "direct" }
    }
    if ($normalizedPath -like "*\\program files\\nodejs\\*") { return "direct" }

    return "unknown"
}

function Test-NodeFnmInstalled {
    <#
    .SYNOPSIS
    测试步骤 01 是否已完成（Node.js 和 fnm 安装）
    .RETURNS
    测试结果对象
    #>
    param()

    $result = @{
        IsInstalled = $false
        Version = ""
        Data = @{}
        Message = ""
    }

    try {
        Write-UiInfo "🔍 检查 Node.js 和 fnm 安装状态..."

        # 检查 fnm/node/npm 是否可用（使用 ReturnDetails 获取完整信息）
        $fnmDetails = Test-CommandAvailable -Command "fnm" -ReturnDetails
        $nodeDetails = Test-CommandAvailable -Command "node" -ReturnDetails
        $npmDetails = Test-CommandAvailable -Command "npm" -ReturnDetails

        $fnmAvailable = [bool]$fnmDetails.Available
        $nodeAvailable = [bool]$nodeDetails.Available
        $npmAvailable = [bool]$npmDetails.Available

        # 检测 nvm-windows（多信号合并）
        $nvmCommandAvailable = Test-CommandAvailable -Command "nvm"
        $nvmHome = [Environment]::GetEnvironmentVariable("NVM_HOME", "Process")
        if ([string]::IsNullOrWhiteSpace($nvmHome)) {
            $nvmHome = [Environment]::GetEnvironmentVariable("NVM_HOME", "User")
        }
        if ([string]::IsNullOrWhiteSpace($nvmHome)) {
            $nvmHome = [Environment]::GetEnvironmentVariable("NVM_HOME", "Machine")
        }
        $nvmDefaultPath = Join-Path $env:APPDATA "nvm"
        $nvmDirExists = Test-Path $nvmDefaultPath -PathType Container
        $nvmRegistryExists = Test-Path "HKCU:\Software\nvm-windows"
        $nvmDetected = $nvmCommandAvailable -or (-not [string]::IsNullOrWhiteSpace($nvmHome)) -or $nvmDirExists -or $nvmRegistryExists

        # 检测直接安装的 Node.js
        $directNodePath = Join-Path $env:ProgramFiles "nodejs"
        $directNodeDirExists = Test-Path $directNodePath -PathType Container
        $directNodeRegistryExists = (Test-Path "HKLM:\SOFTWARE\Node.js") -or (Test-Path "HKLM:\SOFTWARE\WOW6432Node\Node.js")
        $directNodeDetected = $directNodeDirExists -or $directNodeRegistryExists

        # 检测 winget 安装记录（辅助信号）
        $wingetAvailable = Test-CommandAvailable -Command "winget"
        $wingetNodeInstalled = $false
        if ($wingetAvailable) {
            try {
                $wingetResult = Invoke-ExternalCommand -Command "winget" -Arguments @("list", "--id", "OpenJS.NodeJS", "-e", "--disable-interactivity") -SuppressOutput -TimeoutSeconds 30 -RetryCount 0
                if ($wingetResult.Success -and $wingetResult.Output -and $wingetResult.Output -match "OpenJS\.NodeJS") {
                    $wingetNodeInstalled = $true
                }
            } catch {
                Write-UiWarn "⚠ winget list Node.js 检测失败: $($_.Exception.Message)"
            }
        }
        if ($wingetNodeInstalled) {
            $directNodeDetected = $true
        }

        # 推断 node/npm 的来源路径
        $nodePathSource = Get-NodeCommandSource -ResolvedPath $nodeDetails.ResolvedPath -NvmHome $nvmHome -DirectNodePath $directNodePath
        $npmPathSource = Get-NodeCommandSource -ResolvedPath $npmDetails.ResolvedPath -NvmHome $nvmHome -DirectNodePath $directNodePath

        # 综合判定 Node 来源（优先使用"活跃命令路径"信号，避免残留目录导致误判 mixed）
        $sourceSignals = @{}
        if ($nodePathSource -ne "unknown") { $sourceSignals[$nodePathSource] = $true }
        if ($npmPathSource -ne "unknown") { $sourceSignals[$npmPathSource] = $true }
        if ($sourceSignals.Count -eq 0) {
            if ($fnmAvailable -and -not $nvmDetected -and -not $directNodeDetected) {
                $sourceSignals["fnm"] = $true
            } elseif ($nvmDetected -and -not $directNodeDetected) {
                $sourceSignals["nvm"] = $true
            } elseif ($directNodeDetected -and -not $nvmDetected) {
                $sourceSignals["direct"] = $true
            }
        }

        $sourceKeys = @($sourceSignals.Keys)
        $nodeSource = "unknown"
        if ($sourceKeys.Count -gt 1) {
            $nodeSource = "mixed"
        } elseif ($sourceKeys.Count -eq 1) {
            $nodeSource = $sourceKeys[0]
        }

        # 冲突类型判定（关注 nvm 与 direct Node，fnm 本身不算冲突）
        $conflictType = "none"
        if ($nvmDetected -and $directNodeDetected) {
            $conflictType = "mixed"
        } elseif ($nvmDetected) {
            $conflictType = "nvm-only"
        } elseif ($directNodeDetected) {
            $conflictType = "direct-only"
        }

        $conflictDetails = @()
        if ($nvmDetected) {
            $conflictDetails += "检测到 nvm-windows（命令/环境变量/目录/注册表命中）"
        }
        if ($directNodeDetected) {
            $conflictDetails += "检测到直接安装 Node.js（ProgramFiles/注册表/winget 命中）"
        }
        if ($nodeSource -eq "mixed") {
            $conflictDetails += "Node 来源混合，可能存在 PATH 优先级冲突"
        }

        # 保存检测数据
        $result.Data["FnmAvailable"] = $fnmAvailable
        $result.Data["FnmPath"] = $fnmDetails.ResolvedPath
        $result.Data["NodeAvailable"] = $nodeAvailable
        $result.Data["NodePath"] = $nodeDetails.ResolvedPath
        $result.Data["NpmAvailable"] = $npmAvailable
        $result.Data["NpmPath"] = $npmDetails.ResolvedPath

        $result.Data["NvmDetected"] = $nvmDetected
        $result.Data["NvmCommandAvailable"] = $nvmCommandAvailable
        $result.Data["NvmHome"] = $nvmHome
        $result.Data["NvmDefaultPath"] = $nvmDefaultPath
        $result.Data["NvmRegistryDetected"] = $nvmRegistryExists

        $result.Data["DirectNodeDetected"] = $directNodeDetected
        $result.Data["DirectNodePath"] = $directNodePath
        $result.Data["DirectNodeRegistryDetected"] = $directNodeRegistryExists
        $result.Data["WingetAvailable"] = $wingetAvailable
        $result.Data["WingetNodeInstalled"] = $wingetNodeInstalled

        $result.Data["NodePathSource"] = $nodePathSource
        $result.Data["NpmPathSource"] = $npmPathSource
        $result.Data["NodeSource"] = $nodeSource
        $result.Data["ConflictType"] = $conflictType
        $result.Data["ConflictDetails"] = $conflictDetails

        # 获取 nvm 版本
        $nvmVersion = "未知"
        if ($nvmCommandAvailable) {
            $nvmVersion = Get-CommandVersion -Command "nvm"
        }
        $result.Data["NvmVersion"] = $nvmVersion

        # 输出检测结果
        if ($fnmAvailable) {
            $fnmVersion = Get-CommandVersion -Command "fnm"
            $result.Data["FnmVersion"] = $fnmVersion
            Write-UiSuccess "✓ fnm 已安装 (版本: $fnmVersion)"
        } else {
            Write-UiWarn "⚠ fnm 未安装（允许继续使用现有 Node.js 环境）"
        }

        if ($nvmDetected) {
            Write-UiWarn "⚠ 检测到 nvm-windows 环境"
            if ($nvmHome) {
                Write-UiInfo "  NVM_HOME: $nvmHome"
            }
            if ($nvmCommandAvailable) {
                Write-UiInfo "  nvm 版本: $nvmVersion"
            }
        }

        if ($directNodeDetected) {
            Write-UiWarn "⚠ 检测到直接安装的 Node.js 环境"
            Write-UiInfo "  默认路径: $directNodePath"
            if ($wingetNodeInstalled) {
                Write-UiInfo "  winget 安装记录: OpenJS.NodeJS"
            }
        }

        $nodeVersionSatisfied = $false
        if ($nodeAvailable) {
            $nodeVersion = Get-CommandVersion -Command "node"
            $result.Data["NodeVersion"] = $nodeVersion
            Write-UiSuccess "✓ Node.js 已安装 (版本: $nodeVersion)"
            if ($nodeDetails.ResolvedPath) {
                Write-UiInfo "  路径: $($nodeDetails.ResolvedPath)"
            }

            # 检查版本是否满足要求
            if ($nodeVersion -match '^v?(\d+)\.') {
                $versionNumber = [int]$matches[1]
                if ($versionNumber -ge [int]$script:RequiredNodeVersion) {
                    $result.Version = $nodeVersion
                    $nodeVersionSatisfied = $true
                    Write-UiSuccess "✓ Node.js 版本满足要求 (需要: v$script:RequiredNodeVersion+)"
                } else {
                    Write-UiWarn "⚠ Node.js 版本过低 (当前: $nodeVersion, 需要: v$script:RequiredNodeVersion+)"
                }
            } else {
                Write-UiWarn "⚠ 无法解析 Node.js 版本号: $nodeVersion"
            }
        } else {
            Write-UiWarn "⚠ Node.js 未安装"
        }

        if ($npmAvailable) {
            $npmVersion = Get-CommandVersion -Command "npm"
            $result.Data["NpmVersion"] = $npmVersion
            Write-UiSuccess "✓ npm 已安装 (版本: $npmVersion)"
            if ($npmDetails.ResolvedPath) {
                Write-UiInfo "  路径: $($npmDetails.ResolvedPath)"
            }
        } else {
            Write-UiWarn "⚠ npm 未安装"
        }

        Write-UiInfo "Node 来源判定: $nodeSource"
        Write-UiInfo "冲突类型: $conflictType"

        # 检查 $PROFILE 中的 fnm 配置
        $profilePath = $PROFILE
        if (Test-Path $profilePath) {
            $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
            if ($profileContent -and $profileContent -match "fnm") {
                $result.Data["ProfileConfigured"] = $true
                Write-UiSuccess "✓ PowerShell Profile 中已配置 fnm 初始化"
            } else {
                $result.Data["ProfileConfigured"] = $false
                Write-UiWarn "⚠ PowerShell Profile 中未配置 fnm 初始化"
            }
        } else {
            $result.Data["ProfileConfigured"] = $false
            Write-UiWarn "⚠ PowerShell Profile 文件不存在"
        }

        # 判断是否已满足运行时要求
        # 注意：若存在冲突且当前并非 fnm 管理，不应标记为已安装，否则生命周期会跳过 Install 阶段，冲突菜单无法触发
        if ($nodeAvailable -and $npmAvailable -and $nodeVersionSatisfied) {
            if ($conflictType -ne "none" -and -not $fnmAvailable) {
                $result.IsInstalled = $false
                $result.Data["NeedsConflictResolution"] = $true
                $result.Message = "检测到可用 Node.js，但存在环境冲突，需进入安装阶段处理"
            } else {
                $result.IsInstalled = $true
                if ($fnmAvailable -and $result.Data["ProfileConfigured"]) {
                    $result.Message = "Node.js 运行时已就绪（fnm 管理）"
                } else {
                    $result.Message = "Node.js 运行时已就绪（来源: $nodeSource）"
                }
            }
        } else {
            $result.Message = "Node.js 运行时不完整，需要安装或修复"
        }

    } catch {
        $result.Message = "Node.js 安装状态检查失败: $($_.Exception.Message)"
        Write-UiWarn "⚠ $($result.Message)"
    }

    return $result
}

function Resolve-NpmForBackup {
    <#
    .SYNOPSIS
    利用 snapshot 中的环境信息，主动定位并激活 npm（修复 PATH 缺失问题）
    .PARAMETER EnvSnapshot
    Test-NodeFnmInstalled 返回的 Data 哈希表
    .RETURNS
    @{ Available = [bool]; Method = [string]; ErrorMessage = [string] }
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$EnvSnapshot
    )

    # 1. npm 已在 PATH，无需修复
    if (Test-CommandAvailable -Command "npm") {
        return @{ Available = $true; Method = "already-in-path"; ErrorMessage = "" }
    }

    Write-UiWarn "npm 不在当前 PATH 中，尝试定位..."

    # 2. 尝试通过 snapshot 中记录的 NpmPath 直接定位
    $npmPath = [string]$EnvSnapshot["NpmPath"]
    if ($npmPath -and (Test-Path $npmPath -PathType Leaf)) {
        $npmDir = Split-Path -Parent $npmPath
        Write-UiInfo "  从 snapshot 定位到 npm: $npmDir"
        $env:PATH = "$npmDir;$env:PATH"
        if (Test-CommandAvailable -Command "npm") {
            Write-UiSuccess "通过 snapshot 路径恢复 npm 可用性"
            return @{ Available = $true; Method = "snapshot-path"; ErrorMessage = "" }
        }
    }

    # 3. nvm 场景：尝试激活 nvm 或从 NvmHome 子目录查找
    if ([bool]$EnvSnapshot["NvmDetected"]) {
        # 3a. nvm 命令可用 - 尝试 nvm use
        if ([bool]$EnvSnapshot["NvmCommandAvailable"]) {
            Write-UiInfo "  尝试通过 nvm 激活 Node.js 环境..."
            try {
                $nvmListResult = Invoke-ExternalCommand -Command "nvm" -Arguments @("list") -SuppressOutput -TimeoutSeconds 15 -RetryCount 0
                if ($nvmListResult.Success -and $nvmListResult.Output) {
                    $versions = $nvmListResult.Output -split "`n" | ForEach-Object {
                        if ($_ -match '(\d+\.\d+\.\d+)') { $matches[1] }
                    } | Where-Object { $_ }
                    if ($versions) {
                        $targetVersion = $versions | Select-Object -First 1
                        Write-UiInfo "  执行 nvm use $targetVersion..."
                        $useResult = Invoke-ExternalCommand -Command "nvm" -Arguments @("use", $targetVersion) -SuppressOutput -TimeoutSeconds 30 -RetryCount 0
                        Refresh-SessionPath
                        if (Test-CommandAvailable -Command "npm") {
                            Write-UiSuccess "通过 nvm use $targetVersion 恢复 npm 可用性"
                            return @{ Available = $true; Method = "nvm-use"; ErrorMessage = "" }
                        }
                    }
                }
            } catch {
                Write-UiWarn "  nvm 激活失败: $($_.Exception.Message)"
            }
        }

        # 3b. 直接扫描 NvmHome 子目录
        $nvmHome = [string]$EnvSnapshot["NvmHome"]
        if ([string]::IsNullOrWhiteSpace($nvmHome)) {
            $nvmHome = [string]$EnvSnapshot["NvmDefaultPath"]
        }
        if ($nvmHome -and (Test-Path $nvmHome)) {
            $nvmNodeDirs = Get-ChildItem -Path $nvmHome -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName "npm.cmd") }
            if ($nvmNodeDirs) {
                $bestDir = $nvmNodeDirs | Sort-Object Name -Descending | Select-Object -First 1
                Write-UiInfo "  从 NvmHome 定位到 npm: $($bestDir.FullName)"
                $env:PATH = "$($bestDir.FullName);$env:PATH"
                if (Test-CommandAvailable -Command "npm") {
                    Write-UiSuccess "通过 NvmHome 目录恢复 npm 可用性"
                    return @{ Available = $true; Method = "nvm-dir-scan"; ErrorMessage = "" }
                }
            }
        }
    }

    # 4. 直接安装场景：从 ProgramFiles\nodejs 定位
    if ([bool]$EnvSnapshot["DirectNodeDetected"]) {
        $directPath = [string]$EnvSnapshot["DirectNodePath"]
        if ([string]::IsNullOrWhiteSpace($directPath)) {
            $directPath = "$env:ProgramFiles\nodejs"
        }
        if ((Test-Path $directPath) -and (Test-Path (Join-Path $directPath "npm.cmd"))) {
            Write-UiInfo "  从直接安装路径定位到 npm: $directPath"
            $env:PATH = "$directPath;$env:PATH"
            if (Test-CommandAvailable -Command "npm") {
                Write-UiSuccess "通过直接安装路径恢复 npm 可用性"
                return @{ Available = $true; Method = "direct-path"; ErrorMessage = "" }
            }
        }
    }

    # 5. 最终回退：PATH 刷新后重试
    Refresh-SessionPath
    if (Test-CommandAvailable -Command "npm") {
        Write-UiSuccess "PATH 刷新后 npm 可用"
        return @{ Available = $true; Method = "path-refresh"; ErrorMessage = "" }
    }

    return @{ Available = $false; Method = "none"; ErrorMessage = "所有定位策略均失败，npm 无法激活" }
}

function Backup-NpmGlobalPackages {
    <#
    .SYNOPSIS
    备份 npm 全局包（名称和版本）
    .RETURNS
    备份结果对象
    #>
    param()

    $result = @{
        Success = $false
        Packages = @()
        ErrorMessage = ""
    }

    try {
        Write-UiInfo "📦 备份 npm 全局包列表..."

        # 注意：调用方应在调用前先执行 Resolve-NpmForBackup 确保 npm 可用
        if (-not (Test-CommandAvailable -Command "npm")) {
            Write-UiWarn "npm 命令不可用（已尝试所有定位策略），跳过全局包备份"
            $result.Success = $true
            $result.Packages = @()
            return $result
        }

        $listOutput = & npm list -g --json --depth=0 2>$null
        $npmExitCode = $LASTEXITCODE
        if (-not $listOutput) {
            if ($npmExitCode -ne 0) {
                throw "npm list -g 无输出且退出码为 $npmExitCode，无法安全备份全局包"
            }
            Write-UiWarn "⚠ npm list -g 返回为空，将按无全局包处理"
            $result.Success = $true
            return $result
        }

        $jsonText = ($listOutput -join "`n").Trim()
        try {
            $json = $jsonText | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "npm list -g 输出解析失败，无法安全备份全局包: $($_.Exception.Message)"
        }
        if ($npmExitCode -ne 0) {
            Write-UiWarn "⚠ npm list -g 退出码为 $npmExitCode，但已成功解析 JSON，继续迁移流程"
        }
        if ($json -and $json.dependencies) {
            foreach ($pkg in $json.dependencies.PSObject.Properties) {
                $pkgName = [string]$pkg.Name
                if ($pkgName -eq "npm") { continue }

                $pkgVersion = ""
                if ($pkg.Value -and $pkg.Value.PSObject.Properties.Name -contains "version") {
                    $pkgVersion = [string]$pkg.Value.version
                }

                $result.Packages += @{
                    Name = $pkgName
                    Version = $pkgVersion
                }
            }
        }

        $result.Success = $true
        Write-UiSuccess "✓ npm 全局包备份完成，共 $($result.Packages.Count) 个包"
    } catch {
        $result.ErrorMessage = "备份 npm 全局包失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Uninstall-ExistingNode {
    <#
    .SYNOPSIS
    卸载冲突的 Node.js 管理工具和直接安装版本
    .PARAMETER EnvSnapshot
    Test-NodeFnmInstalled 返回的环境快照 Data
    .RETURNS
    卸载结果对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$EnvSnapshot
    )

    $result = @{
        Success = $false
        ErrorMessage = ""
        CleanedPaths = @()
    }

    try {
        $cleanPaths = @()
        $cleanedPathMap = @{}

        # 收集待清理路径
        $candidatePaths = @(
            [string]$EnvSnapshot["NvmHome"],
            [string]$EnvSnapshot["NvmDefaultPath"],
            [string]$EnvSnapshot["DirectNodePath"],
            "$env:ProgramFiles\nodejs",
            "${env:ProgramFiles(x86)}\nodejs"
        )

        $nodePath = [string]$EnvSnapshot["NodePath"]
        if ($nodePath -and (Test-Path $nodePath -PathType Leaf)) {
            $candidatePaths += (Split-Path -Parent $nodePath)
        }
        $npmPath = [string]$EnvSnapshot["NpmPath"]
        if ($npmPath -and (Test-Path $npmPath -PathType Leaf)) {
            $candidatePaths += (Split-Path -Parent $npmPath)
        }

        foreach ($pathItem in $candidatePaths) {
            if ([string]::IsNullOrWhiteSpace($pathItem)) { continue }
            $normalized = $pathItem.Replace("/", "\").Trim().TrimEnd("\")
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                $cleanedPathMap[$normalized.ToLower()] = $normalized
            }
        }
        $cleanPaths = @($cleanedPathMap.Values)

        # 卸载 nvm-windows
        if ([bool]$EnvSnapshot["NvmDetected"]) {
            Write-UiWarn "⚠ 开始卸载 nvm-windows..."

            if (Test-CommandAvailable -Command "nvm") {
                try {
                    $nvmOffResult = Invoke-ExternalCommand -Command "nvm" -Arguments @("off") -SuppressOutput -TimeoutSeconds 30 -RetryCount 0
                    if ($nvmOffResult.Success) {
                        Write-UiSuccess "✓ 已执行 nvm off"
                    } else {
                        Write-UiWarn "⚠ nvm off 执行失败: $($nvmOffResult.Error)"
                    }
                } catch {
                    Write-UiWarn "⚠ nvm off 执行异常: $($_.Exception.Message)"
                }
            }

            if (Test-CommandAvailable -Command "winget") {
                try {
                    $nvmUninstall = Invoke-ExternalCommand -Command "winget" -Arguments @("uninstall", "--id", "CoreyButler.NVMforWindows", "-e", "--disable-interactivity") -SuppressOutput -TimeoutSeconds 240 -RetryCount 0
                    if ($nvmUninstall.Success) {
                        Write-UiSuccess "✓ winget 卸载 nvm-windows 成功"
                    } else {
                        Write-UiWarn "⚠ winget 卸载 nvm-windows 失败: $($nvmUninstall.Error)"
                    }
                } catch {
                    Write-UiWarn "⚠ winget 卸载 nvm-windows 异常: $($_.Exception.Message)"
                }
            } else {
                Write-UiWarn "⚠ winget 不可用，跳过 nvm-windows 自动卸载"
            }

            # 清理 nvm 目录
            $nvmFolders = @([string]$EnvSnapshot["NvmHome"], "$env:APPDATA\nvm")
            $nvmUnique = @{}
            foreach ($folder in $nvmFolders) {
                if ([string]::IsNullOrWhiteSpace($folder)) { continue }
                $normalizedFolder = $folder.Replace("/", "\").Trim().TrimEnd("\")
                $nvmUnique[$normalizedFolder.ToLower()] = $normalizedFolder
            }

            foreach ($folderPath in $nvmUnique.Values) {
                if (Test-Path $folderPath) {
                    try {
                        Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop
                        Write-UiSuccess "✓ 已清理目录: $folderPath"
                    } catch {
                        Write-UiWarn "⚠ 清理目录失败: $folderPath，原因: $($_.Exception.Message)"
                    }
                }
            }
        }

        # 卸载直接安装的 Node.js
        if ([bool]$EnvSnapshot["DirectNodeDetected"]) {
            Write-UiWarn "⚠ 开始卸载直接安装的 Node.js..."

            if (Test-CommandAvailable -Command "winget") {
                try {
                    $nodeUninstall = Invoke-ExternalCommand -Command "winget" -Arguments @("uninstall", "--id", "OpenJS.NodeJS", "-e", "--disable-interactivity") -SuppressOutput -TimeoutSeconds 240 -RetryCount 0
                    if ($nodeUninstall.Success) {
                        Write-UiSuccess "✓ winget 卸载 Node.js 成功"
                    } else {
                        Write-UiWarn "⚠ winget 卸载 Node.js 失败: $($nodeUninstall.Error)"
                    }
                } catch {
                    Write-UiWarn "⚠ winget 卸载 Node.js 异常: $($_.Exception.Message)"
                }
            } else {
                Write-UiWarn "⚠ winget 不可用，尝试注册表卸载"
            }

            # 从注册表查找卸载信息
            $uninstallKeyPaths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )

            $nodeUninstallItems = @()
            foreach ($keyPath in $uninstallKeyPaths) {
                try {
                    $items = Get-ItemProperty $keyPath -ErrorAction SilentlyContinue | Where-Object {
                        $_.DisplayName -like "Node.js*" -or $_.DisplayName -eq "Node.js"
                    }
                    if ($items) { $nodeUninstallItems += $items }
                } catch {
                    # 忽略单个注册表分支错误
                }
            }

            foreach ($item in $nodeUninstallItems) {
                $uninstallString = ""
                if ($item.PSObject.Properties.Name -contains "QuietUninstallString" -and $item.QuietUninstallString) {
                    $uninstallString = [string]$item.QuietUninstallString
                } elseif ($item.PSObject.Properties.Name -contains "UninstallString" -and $item.UninstallString) {
                    $uninstallString = [string]$item.UninstallString
                }

                if (-not $uninstallString) { continue }

                try {
                    if ($uninstallString -match '\{[0-9A-Fa-f\-]{36}\}') {
                        $productCode = $matches[0]
                        $msiResult = Invoke-ExternalCommand -Command "msiexec" -Arguments @("/x", $productCode, "/quiet", "/norestart") -SuppressOutput -TimeoutSeconds 300 -RetryCount 0
                        if ($msiResult.Success) {
                            Write-UiSuccess "✓ msiexec 卸载成功: $($item.DisplayName)"
                        } else {
                            Write-UiWarn "⚠ msiexec 卸载失败: $($item.DisplayName)，$($msiResult.Error)"
                        }
                    } elseif ($uninstallString -match '(?i)msiexec(?:\.exe)?\s+.*\{[0-9A-Fa-f\-]{36}\}') {
                        $productCode = [regex]::Match($uninstallString, '\{[0-9A-Fa-f\-]{36}\}').Value
                        if ($productCode) {
                            $msiResult = Invoke-ExternalCommand -Command "msiexec" -Arguments @("/x", $productCode, "/quiet", "/norestart") -SuppressOutput -TimeoutSeconds 300 -RetryCount 0
                            if ($msiResult.Success) {
                                Write-UiSuccess "✓ msiexec 卸载成功: $($item.DisplayName)"
                            } else {
                                Write-UiWarn "⚠ msiexec 卸载失败: $($item.DisplayName)，$($msiResult.Error)"
                            }
                        } else {
                            Write-UiWarn "⚠ 无法提取 MSI ProductCode，跳过不安全卸载命令: $($item.DisplayName)"
                        }
                    } else {
                        Write-UiWarn "⚠ 跳过非 MSI 卸载命令（避免执行不受控命令）: $($item.DisplayName)"
                    }
                } catch {
                    Write-UiWarn "⚠ 卸载执行异常: $($item.DisplayName)，$($_.Exception.Message)"
                }
            }

            # 清理残留目录
            $directNodeFolders = @([string]$EnvSnapshot["DirectNodePath"], "$env:ProgramFiles\nodejs", "${env:ProgramFiles(x86)}\nodejs")
            foreach ($folderPath in $directNodeFolders) {
                if ([string]::IsNullOrWhiteSpace($folderPath)) { continue }
                if (Test-Path $folderPath) {
                    try {
                        Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop
                        Write-UiSuccess "✓ 已清理目录: $folderPath"
                    } catch {
                        Write-UiWarn "⚠ 清理目录失败: $folderPath，原因: $($_.Exception.Message)"
                    }
                }
            }
        }

        # 清理 PATH（当前会话 + 用户级）
        $targetMap = @{}
        foreach ($target in $cleanPaths) {
            $normalizedTarget = $target.Replace("/", "\").Trim().Trim('"').TrimEnd("\").ToLower()
            if (-not [string]::IsNullOrWhiteSpace($normalizedTarget)) {
                $targetMap[$normalizedTarget] = $true
            }
        }

        if ($targetMap.Keys.Count -gt 0) {
            # 清理当前会话 PATH
            $sessionKept = @()
            $sessionRemoved = @()
            foreach ($entry in ($env:PATH -split ";")) {
                $trimmed = $entry.Trim().Trim('"')
                if (-not $trimmed) { continue }
                $normalized = $trimmed.Replace("/", "\").TrimEnd("\").ToLower()
                if ($targetMap.ContainsKey($normalized)) {
                    $sessionRemoved += $trimmed
                } else {
                    $sessionKept += $trimmed
                }
            }
            if ($sessionRemoved.Count -gt 0) {
                $env:PATH = $sessionKept -join ";"
                $result.CleanedPaths += $sessionRemoved
            }

            # 清理用户级 PATH
            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($userPath) {
                $userKept = @()
                $userRemoved = @()
                foreach ($entry in ($userPath -split ";")) {
                    $trimmed = $entry.Trim().Trim('"')
                    if (-not $trimmed) { continue }
                    $normalized = $trimmed.Replace("/", "\").TrimEnd("\").ToLower()
                    if ($targetMap.ContainsKey($normalized)) {
                        $userRemoved += $trimmed
                    } else {
                        $userKept += $trimmed
                    }
                }
                if ($userRemoved.Count -gt 0) {
                    [Environment]::SetEnvironmentVariable("PATH", ($userKept -join ";"), "User")
                    $result.CleanedPaths += $userRemoved
                }
            }
        }

        Refresh-SessionPath

        # 卸载残留检查
        $residualIssues = @()
        if ([bool]$EnvSnapshot["NvmDetected"]) {
            if (Test-Path "$env:APPDATA\nvm") {
                $residualIssues += "$env:APPDATA\nvm 仍存在"
            }
        }
        if ([bool]$EnvSnapshot["DirectNodeDetected"]) {
            if (Test-Path "$env:ProgramFiles\nodejs") {
                $residualIssues += "$env:ProgramFiles\nodejs 仍存在"
            }
        }

        if ($residualIssues.Count -gt 0) {
            throw "卸载后仍检测到残留: $($residualIssues -join '; ')"
        }

        $result.Success = $true
        Write-UiSuccess "✓ 冲突工具卸载与 PATH 清理完成"
    } catch {
        $result.ErrorMessage = "卸载冲突环境失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Restore-NpmGlobalPackages {
    <#
    .SYNOPSIS
    恢复 npm 全局包
    .PARAMETER Packages
    备份的全局包数组（@{Name;Version}）
    .RETURNS
    恢复结果对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Packages
    )

    $result = @{
        Success = $true
        Installed = @()
        Failed = @()
    }

    if (-not $Packages -or $Packages.Count -eq 0) {
        Write-UiInfo "无 npm 全局包需要恢复"
        return $result
    }

    try {
        if (-not (Test-CommandAvailable -Command "npm")) {
            throw "npm 命令不可用，无法恢复全局包"
        }

        Write-UiInfo "📥 开始恢复 npm 全局包..."
        foreach ($pkg in $Packages) {
            $name = [string]$pkg.Name
            $version = [string]$pkg.Version
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $fullName = $name
            if (-not [string]::IsNullOrWhiteSpace($version)) {
                $fullName = "$name@$version"
            }

            try {
                $installResult = Invoke-ExternalCommand -Command "npm" -Arguments @("install", "-g", $fullName) -TimeoutSeconds 180 -RetryCount 0
                if ($installResult.Success) {
                    $result.Installed += $fullName
                    Write-UiSuccess "✓ 已恢复: $fullName"
                } else {
                    $result.Failed += @{ Name = $fullName; Error = $installResult.Error }
                    Write-UiWarn "⚠ 恢复失败: $fullName，$($installResult.Error)"
                }
            } catch {
                $result.Failed += @{ Name = $fullName; Error = $_.Exception.Message }
                Write-UiWarn "⚠ 恢复异常: $fullName，$($_.Exception.Message)"
            }
        }

        if ($result.Failed.Count -gt 0) {
            $result.Success = $false
        }
    } catch {
        $result.Success = $false
        $result.Failed += @{ Name = "全部"; Error = $_.Exception.Message }
        Write-UiWarn "⚠ npm 全局包恢复过程中断: $($_.Exception.Message)"
    }

    return $result
}

function Install-NodeFnm {
    <#
    .SYNOPSIS
    执行步骤 01 安装（fnm + Node.js + $PROFILE 配置）
    .RETURNS
    安装结果对象
    #>
    param()

    $result = @{
        Success = $false
        Data = @{}
        ErrorMessage = ""
        Message = ""
    }

    try {
        Write-UiInfo "📦 开始安装 fnm 和 Node.js..."

        $shouldRestoreGlobalPackages = $false
        $globalPackagesBackup = @()

        # 0. 冲突检测与交互处理
        $snapshot = Test-NodeFnmInstalled
        if ($snapshot -and $snapshot.Data) {
            foreach ($key in $snapshot.Data.Keys) {
                $result.Data[$key] = $snapshot.Data[$key]
            }
        }

        $conflictType = "none"
        if ($snapshot -and $snapshot.Data -and $snapshot.Data.ContainsKey("ConflictType")) {
            $conflictType = [string]$snapshot.Data["ConflictType"]
        }

        if ($conflictType -ne "none") {
            Write-UiWarn "⚠ 检测到 Node.js 环境冲突: $conflictType"

            if ($snapshot.Data.ContainsKey("ConflictDetails") -and $snapshot.Data["ConflictDetails"]) {
                foreach ($detail in @($snapshot.Data["ConflictDetails"])) {
                    Write-UiWarn "  - $detail"
                }
            }

            $npmInPath = [bool]$snapshot.Data["NpmAvailable"]
            $restoreLabel = if ($npmInPath) {
                "迁移到 fnm（卸载冲突工具并恢复 npm 全局包）[推荐]"
            } else {
                "迁移到 fnm（卸载冲突工具，将尝试定位 npm 恢复全局包）"
            }
            $options = @(
                "保留现有环境（跳过 fnm 安装）",
                $restoreLabel,
                "全新安装 fnm（卸载冲突工具，不恢复全局包）"
            )
            $choice = Show-SingleSelectMenu -Title "检测到冲突，选择处理方式：" -Options $options -DefaultIndex 1

            if ($choice -eq -1) {
                throw "用户取消了冲突处理"
            }

            if ($choice -eq 0) {
                $result.Success = $true
                $result.Message = "保留现有 Node.js 环境，已跳过 fnm 安装"
                $result.Data["SkippedFnmInstall"] = $true
                $result.Data["MigrationMode"] = "KeepExisting"
                Write-UiSuccess "✓ 已按用户选择保留现有环境"
                return $result
            }

            $confirm = Show-SingleSelectMenu -Title "⚠ 将执行卸载操作（可能影响现有开发环境），是否继续？" -Options @("继续执行", "取消") -DefaultIndex 0
            if ($confirm -ne 0) {
                throw "用户取消了卸载操作"
            }

            if ($choice -eq 1) {
                $shouldRestoreGlobalPackages = $true
                $result.Data["MigrationMode"] = "MigrateWithRestore"
            } else {
                $result.Data["MigrationMode"] = "FreshInstall"
            }

            if ($shouldRestoreGlobalPackages) {
                # 主动探测并修复 npm 可用性
                $npmResolve = Resolve-NpmForBackup -EnvSnapshot $snapshot.Data
                if ($npmResolve.Available) {
                    Write-UiInfo "npm 已就绪（方式: $($npmResolve.Method)），开始备份..."
                } else {
                    Write-UiWarn "$($npmResolve.ErrorMessage)"
                    Write-UiWarn "  无法备份 npm 全局包，您可以选择："
                    $failChoice = Show-SingleSelectMenu -Title "npm 定位失败，请选择处理方式：" -Options @(
                        "继续迁移（跳过全局包恢复，后续可手动安装）",
                        "中止迁移（保留现有环境不做任何更改）"
                    ) -DefaultIndex 0
                    if ($failChoice -eq 1 -or $failChoice -eq -1) {
                        $result.Success = $true
                        $result.Message = "用户选择中止迁移，保留现有环境"
                        $result.Data["MigrationMode"] = "AbortedByUser"
                        Write-UiWarn "已中止迁移，保留现有环境"
                        return $result
                    }
                    $shouldRestoreGlobalPackages = $false
                    $result.Data["BackupSkipped"] = $true
                    $result.Data["BackupSkipReason"] = $npmResolve.ErrorMessage
                }

                if ($shouldRestoreGlobalPackages) {
                    $backupResult = Backup-NpmGlobalPackages
                    if (-not $backupResult.Success) {
                        Write-UiWarn "npm 全局包备份失败: $($backupResult.ErrorMessage)"
                        Write-UiWarn "  将继续迁移但跳过全局包恢复"
                        $shouldRestoreGlobalPackages = $false
                        $result.Data["BackupSkipped"] = $true
                        $result.Data["BackupSkipReason"] = $backupResult.ErrorMessage
                    } else {
                        $globalPackagesBackup = @($backupResult.Packages)
                        $result.Data["GlobalPackagesBackupCount"] = $globalPackagesBackup.Count
                        $result.Data["GlobalPackagesBackup"] = $globalPackagesBackup
                    }
                }
            }

            $uninstallResult = Uninstall-ExistingNode -EnvSnapshot $snapshot.Data
            if (-not $uninstallResult.Success) {
                throw "卸载冲突工具失败: $($uninstallResult.ErrorMessage)"
            }

            $result.Data["UninstallCompleted"] = $true
            $result.Data["UninstallCleanedPaths"] = @($uninstallResult.CleanedPaths)

            Refresh-SessionPath
            Write-UiSuccess "✓ 冲突环境处理完成，继续安装 fnm"
        } else {
            $result.Data["MigrationMode"] = "NoConflict"
        }

        # 1. 安装 fnm
        Write-UiInfo "🔧 安装 fnm (Fast Node Manager)..."

        if (Test-CommandAvailable -Command "fnm") {
            Write-UiSuccess "✓ fnm 已安装，跳过安装步骤"
        } else {
            # 使用 winget 安装 fnm
            if (Test-CommandAvailable -Command "winget") {
                try {
                    $fnmInstall = Invoke-WingetInstall -PackageId "Schniz.fnm" -PackageName "fnm" -Silent -AcceptLicense
                    if (-not $fnmInstall.Success) {
                        throw "winget 安装 fnm 失败"
                    }
                    Write-UiSuccess "✓ fnm 通过 winget 安装成功"
                } catch {
                    Write-UiWarn "⚠ winget 安装失败，尝试手动下载安装..."

                    # 手动下载安装 fnm
                    $fnmDir = "$env:LOCALAPPDATA\fnm"
                    if (-not (Test-Path $fnmDir)) {
                        New-Item -Path $fnmDir -ItemType Directory -Force | Out-Null
                    }

                    # 下载 fnm 二进制文件
                    $fnmUrl = "https://github.com/Schniz/fnm/releases/latest/download/fnm-windows.zip"
                    $fnmZip = "$env:TEMP\fnm-windows.zip"

                    Write-UiInfo "正在下载 fnm..."
                    try {
                        # 使用统一的下载函数
                        $downloadResult = Invoke-FileDownload -Url $fnmUrl -OutputPath $fnmZip -Description "fnm (Fast Node Manager)"

                        if (-not $downloadResult.Success) {
                            throw "下载失败: $($downloadResult.ErrorMessage)"
                        }

                        Expand-Archive -Path $fnmZip -DestinationPath $fnmDir -Force
                        Remove-Item $fnmZip -Force

                        # 添加到 PATH（临时）
                        $env:PATH = "$fnmDir;$env:PATH"

                        Write-UiSuccess "✓ fnm 手动安装成功"
                    } catch {
                        throw "手动下载安装 fnm 失败: $($_.Exception.Message)"
                    }
                }
            } else {
                throw "winget 不可用且无法手动安装 fnm"
            }
        }

        # 刷新 PATH 确保 fnm 可用
        Refresh-SessionPath

        # 验证 fnm 安装
        if (-not (Test-CommandAvailable -Command "fnm")) {
            throw "fnm 安装后仍不可用"
        }

        $fnmVersion = Get-CommandVersion -Command "fnm"
        $result.Data["FnmVersion"] = $fnmVersion
        Write-UiSuccess "✓ fnm 验证成功 (版本: $fnmVersion)"

        # 2. 配置 PowerShell Profile（在安装 Node.js 之前）
        Write-UiInfo "⚙️ 配置 PowerShell Profile..."

        $profilePath = $PROFILE

        # fnm 初始化配置
        $fnmConfig = @(
            "# fnm (Fast Node Manager) 初始化",
            "if (Get-Command fnm -ErrorAction SilentlyContinue) {",
            "    fnm env --use-on-cd | Out-String | Invoke-Expression",
            "}",
            "",
            "# Node.js 和 npm 路径刷新",
            "if (Get-Command node -ErrorAction SilentlyContinue) {",
            "    # 确保 npm 全局包路径在 PATH 中",
            "    `$npmGlobalPath = npm config get prefix 2>`$null",
            "    if (`$npmGlobalPath -and (Test-Path `$npmGlobalPath)) {",
            "        `$env:PATH = `"`$npmGlobalPath;`$env:PATH`"",
            "    }",
            "}"
        )

        # 使用标记块写入配置
        $profileSuccess = Set-ManagedBlockInFile -FilePath $profilePath -Content $fnmConfig -CreateIfNotExists -AppendIfNoBlock

        if ($profileSuccess) {
            Write-UiSuccess "✓ PowerShell Profile 配置成功"
            $result.Data["ProfileConfigured"] = $true
        } else {
            Write-UiWarn "⚠ PowerShell Profile 配置失败，但不影响 fnm 使用"
            $result.Data["ProfileConfigured"] = $false
        }

        # 3. 重新加载 PowerShell Profile 以刷新当前会话环境
        Write-UiInfo "🔄 重新加载 PowerShell Profile 以刷新环境..."

        try {
            if (Test-Path $PROFILE) {
                # 使用 dot-source 重新加载 Profile
                . $PROFILE
                Write-UiSuccess "✓ PowerShell Profile 已重新加载"
            } else {
                Write-UiWarn "⚠ PowerShell Profile 文件不存在"
            }
        } catch {
            Write-UiWarn "⚠ 重新加载 PowerShell Profile 时出错: $($_.Exception.Message)"
        }

        # 再次刷新 PATH
        Refresh-SessionPath

        # 4. 使用 fnm 安装 Node.js（在 Profile 配置和刷新之后）
        Write-UiInfo "🟢 使用 fnm 安装 Node.js LTS..."

        try {
            # 安装最新 LTS 版本
            $installResult = Invoke-ExternalCommand -Command "fnm" -Arguments @("install", "--lts") -TimeoutSeconds 300
            if (-not $installResult.Success) {
                throw "fnm 安装 Node.js 失败: $($installResult.Error)"
            }

            Write-UiSuccess "✓ Node.js LTS 安装成功"

            # 显式注入 fnm 环境变量到当前会话（不依赖 $PROFILE 重载）
            # fnm use 需要 FNM_MULTISHELL_PATH 等变量，必须在调用前确保已设置
            Write-UiInfo "🔄 初始化 fnm 环境变量..."
            try {
                $fnmEnvOutput = & fnm env --use-on-cd 2>&1 | Out-String
                if ($fnmEnvOutput) {
                    Invoke-Expression $fnmEnvOutput
                    Write-UiSuccess "✓ fnm 环境变量已注入当前会话"
                } else {
                    Write-UiWarn "⚠ fnm env 未返回输出，fnm use 可能失败"
                }
            } catch {
                Write-UiWarn "⚠ fnm env 执行异常: $($_.Exception.Message)"
            }

            # 使用 LTS 版本
            Write-UiInfo "正在激活 Node.js LTS 版本..."

            # 优先使用 fnm default 设置默认版本（不依赖 MULTISHELL_PATH）
            $defaultResult = Invoke-ExternalCommand -Command "fnm" -Arguments @("default", "lts-latest") -TimeoutSeconds 60
            if ($defaultResult.Success) {
                Write-UiSuccess "✓ Node.js LTS 已设为默认版本"
            } else {
                Write-UiWarn "⚠ fnm default 失败，尝试 fnm use..."
            }

            # 再次确认环境变量存在后执行 fnm use
            if (-not $env:FNM_MULTISHELL_PATH) {
                Write-UiWarn "⚠ FNM_MULTISHELL_PATH 仍未设置，再次尝试注入..."
                try {
                    $fnmEnvRetry = & fnm env --use-on-cd 2>&1 | Out-String
                    if ($fnmEnvRetry) { Invoke-Expression $fnmEnvRetry }
                } catch {
                    Write-UiWarn "⚠ fnm env 重试失败: $($_.Exception.Message)"
                }
            }

            $useResult = Invoke-ExternalCommand -Command "fnm" -Arguments @("use", "--install-if-missing", "lts-latest") -TimeoutSeconds 60
            if (-not $useResult.Success) {
                # fnm use 失败时提供友好的中文指引
                $friendlyMsg = "Node.js 版本激活失败。"
                $friendlyMsg += "`n  原因: fnm 环境变量未正确初始化"
                $friendlyMsg += "`n  建议: 关闭当前终端，打开新的 PowerShell 7 窗口后重新运行安装程序"
                $friendlyMsg += "`n  或手动执行: fnm env --use-on-cd | Out-String | Invoke-Expression; fnm use lts-latest"
                throw $friendlyMsg
            }

            Write-UiSuccess "✓ Node.js LTS 版本已激活"

        } catch {
            throw "Node.js 安装过程失败: $($_.Exception.Message)"
        }

        # 5. 再次刷新 PATH 确保 node 和 npm 可用
        Refresh-SessionPath

        # 6. 验证 Node.js 和 npm
        Write-UiInfo "🔍 验证 Node.js 和 npm 安装..."

        # 验证 Node.js
        $nodeDetails = Test-CommandAvailable -Command "node" -ReturnDetails
        if ($nodeDetails.Available) {
            $nodeVersion = Get-CommandVersion -Command "node"
            $result.Data["NodeVersion"] = $nodeVersion
            $result.Data["NodePath"] = $nodeDetails.ResolvedPath
            Write-UiSuccess "✓ Node.js 验证成功 (版本: $nodeVersion)"
            Write-UiInfo "  路径: $($nodeDetails.ResolvedPath)"
        } else {
            $errorMsg = "Node.js 安装后不可用"
            if ($nodeDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($nodeDetails.ResolvedPath)"
            }
            if ($nodeDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($nodeDetails.ErrorMessage)"
            }
            $errorMsg += "`n  建议: 请重新启动 PowerShell 后重试，或手动执行: . `$PROFILE"
            throw $errorMsg
        }

        # 验证 npm
        $npmDetails = Test-CommandAvailable -Command "npm" -ReturnDetails
        if ($npmDetails.Available) {
            $npmVersion = Get-CommandVersion -Command "npm"
            $result.Data["NpmVersion"] = $npmVersion
            $result.Data["NpmPath"] = $npmDetails.ResolvedPath
            Write-UiSuccess "✓ npm 验证成功 (版本: $npmVersion)"
            Write-UiInfo "  路径: $($npmDetails.ResolvedPath)"
        } else {
            $errorMsg = "npm 安装后不可用"
            if ($npmDetails.ResolvedPath) {
                $errorMsg += "`n  解析路径: $($npmDetails.ResolvedPath)"
            }
            if ($npmDetails.ErrorMessage) {
                $errorMsg += "`n  错误详情: $($npmDetails.ErrorMessage)"
            }
            if ($npmDetails.ExitCode -ne -1) {
                $errorMsg += "`n  退出码: $($npmDetails.ExitCode)"
            }
            $errorMsg += "`n  建议: 请重新启动 PowerShell 后重试，或手动执行: . `$PROFILE"
            throw $errorMsg
        }

        # 5. 配置 npm 镜像源
        Write-UiInfo "配置 npm 镜像源..."
        try {
            $configResult = Invoke-ExternalCommand -Command "npm" -Arguments @("config", "set", "registry", "https://registry.npmmirror.com") -TimeoutSeconds 30
            if ($configResult.ExitCode -eq 0) {
                Write-UiSuccess "npm 镜像源已设置为 registry.npmmirror.com"
            } else {
                Write-UiWarn "npm 镜像源配置失败，将使用默认源"
            }
        } catch {
            Write-UiWarn "⚠ npm 镜像源配置过程中出现错误: $($_.Exception.Message)"
        }

        # 6. 恢复 npm 全局包（仅迁移模式）
        if ($shouldRestoreGlobalPackages) {
            $restoreResult = Restore-NpmGlobalPackages -Packages $globalPackagesBackup
            $result.Data["GlobalPackagesRestoreInstalled"] = @($restoreResult.Installed)
            $result.Data["GlobalPackagesRestoreFailed"] = @($restoreResult.Failed)
            $result.Data["GlobalPackagesRestoreSuccess"] = $restoreResult.Success

            if (-not $restoreResult.Success) {
                Write-UiWarn "⚠ npm 全局包部分恢复失败（详见结果数据）"
            } else {
                Write-UiSuccess "✓ npm 全局包恢复完成"
            }
        }

        # 安装成功
        $result.Success = $true
        $result.Message = "Node.js 运行时安装配置完成"

        Write-UiSuccess "✅ NodeFnm 安装完成！"
        Write-UiInfo "💡 提示: 如果在新的 PowerShell 会话中 node 命令不可用，请重新启动 PowerShell"

    } catch {
        $result.ErrorMessage = "fnm 和 Node.js 安装失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Verify-NodeFnm {
    <#
    .SYNOPSIS
    验证步骤 01 执行结果
    .RETURNS
    验证结果对象
    #>
    param()

    $result = @{
        Success = $false
        Message = ""
        ErrorMessage = ""
    }

    try {
        Write-UiInfo "✅ 验证 Node.js 运行时..."

        $verificationPassed = $true
        $issues = @()

        # 验证 fnm（可选）
        if (Test-CommandAvailable -Command "fnm") {
            $fnmVersion = Get-CommandVersion -Command "fnm"
            Write-UiSuccess "✓ fnm 验证通过 (版本: $fnmVersion)"
        } else {
            Write-UiWarn "⚠ fnm 未安装或不可用（允许使用 nvm/direct Node 环境）"
        }

        # 验证 Node.js（必须）
        if (Test-CommandAvailable -Command "node") {
            $nodeVersion = Get-CommandVersion -Command "node"
            Write-UiInfo "  Node.js 当前版本: $nodeVersion"

            # 检查版本号是否有效
            if ($nodeVersion -match '^v?\d+\.\d+') {
                # 提取主版本号
                $versionNumber = $nodeVersion -replace '^v?(\d+)\..*$', '$1'

                # 验证提取的版本号是否为数字
                if ($versionNumber -match '^\d+$') {
                    if ([int]$versionNumber -ge [int]$script:RequiredNodeVersion) {
                        Write-UiSuccess "✓ Node.js 验证通过 (版本: $nodeVersion)"
                    } else {
                        $verificationPassed = $false
                        $issues += "Node.js 版本过低 (当前: $nodeVersion, 需要: v$script:RequiredNodeVersion+)"
                    }
                } else {
                    $verificationPassed = $false
                    $issues += "无法解析 Node.js 版本号: $nodeVersion"
                }
            } else {
                $verificationPassed = $false
                $issues += "无法获取有效的 Node.js 版本号 (返回: $nodeVersion)"
            }
        } else {
            $verificationPassed = $false
            $issues += "Node.js 命令不可用"
        }

        # 验证 npm（必须）
        if (Test-CommandAvailable -Command "npm") {
            $npmVersion = Get-CommandVersion -Command "npm"
            Write-UiSuccess "✓ npm 验证通过 (版本: $npmVersion)"
        } else {
            $verificationPassed = $false
            $issues += "npm 命令不可用"
        }

        # 验证 npm 基本功能
        try {
            $npmTestResult = Invoke-ExternalCommand -Command "npm" -Arguments @("--version") -SuppressOutput -TimeoutSeconds 10
            if ($npmTestResult.Success) {
                Write-UiSuccess "✓ npm 功能验证通过"
            } else {
                $issues += "npm 功能测试失败"
            }
        } catch {
            $issues += "npm 功能测试异常: $($_.Exception.Message)"
        }

        if ($verificationPassed -and $issues.Count -eq 0) {
            $result.Success = $true
            $result.Message = "Node.js 运行时验证通过"
        } else {
            $result.Success = $false
            $result.ErrorMessage = "验证失败: $($issues -join '; ')"
            Write-UiError "✗ $($result.ErrorMessage)"
        }

    } catch {
        $result.ErrorMessage = "Node.js 运行时验证过程失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}
# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用