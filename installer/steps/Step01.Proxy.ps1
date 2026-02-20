# Step01.Proxy.ps1 - 代理配置检测和引导
# 作者: 哈雷酱 (本小姐的网络诊断杰作！)
# 功能: 检测代理配置，提供网络连通性评估和配置建议

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
$scriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. "$scriptRoot\core\Net.ps1"
. "$scriptRoot\core\Ui.ps1"

function Test-Step01Installed {
    <#
    .SYNOPSIS
    测试步骤 01 是否已完成（代理检测步骤）
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
        Write-UiInfo "🔍 检查代理配置检测状态..."

        # 代理检测步骤总是需要重新执行，因为网络环境可能变化
        # 但我们可以检查基本的网络连通性
        $networkHealth = Get-NetworkHealth

        $result.Data["NetworkHealth"] = $networkHealth
        $result.Data["ProxySnapshot"] = Get-ProxySnapshot
        $result.Version = "1.0"
        $result.Message = "代理检测步骤准备就绪"

        # 代理检测步骤不算"已安装"，每次都需要重新检测
        $result.IsInstalled = $false

        Write-UiInfo "代理检测步骤将重新执行以获取最新网络状态"

    } catch {
        $result.Message = "代理检测状态检查失败: $($_.Exception.Message)"
        Write-UiWarn "⚠ $($result.Message)"
    }

    return $result
}

function Install-Step01 {
    <#
    .SYNOPSIS
    执行步骤 01 安装（代理配置检测和引导）
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
        Write-UiInfo "🌐 执行代理配置检测和网络评估..."

        # 1. 获取代理配置快照
        Write-UiInfo "📡 检测代理配置..."
        $proxySnapshot = Get-ProxySnapshot

        if ($proxySnapshot.HasProxy) {
            Write-UiSuccess "✓ 检测到代理配置"
            Write-UiInfo "  配置来源: $($proxySnapshot.Sources -join ', ')"

            if ($proxySnapshot.HttpProxy) {
                Write-UiInfo "  HTTP 代理: $($proxySnapshot.HttpProxy)"
            }
            if ($proxySnapshot.HttpsProxy) {
                Write-UiInfo "  HTTPS 代理: $($proxySnapshot.HttpsProxy)"
            }
        } else {
            Write-UiInfo "ℹ 未检测到代理配置（直连模式）"
        }

        # 2. 执行网络连通性测试
        Write-UiInfo "🔗 测试网络连通性..."
        $networkTest = Test-NetworkPrerequisites

        # 3. 评估网络健康度
        Write-UiInfo "📊 评估网络健康度..."
        $networkHealth = Get-NetworkHealth

        # 4. 生成建议和警告
        $recommendations = @()
        $warnings = @()

        # 基于测试结果生成建议
        if ($networkHealth.Level -eq "较差" -or $networkHealth.Level -eq "很差") {
            $warnings += "网络连接质量较差，可能影响后续安装步骤"

            if ($proxySnapshot.HasProxy) {
                $recommendations += "检查代理服务器设置是否正确"
                $recommendations += "确认代理服务器地址和端口可访问"
                $recommendations += "验证代理认证信息（如果需要）"
            } else {
                $recommendations += "检查网络连接是否正常"
                $recommendations += "如果在企业网络环境中，可能需要配置代理"
                $recommendations += "联系网络管理员确认网络策略"
            }
        }

        # 检查关键端点
        $criticalEndpoints = @("npm registry", "GitHub")
        foreach ($endpoint in $criticalEndpoints) {
            if ($networkTest.TestedEndpoints.ContainsKey($endpoint)) {
                $endpointResult = $networkTest.TestedEndpoints[$endpoint]
                if (-not $endpointResult.Success) {
                    $warnings += "$endpoint 不可达，可能影响相关组件的安装"

                    if ($endpoint -eq "npm registry") {
                        $recommendations += "考虑配置 npm 镜像源（如淘宝镜像）"
                    }
                    if ($endpoint -eq "GitHub") {
                        $recommendations += "考虑配置 Git 代理或使用镜像源"
                    }
                }
            }
        }

        # 5. 显示检测结果摘要
        Write-Host ""
        Write-UiInfo "📋 代理配置检测摘要:"
        Write-UiInfo "  代理状态: $(if ($proxySnapshot.HasProxy) { '已配置' } else { '未配置' })"
        Write-UiInfo "  网络健康度: $($networkHealth.Level) ($($networkHealth.OverallScore)/100)"
        Write-UiInfo "  连通性测试: $($networkTest.SuccessCount)/$($networkTest.SuccessCount + $networkTest.FailureCount) 成功"

        # 显示警告
        if ($warnings.Count -gt 0) {
            Write-Host ""
            Write-UiWarn "⚠ 发现的问题:"
            foreach ($warning in $warnings) {
                Write-UiWarn "  • $warning"
            }
        }

        # 显示建议
        if ($recommendations.Count -gt 0) {
            Write-Host ""
            Write-UiInfo "💡 建议:"
            foreach ($recommendation in $recommendations) {
                Write-UiInfo "  • $recommendation"
            }
        }

        # 6. 询问用户是否继续
        if ($warnings.Count -gt 0) {
            Write-Host ""
            $options = @("继续安装（忽略网络问题）", "退出并解决网络问题")
            $choice = Show-SingleSelectMenu -Title "检测到网络问题，是否继续？" -Options $options

            if ($choice -eq 1) {
                $result.ErrorMessage = "用户选择退出以解决网络问题"
                Write-UiInfo "用户选择退出，请解决网络问题后重新运行安装程序"
                return $result
            } else {
                Write-UiInfo "用户选择继续安装，将忽略网络警告"
            }
        }

        # 7. 保存检测结果
        $result.Success = $true
        $result.Message = "代理配置检测完成"
        $result.Data["ProxySnapshot"] = $proxySnapshot
        $result.Data["NetworkTest"] = $networkTest
        $result.Data["NetworkHealth"] = $networkHealth
        $result.Data["Warnings"] = $warnings
        $result.Data["Recommendations"] = $recommendations

        Write-UiSuccess "✓ 代理配置检测和网络评估完成"

    } catch {
        $result.ErrorMessage = "代理配置检测失败: $($_.Exception.Message)"
        Write-UiError "✗ $($result.ErrorMessage)"
    }

    return $result
}

function Verify-Step01 {
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
        Write-UiInfo "✅ 验证代理配置检测结果..."

        # 重新进行快速网络测试以验证
        $quickTest = Test-EndpointReachable -Endpoint "https://www.google.com" -TimeoutSeconds 5

        if ($quickTest.Success) {
            $result.Success = $true
            $result.Message = "网络连接验证通过"
            Write-UiSuccess "✓ 网络连接验证通过"
        } else {
            # 网络不通也不算验证失败，只是记录状态
            $result.Success = $true
            $result.Message = "网络连接验证失败，但不影响后续步骤"
            Write-UiWarn "⚠ 网络连接验证失败，后续步骤可能受影响"
        }

    } catch {
        $result.ErrorMessage = "代理配置验证失败: $($_.Exception.Message)"
        Write-UiWarn "⚠ $($result.ErrorMessage)"
        # 验证失败也不算致命错误
        $result.Success = $true
    }

    return $result
}

function Rollback-Step01 {
    <#
    .SYNOPSIS
    回滚步骤 01（代理检测步骤无需回滚）
    .RETURNS
    回滚结果对象
    #>
    param()

    $result = @{
        Success = $true
        Message = "代理检测步骤无需回滚"
    }

    Write-UiInfo "代理配置检测步骤不涉及系统修改，无需回滚操作"

    return $result
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用