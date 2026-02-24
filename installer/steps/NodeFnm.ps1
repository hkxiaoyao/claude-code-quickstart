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

        # 检查 fnm 是否可用
        $fnmAvailable = Test-CommandAvailable -Command "fnm"
        $nodeAvailable = Test-CommandAvailable -Command "node"
        $npmAvailable = Test-CommandAvailable -Command "npm"

        $result.Data["FnmAvailable"] = $fnmAvailable
        $result.Data["NodeAvailable"] = $nodeAvailable
        $result.Data["NpmAvailable"] = $npmAvailable

        if ($fnmAvailable) {
            $fnmVersion = Get-CommandVersion -Command "fnm"
            $result.Data["FnmVersion"] = $fnmVersion
            Write-UiSuccess "✓ fnm 已安装 (版本: $fnmVersion)"
        } else {
            Write-UiWarn "⚠ fnm 未安装"
        }

        if ($nodeAvailable) {
            $nodeVersion = Get-CommandVersion -Command "node"
            $result.Data["NodeVersion"] = $nodeVersion
            Write-UiSuccess "✓ Node.js 已安装 (版本: $nodeVersion)"

            # 检查版本是否满足要求
            $versionNumber = $nodeVersion -replace '^v?(\d+)\..*$', '$1'
            if ([int]$versionNumber -ge [int]$script:RequiredNodeVersion) {
                $result.Version = $nodeVersion
                Write-UiSuccess "✓ Node.js 版本满足要求 (需要: v$script:RequiredNodeVersion+)"
            } else {
                Write-UiWarn "⚠ Node.js 版本过低 (当前: $nodeVersion, 需要: v$script:RequiredNodeVersion+)"
            }
        } else {
            Write-UiWarn "⚠ Node.js 未安装"
        }

        if ($npmAvailable) {
            $npmVersion = Get-CommandVersion -Command "npm"
            $result.Data["NpmVersion"] = $npmVersion
            Write-UiSuccess "✓ npm 已安装 (版本: $npmVersion)"
        } else {
            Write-UiWarn "⚠ npm 未安装"
        }

        # 检查 $PROFILE 中的 fnm 配置
        $profilePath = $PROFILE
        if (Test-Path $profilePath) {
            $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
            if ($profileContent -and $profileContent -match "fnm") {
                $result.Data["ProfileConfigured"] = $true
                Write-UiSuccess "✓ PowerShell Profile 中已配置 fnm"
            } else {
                $result.Data["ProfileConfigured"] = $false
                Write-UiWarn "⚠ PowerShell Profile 中未配置 fnm"
            }
        } else {
            $result.Data["ProfileConfigured"] = $false
            Write-UiWarn "⚠ PowerShell Profile 文件不存在"
        }

        # 判断是否已完全安装
        if ($fnmAvailable -and $nodeAvailable -and $npmAvailable -and
            $result.Version -and $result.Data["ProfileConfigured"]) {
            $result.IsInstalled = $true
            $result.Message = "Node.js 和 fnm 已完全安装并配置"
        } else {
            $result.Message = "Node.js 或 fnm 安装不完整，需要重新安装"
        }

    } catch {
        $result.Message = "Node.js 安装状态检查失败: $($_.Exception.Message)"
        Write-UiWarn "⚠ $($result.Message)"
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
                $friendlyMsg += "`n  建议: 关闭当前终端，打开新的 PowerShell 7 窗口后重新运行安装程序（-Resume）"
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

        # 安装成功
        $result.Success = $true
        $result.Message = "fnm 和 Node.js 安装配置完成"

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
        Write-UiInfo "✅ 验证 fnm 和 Node.js 安装..."

        $verificationPassed = $true
        $issues = @()

        # 验证 fnm
        if (Test-CommandAvailable -Command "fnm") {
            $fnmVersion = Get-CommandVersion -Command "fnm"
            Write-UiSuccess "✓ fnm 验证通过 (版本: $fnmVersion)"
        } else {
            $verificationPassed = $false
            $issues += "fnm 命令不可用"
        }

        # 验证 Node.js
        if (Test-CommandAvailable -Command "node") {
            $nodeVersion = Get-CommandVersion -Command "node"

            # 检查版本号是否有效
            if ($nodeVersion -match '^\d+\.\d+') {
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

        # 验证 npm
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
            $result.Message = "fnm 和 Node.js 验证完全通过"
        } else {
            $result.Success = $false
            $result.ErrorMessage = "验证失败: $($issues -join '; ')"
            Write-UiError "✗ $($result.ErrorMessage)"
        }

    } catch {
        $result.ErrorMessage = "fnm 和 Node.js 验证过程失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}
# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用