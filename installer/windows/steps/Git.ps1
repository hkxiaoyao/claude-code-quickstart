# Git.ps1 - Git 安装和基础配置
# 作者: 哈雷酱 (本小姐的版本控制杰作！)
# 功能: 安装 Git 并配置基础环境

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$scriptRoot\core\Process.ps1"
. "$scriptRoot\core\Ui.ps1"
. "$scriptRoot\core\Profile.ps1"

# 全局配置
$script:MinGitVersion = [Version]"2.30.0"  # 最低 Git 版本要求

function Test-GitInstalled {
    <#
    .SYNOPSIS
    检测 Git 安装和配置状态
    .RETURNS
    标准检测结果 hashtable（IsInstalled, Version, Data, Message）
    #>
    param()

    return Invoke-UnifiedCheck -StepId "Git" -DisplayName "Git" `
        -Command "git" -MinVersion "2.30.0" `
        -CustomVerify {
            # 哨兵检查：init.defaultBranch 是否已配置为 main
            $sentinel = & git config --global --get init.defaultBranch 2>$null
            if ($sentinel -ne "main") { return $false }

            # 检查 .bashrc managed block 是否存在
            $homeDir = Get-UserHome
            if (-not $homeDir) { $homeDir = $env:HOME }
            if (-not $homeDir) { return $false }

            $bashrcPath = Join-Path $homeDir ".bashrc"
            if (-not (Test-Path $bashrcPath)) { return $false }

            $bashrcContent = Get-Content -Path $bashrcPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            return ($bashrcContent -and $bashrcContent.Contains("# >>> Claude Code Quickstart >>>"))
        } -UseCache
}

function Install-Git {
    <#
    .SYNOPSIS
    执行步骤 02 安装（Git 安装 + 基础配置）
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
        Write-UiPrimary "📦 开始安装和配置 Git..." -Level Detail

        # 1. 安装 Git
        Write-UiPrimary "🔧 检查并安装 Git..." -Level Detail

        if (Test-CommandAvailable -Command "git") {
            $currentVersion = Get-CommandVersion -Command "git"
            Write-UiSuccess "✓ Git 已安装，当前版本: $currentVersion" -Level Detail

            # 检查版本是否满足要求
            try {
                $versionString = $currentVersion -replace '^git version ', '' -replace '\.windows.*$', ''
                $gitVersion = [Version]$versionString

                if ($gitVersion -lt $script:MinGitVersion) {
                    Write-UiWarning "⚠ Git 版本过低，尝试更新..." -Level Detail
                    $needsUpdate = $true
                } else {
                    $needsUpdate = $false
                }
            } catch {
                Write-UiWarning "⚠ 无法解析 Git 版本，尝试重新安装..." -Level Debug
                $needsUpdate = $true
            }
        } else {
            Write-UiPrimary "Git 未安装，开始安装..." -Level Detail
            $needsUpdate = $true
        }

        if ($needsUpdate) {
            # 使用 winget 安装 Git
            if (Test-CommandAvailable -Command "winget") {
                try {
                    $gitInstall = Invoke-WingetInstall -PackageId "Git.Git" -PackageName "Git" -Silent -AcceptLicense
                    if (-not $gitInstall.Success) {
                        throw "winget 安装 Git 失败"
                    }
                    Write-UiSuccess "✓ Git 通过 winget 安装成功" -Level Detail
                } catch {
                    Write-UiWarning "⚠ winget 安装失败，请手动安装 Git" -Level Detail
                    Write-UiInfo "请访问 https://git-scm.com/download/win 下载并安装 Git" -Level Detail
                    throw "Git 安装失败，请手动安装后重新运行"
                }
            } else {
                Write-UiWarning "⚠ winget 不可用，无法自动安装 Git" -Level Detail
                Write-UiInfo "请访问 https://git-scm.com/download/win 下载并安装 Git" -Level Detail
                throw "Git 安装失败，请手动安装后重新运行"
            }

            # 刷新 PATH 确保 Git 可用
            Refresh-SessionPath

            # 验证 Git 安装
            if (-not (Test-CommandAvailable -Command "git")) {
                throw "Git 安装后仍不可用，请检查安装是否成功"
            }
        }

        $finalGitVersion = Get-CommandVersion -Command "git"
        $result.Data["GitVersion"] = $finalGitVersion

        # 2. 配置 Git 推荐设置
        Write-UiPrimary "🔧 配置 Git 推荐设置..." -Level Detail

        $recommendedConfigs = @(
            @{ Key = "init.defaultBranch"; Value = "main"; Description = "默认分支名" },
            @{ Key = "core.quotepath"; Value = "false"; Description = "中文文件名显示" },
            @{ Key = "i18n.commit.encoding"; Value = "utf-8"; Description = "提交信息编码" },
            @{ Key = "i18n.logoutputencoding"; Value = "utf-8"; Description = "日志输出编码" }
        )

        foreach ($config in $recommendedConfigs) {
            try {
                $existingValue = & git config --global --get $config.Key 2>$null
                if (-not $existingValue) {
                    $configResult = Invoke-ExternalCommand -Command "git" -Arguments @("config", "--global", $config.Key, $config.Value) -TimeoutSeconds 30
                    if ($configResult.Success) {
                        Write-UiSuccess "✓ $($config.Description) 配置成功: $($config.Value)" -Level Detail
                    } else {
                        Write-UiWarning "⚠ $($config.Description) 配置失败: $($configResult.Error)" -Level Debug
                    }
                } else {
                    Write-UiInfo "ℹ $($config.Description) 已存在: $existingValue" -Level Detail
                }
            } catch {
                Write-UiWarning "⚠ $($config.Description) 配置异常: $($_.Exception.Message)" -Level Debug
            }
        }

        # 3.5. 配置 Git Bash UTF-8 支持（~/.bashrc）
        Write-UiPrimary "🔧 配置 Git Bash UTF-8 支持..." -Level Detail

        try {
            # 查找用户主目录
            $homeDir = Get-UserHome
            if (-not $homeDir) { $homeDir = $env:HOME }

            if ($homeDir) {
                $bashrcPath = Join-Path $homeDir ".bashrc"

                # UTF-8 配置内容
                $utf8Config = @(
                    "# 搞定python",
                    "export PYTHONIOENCODING=utf-8",
                    "export PYTHONUTF8=1",
                    "",
                    "# 搞定通过 Git Bash 管道调用时中文输出乱码问题",
                    "_ps_utf8_wrapper() {",
                    "    local exe=`"`$1`"; shift",
                    "    local pre_args=()",
                    "    local cmd=`"`"",
                    "    local found_command=false",
                    "",
                    "    while [[ `$# -gt 0 ]]; do",
                    "        case `"`$1`" in",
                    "            -Command|-c)",
                    "                found_command=true",
                    "                shift",
                    "                cmd=`"`$*`"",
                    "                break",
                    "                ;;",
                    "            *)",
                    "                pre_args+=(`"`$1`")",
                    "                shift",
                    "                ;;",
                    "        esac",
                    "    done",
                    "",
                    "    if `$found_command && [[ -n `"`$cmd`" ]]; then",
                    "        command `"`$exe`" `"`${pre_args[@]}`" -Command \",
                    "            `"[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; `$cmd`"",
                    "    else",
                    "        command `"`$exe`" `"`${pre_args[@]}`"",
                    "    fi",
                    "}",
                    "",
                    "powershell() { _ps_utf8_wrapper powershell.exe `"`$@`"; }",
                    "pwsh() { _ps_utf8_wrapper pwsh.exe `"`$@`"; }"
                )

                # 使用标记块写入配置
                . "$scriptRoot\core\Profile.ps1"
                $success = Set-ManagedBlockInFile -FilePath $bashrcPath -Content $utf8Config -CreateIfNotExists -AppendIfNoBlock

                if ($success) {
                    Write-UiSuccess "✓ Git Bash UTF-8 配置已应用（Python UTF-8 + PowerShell wrapper）" -Level Detail
                } else {
                    Write-UiWarning "⚠ Git Bash 配置写入失败（不影响主安装流程）" -Level Debug
                }
            } else {
                Write-UiWarning "⚠ 无法确定用户主目录，跳过 Git Bash 配置" -Level Detail
            }
        } catch {
            Write-UiWarning "⚠ Git Bash 配置过程中发生错误: $($_.Exception.Message)" -Level Debug
            Write-UiDim "这不影响主安装流程，可以稍后手动配置" -Level Detail
        }

        # 安装成功
        $gitVersion = Get-CommandVersion -Command "git"
        $result.Data["Version"] = $gitVersion
        $result.Success = $true
        $result.Message = "Git 安装和配置完成"

        Write-UiSuccess "✅ Git 安装完成！" -Level Detail

    } catch {
        $result.ErrorMessage = "Git 安装和配置失败: $($_.Exception.Message)"
        Write-UiDanger "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Verify-Git {
    <#
    .SYNOPSIS
    验证步骤 02 执行结果
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
        Write-UiPrimary "✅ 验证 Git 安装和配置..." -Level Detail

        $verificationPassed = $true
        $issues = @()

        # 验证 Git 命令可用性
        if (Test-CommandAvailable -Command "git") {
            $gitVersion = Get-CommandVersion -Command "git"
            Write-UiSuccess "✓ Git 命令验证通过 (版本: $gitVersion)" -Level Detail
        } else {
            $verificationPassed = $false
            $issues += "Git 命令不可用"
        }

        # 验证 Git 基本功能
        try {
            # 测试 git version 命令
            $versionResult = Invoke-ExternalCommand -Command "git" -Arguments @("--version") -SuppressOutput -TimeoutSeconds 10
            if ($versionResult.Success) {
                Write-UiSuccess "✓ Git 基本功能验证通过" -Level Detail
            } else {
                $issues += "Git 基本功能测试失败"
            }

            # 测试 git config 命令
            $configResult = Invoke-ExternalCommand -Command "git" -Arguments @("config", "--list", "--global") -SuppressOutput -TimeoutSeconds 10
            if ($configResult.Success) {
                Write-UiSuccess "✓ Git 配置功能验证通过" -Level Detail
            } else {
                $issues += "Git 配置功能测试失败"
            }
        } catch {
            $issues += "Git 功能测试异常: $($_.Exception.Message)"
        }

        if ($verificationPassed -and $issues.Count -eq 0) {
            $result.Success = $true
            $result.Message = "Git 安装和配置验证完全通过"
        } else {
            $result.Success = $false
            $result.ErrorMessage = "验证失败: $($issues -join '; ')"
            Write-UiDanger "✗ $($result.ErrorMessage)"
        }

    } catch {
        $result.ErrorMessage = "Git 验证过程失败: $($_.Exception.Message)"
        Write-UiDanger "✗ $($result.ErrorMessage)"
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用