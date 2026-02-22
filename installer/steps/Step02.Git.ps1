# Step02.Git.ps1 - Git 安装和基础配置
# 作者: 哈雷酱 (本小姐的版本控制杰作！)
# 功能: 安装 Git 并进行基础配置（user.name/email）

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$scriptRoot\core\Process.ps1"
. "$scriptRoot\core\Ui.ps1"

# 全局配置
$script:MinGitVersion = [Version]"2.30.0"  # 最低 Git 版本要求

function Test-Step02Installed {
    <#
    .SYNOPSIS
    测试步骤 02 是否已完成（Git 安装和配置）
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
        Write-UiInfo "🔍 检查 Git 安装和配置状态..."

        # 检查 Git 是否可用
        $gitAvailable = Test-CommandAvailable -Command "git"
        $result.Data["GitAvailable"] = $gitAvailable

        if ($gitAvailable) {
            $gitVersion = Get-CommandVersion -Command "git"
            $result.Data["GitVersion"] = $gitVersion
            Write-UiSuccess "✓ Git 已安装 (版本: $gitVersion)"

            # 解析版本号进行比较
            try {
                $versionString = $gitVersion -replace '^git version ', '' -replace '\.windows.*$', ''
                $currentVersion = [Version]$versionString

                if ($currentVersion -ge $script:MinGitVersion) {
                    $result.Version = $gitVersion
                    Write-UiSuccess "✓ Git 版本满足要求 (需要: $script:MinGitVersion+)"
                } else {
                    Write-UiWarn "⚠ Git 版本过低 (当前: $gitVersion, 需要: $script:MinGitVersion+)"
                }
            } catch {
                Write-UiWarn "⚠ 无法解析 Git 版本号: $gitVersion"
                $result.Version = $gitVersion  # 仍然记录版本，但可能需要手动验证
            }
        } else {
            Write-UiWarn "⚠ Git 未安装"
        }

        # 检查 Git 基础配置
        $configChecks = @{
            "UserName" = $false
            "UserEmail" = $false
            "CoreEditor" = $false
            "InitDefaultBranch" = $false
        }

        if ($gitAvailable) {
            try {
                # 检查 user.name
                $userName = & git config --global --get user.name 2>$null
                if ($userName) {
                    $configChecks["UserName"] = $true
                    $result.Data["UserName"] = $userName
                    Write-UiSuccess "✓ Git user.name 已配置: $userName"
                } else {
                    Write-UiWarn "⚠ Git user.name 未配置"
                }

                # 检查 user.email
                $userEmail = & git config --global --get user.email 2>$null
                if ($userEmail) {
                    $configChecks["UserEmail"] = $true
                    $result.Data["UserEmail"] = $userEmail
                    Write-UiSuccess "✓ Git user.email 已配置: $userEmail"
                } else {
                    Write-UiWarn "⚠ Git user.email 未配置"
                }

                # 检查核心编辑器配置
                $coreEditor = & git config --global --get core.editor 2>$null
                if ($coreEditor) {
                    $configChecks["CoreEditor"] = $true
                    $result.Data["CoreEditor"] = $coreEditor
                    Write-UiSuccess "✓ Git core.editor 已配置: $coreEditor"
                } else {
                    Write-UiInfo "ℹ Git core.editor 未配置（将使用默认编辑器）"
                }

                # 检查默认分支配置
                $defaultBranch = & git config --global --get init.defaultBranch 2>$null
                if ($defaultBranch) {
                    $configChecks["InitDefaultBranch"] = $true
                    $result.Data["DefaultBranch"] = $defaultBranch
                    Write-UiSuccess "✓ Git init.defaultBranch 已配置: $defaultBranch"
                } else {
                    Write-UiInfo "ℹ Git init.defaultBranch 未配置（将使用 Git 默认值）"
                }

            } catch {
                Write-UiWarn "⚠ Git 配置检查失败: $($_.Exception.Message)"
            }
        }

        $result.Data["ConfigChecks"] = $configChecks

        # 判断是否已完全安装和配置
        if ($gitAvailable -and $result.Version -and
            $configChecks["UserName"] -and $configChecks["UserEmail"]) {
            $result.IsInstalled = $true
            $result.Message = "Git 已完全安装并配置"
        } else {
            $result.Message = "Git 安装或配置不完整，需要重新配置"
        }

    } catch {
        $result.Message = "Git 安装状态检查失败: $($_.Exception.Message)"
        Write-UiWarn "⚠ $($result.Message)"
    }

    return $result
}

function Install-Step02 {
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
        Write-UiInfo "📦 开始安装和配置 Git..."

        # 1. 安装 Git
        Write-UiInfo "🔧 检查并安装 Git..."

        if (Test-CommandAvailable -Command "git") {
            $currentVersion = Get-CommandVersion -Command "git"
            Write-UiSuccess "✓ Git 已安装，当前版本: $currentVersion"

            # 检查版本是否满足要求
            try {
                $versionString = $currentVersion -replace '^git version ', '' -replace '\.windows.*$', ''
                $gitVersion = [Version]$versionString

                if ($gitVersion -lt $script:MinGitVersion) {
                    Write-UiWarn "⚠ Git 版本过低，尝试更新..."
                    $needsUpdate = $true
                } else {
                    $needsUpdate = $false
                }
            } catch {
                Write-UiWarn "⚠ 无法解析 Git 版本，尝试重新安装..."
                $needsUpdate = $true
            }
        } else {
            Write-UiInfo "Git 未安装，开始安装..."
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
                    Write-UiSuccess "✓ Git 通过 winget 安装成功"
                } catch {
                    Write-UiWarn "⚠ winget 安装失败，请手动安装 Git"
                    Write-UiInfo "请访问 https://git-scm.com/download/win 下载并安装 Git"
                    throw "Git 安装失败，请手动安装后重新运行"
                }
            } else {
                Write-UiWarn "⚠ winget 不可用，无法自动安装 Git"
                Write-UiInfo "请访问 https://git-scm.com/download/win 下载并安装 Git"
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
        Write-UiSuccess "✓ Git 验证成功 (版本: $finalGitVersion)"

        # 2. 配置 Git 基础设置
        Write-UiInfo "⚙️ 配置 Git 基础设置..."

        # 检查现有配置
        $existingUserName = & git config --global --get user.name 2>$null
        $existingUserEmail = & git config --global --get user.email 2>$null

        # 配置 user.name
        if (-not $existingUserName) {
            Write-UiInfo "配置 Git 用户名..."

            # 尝试从系统获取用户名
            $suggestedName = $env:USERNAME
            if (-not $suggestedName) {
                $suggestedName = $env:USER
            }
            if (-not $suggestedName) {
                $suggestedName = "Claude Code User"
            }

            # 询问用户名
            Write-UiInfo "请输入您的 Git 用户名（用于提交记录）："
            Write-UiInfo "建议使用真实姓名，如：张三 或 Zhang San"
            Write-Host "默认值: $suggestedName" -ForegroundColor Gray

            $userName = Read-Host "用户名"
            if (-not $userName.Trim()) {
                $userName = $suggestedName
            }

            try {
                $configResult = Invoke-ExternalCommand -Command "git" -Arguments @("config", "--global", "user.name", $userName) -TimeoutSeconds 30
                if ($configResult.Success) {
                    Write-UiSuccess "✓ Git user.name 配置成功: $userName"
                    $result.Data["UserName"] = $userName
                } else {
                    throw "Git user.name 配置失败: $($configResult.Error)"
                }
            } catch {
                throw "Git user.name 配置异常: $($_.Exception.Message)"
            }
        } else {
            Write-UiSuccess "✓ Git user.name 已存在: $existingUserName"
            $result.Data["UserName"] = $existingUserName
        }

        # 配置 user.email
        if (-not $existingUserEmail) {
            Write-UiInfo "配置 Git 邮箱..."

            Write-UiInfo "请输入您的 Git 邮箱地址（用于提交记录）："
            Write-UiInfo "建议使用常用邮箱，如：user@example.com"

            do {
                $userEmail = Read-Host "邮箱地址"
                if ($userEmail -match '^[^@]+@[^@]+\.[^@]+$') {
                    break
                } else {
                    Write-UiWarn "⚠ 邮箱格式不正确，请重新输入"
                }
            } while ($true)

            try {
                $configResult = Invoke-ExternalCommand -Command "git" -Arguments @("config", "--global", "user.email", $userEmail) -TimeoutSeconds 30
                if ($configResult.Success) {
                    Write-UiSuccess "✓ Git user.email 配置成功: $userEmail"
                    $result.Data["UserEmail"] = $userEmail
                } else {
                    throw "Git user.email 配置失败: $($configResult.Error)"
                }
            } catch {
                throw "Git user.email 配置异常: $($_.Exception.Message)"
            }
        } else {
            Write-UiSuccess "✓ Git user.email 已存在: $existingUserEmail"
            $result.Data["UserEmail"] = $existingUserEmail
        }

        # 3. 配置其他推荐设置
        Write-UiInfo "🔧 配置 Git 推荐设置..."

        $recommendedConfigs = @(
            @{ Key = "init.defaultBranch"; Value = "main"; Description = "默认分支名" },
            @{ Key = "core.autocrlf"; Value = "true"; Description = "Windows 换行符处理" },
            @{ Key = "core.safecrlf"; Value = "warn"; Description = "换行符安全检查" },
            @{ Key = "pull.rebase"; Value = "false"; Description = "拉取时使用合并策略" },
            @{ Key = "core.editor"; Value = "notepad"; Description = "默认编辑器" },
            @{ Key = "core.quotepath"; Value = "false"; Description = "Git 中文文件名支持" },
            @{ Key = "gui.encoding"; Value = "utf-8"; Description = "GUI 编码" },
            @{ Key = "i18n.commit.encoding"; Value = "utf-8"; Description = "提交信息编码" },
            @{ Key = "i18n.logoutputencoding"; Value = "utf-8"; Description = "日志输出编码" }
        )

        foreach ($config in $recommendedConfigs) {
            try {
                $existingValue = & git config --global --get $config.Key 2>$null
                if (-not $existingValue) {
                    $configResult = Invoke-ExternalCommand -Command "git" -Arguments @("config", "--global", $config.Key, $config.Value) -TimeoutSeconds 30
                    if ($configResult.Success) {
                        Write-UiSuccess "✓ $($config.Description) 配置成功: $($config.Value)"
                    } else {
                        Write-UiWarn "⚠ $($config.Description) 配置失败: $($configResult.Error)"
                    }
                } else {
                    Write-UiInfo "ℹ $($config.Description) 已存在: $existingValue"
                }
            } catch {
                Write-UiWarn "⚠ $($config.Description) 配置异常: $($_.Exception.Message)"
            }
        }

        # 3.5. 配置 Git Bash UTF-8 支持（~/.bashrc）
        Write-UiInfo "🔧 配置 Git Bash UTF-8 支持..."

        try {
            # 查找用户主目录
            $homeDir = $env:USERPROFILE
            if (-not $homeDir) { $homeDir = $env:HOME }

            if ($homeDir) {
                $bashrcPath = Join-Path $homeDir ".bashrc"

                # UTF-8 配置内容
                $utf8Config = @(
                    "# UTF-8 编码配置",
                    "export LANG=zh_CN.UTF-8",
                    "export LC_ALL=zh_CN.UTF-8",
                    "export LC_CTYPE=zh_CN.UTF-8",
                    "",
                    "# 终端颜色支持",
                    "export TERM=xterm-256color"
                )

                # 使用标记块写入配置
                . "$scriptRoot\core\Profile.ps1"
                $success = Set-ManagedBlockInFile -FilePath $bashrcPath -Content $utf8Config -CreateIfNotExists -AppendIfNoBlock

                if ($success) {
                    Write-UiSuccess "✓ Git Bash UTF-8 配置已应用"
                    Write-UiInfo "配置将在下次启动 Git Bash 时生效"
                } else {
                    Write-UiWarn "⚠ Git Bash 配置写入失败（不影响主安装流程）"
                }
            } else {
                Write-UiWarn "⚠ 无法确定用户主目录，跳过 Git Bash 配置"
            }
        } catch {
            Write-UiWarn "⚠ Git Bash 配置过程中发生错误: $($_.Exception.Message)"
            Write-UiInfo "这不影响主安装流程，可以稍后手动配置"
        }

        # 4. 验证最终配置
        Write-UiInfo "✅ 验证 Git 配置..."

        $finalUserName = & git config --global --get user.name 2>$null
        $finalUserEmail = & git config --global --get user.email 2>$null

        if ($finalUserName -and $finalUserEmail) {
            Write-UiSuccess "✓ Git 配置验证成功"
            Write-UiInfo "  用户名: $finalUserName"
            Write-UiInfo "  邮箱: $finalUserEmail"
        } else {
            throw "Git 配置验证失败，用户名或邮箱未正确设置"
        }

        # 安装成功
        $result.Success = $true
        $result.Message = "Git 安装和配置完成"

        Write-UiSuccess "✅ Step02 安装完成！"

    } catch {
        $result.ErrorMessage = "Git 安装和配置失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Verify-Step02 {
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
        Write-UiInfo "✅ 验证 Git 安装和配置..."

        $verificationPassed = $true
        $issues = @()

        # 验证 Git 命令可用性
        if (Test-CommandAvailable -Command "git") {
            $gitVersion = Get-CommandVersion -Command "git"
            Write-UiSuccess "✓ Git 命令验证通过 (版本: $gitVersion)"
        } else {
            $verificationPassed = $false
            $issues += "Git 命令不可用"
        }

        # 验证基础配置
        try {
            $userName = & git config --global --get user.name 2>$null
            if ($userName) {
                Write-UiSuccess "✓ Git user.name 验证通过: $userName"
            } else {
                $verificationPassed = $false
                $issues += "Git user.name 未配置"
            }

            $userEmail = & git config --global --get user.email 2>$null
            if ($userEmail) {
                Write-UiSuccess "✓ Git user.email 验证通过: $userEmail"
            } else {
                $verificationPassed = $false
                $issues += "Git user.email 未配置"
            }
        } catch {
            $verificationPassed = $false
            $issues += "Git 配置读取失败: $($_.Exception.Message)"
        }

        # 验证 Git 基本功能
        try {
            # 测试 git version 命令
            $versionResult = Invoke-ExternalCommand -Command "git" -Arguments @("--version") -SuppressOutput -TimeoutSeconds 10
            if ($versionResult.Success) {
                Write-UiSuccess "✓ Git 基本功能验证通过"
            } else {
                $issues += "Git 基本功能测试失败"
            }

            # 测试 git config 命令
            $configResult = Invoke-ExternalCommand -Command "git" -Arguments @("config", "--list", "--global") -SuppressOutput -TimeoutSeconds 10
            if ($configResult.Success) {
                Write-UiSuccess "✓ Git 配置功能验证通过"
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
            Write-UiError "✗ $($result.ErrorMessage)"
        }

    } catch {
        $result.ErrorMessage = "Git 验证过程失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用