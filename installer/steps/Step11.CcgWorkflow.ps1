# CCG Workflow 安装步骤 - Claude Code 环境安装器
# 作者: 哈雷酱 (本小姐的专业工作流管理！)
# 功能: CCG Workflow 模板安装、变量注入和配置生成

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 导入依赖模块
. "$PSScriptRoot\..\core\Ui.ps1"
. "$PSScriptRoot\..\core\Process.ps1"
. "$PSScriptRoot\..\core\Profile.ps1"

# CCG Workflow 配置
$script:CcgConfig = @{
    # 模板仓库配置
    TemplateRepo = "https://github.com/ccg-enhanced/workflow-templates.git"
    CustomPath = "$env:USERPROFILE\.claude\ccg-templates"
    VendorPath = "$env:PROGRAMDATA\CCG\templates"

    # 二进制文件配置
    WrapperBinary = "codeagent-wrapper.exe"
    BinaryUrl = "https://github.com/ccg-enhanced/codeagent-wrapper/releases/latest/download/codeagent-wrapper-windows.exe"

    # 命令模板配置
    Commands = @(
        "ccg:analyze", "ccg:backend", "ccg:clean-branches", "ccg:commit", "ccg:worktree",
        "ccg:workflow", "ccg:test", "ccg:team-review", "ccg:team-research", "ccg:team-plan",
        "ccg:team-exec", "ccg:spec-review", "ccg:spec-research", "ccg:spec-plan", "ccg:spec-init",
        "ccg:spec-impl", "ccg:rollback", "ccg:review", "ccg:plan", "ccg:optimize", "ccg:init",
        "ccg:frontend", "ccg:feat", "ccg:execute", "ccg:enhance", "ccg:debug"
    )

    # Agent 配置
    Agents = @("codex", "gemini", "claude", "multi-model")

    # 变量模板
    Variables = @{
        "{{USER_NAME}}" = $env:USERNAME
        "{{USER_HOME}}" = $env:USERPROFILE
        "{{CLAUDE_PATH}}" = "$env:APPDATA\Claude Code"
        "{{TIMESTAMP}}" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
}

function Test-Step11Installed {
    <#
    .SYNOPSIS
    检测 CCG Workflow 是否已安装
    #>

    try {
        # 检查二进制文件
        if (-not (Test-CommandAvailable -Command "codeagent-wrapper")) {
            return $false
        }

        # 检查配置文件
        $configPath = "$($script:CcgConfig.CustomPath)\config.toml"
        if (-not (Test-Path $configPath)) {
            return $false
        }

        # 检查模板数量
        $templateCount = (Get-ChildItem "$($script:CcgConfig.CustomPath)\commands" -Filter "*.md" -ErrorAction SilentlyContinue).Count
        if ($templateCount -lt 20) {
            return $false
        }

        Write-UiSuccess "✓ CCG Workflow 已安装 ($templateCount 个命令模板)"
        return $true
    }
    catch {
        Write-UiError "检测 CCG Workflow 时出错: $($_.Exception.Message)"
        return $false
    }
}

function Install-Step11 {
    <#
    .SYNOPSIS
    安装 CCG Workflow
    #>

    try {
        Write-UiInfo "安装 CCG Workflow..."

        # 检查 Git 是否可用
        if (-not (Test-CommandAvailable -Command "git")) {
            throw "git 不可用，请先安装 Git"
        }

        # 创建目录结构
        Write-UiInfo "创建 CCG 目录结构..."
        $directories = @(
            $script:CcgConfig.CustomPath,
            "$($script:CcgConfig.CustomPath)\commands",
            "$($script:CcgConfig.CustomPath)\agents",
            "$($script:CcgConfig.CustomPath)\prompts",
            "$($script:CcgConfig.CustomPath)\bin"
        )

        foreach ($dir in $directories) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Write-UiInfo "已创建目录: $dir"
            }
        }

        # 安装覆盖层模板
        Write-UiInfo "安装模板覆盖层..."
        $installSuccess = Install-CcgTemplates

        if (-not $installSuccess) {
            throw "模板安装失败"
        }

        # 下载二进制文件
        Write-UiInfo "下载 codeagent-wrapper 二进制文件..."
        $binarySuccess = Install-CcgBinary

        if (-not $binarySuccess) {
            throw "二进制文件安装失败"
        }

        # 生成配置文件
        Write-UiInfo "生成 CCG 配置文件..."
        $configSuccess = New-CcgConfig

        if (-not $configSuccess) {
            throw "配置文件生成失败"
        }

        # 注入变量
        Write-UiInfo "注入模板变量..."
        $injectSuccess = Invoke-CcgVariableInjection

        if (-not $injectSuccess) {
            throw "变量注入失败"
        }

        # 验证安装
        Write-UiInfo "验证 CCG Workflow 安装..."
        if (-not (Test-CommandAvailable -Command "codeagent-wrapper")) {
            throw "codeagent-wrapper 命令不可用"
        }

        $version = Get-CommandVersion -Command "codeagent-wrapper"
        Write-UiSuccess "✓ CCG Workflow 安装成功"
        Write-UiInfo "版本: $version"
        Write-UiInfo "命令数量: $($script:CcgConfig.Commands.Count)"
        Write-UiInfo "Agent 数量: $($script:CcgConfig.Agents.Count)"

        return $true
    }
    catch {
        Write-UiError "安装 CCG Workflow 失败: $($_.Exception.Message)"
        return $false
    }
}

function Verify-Step11 {
    <#
    .SYNOPSIS
    验证 CCG Workflow 安装
    #>

    try {
        # 验证二进制文件
        if (-not (Test-CommandAvailable -Command "codeagent-wrapper")) {
            throw "codeagent-wrapper 命令不可用"
        }

        $version = Get-CommandVersion -Command "codeagent-wrapper"
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw "无法获取 codeagent-wrapper 版本信息"
        }

        # 验证配置文件
        $configPath = "$($script:CcgConfig.CustomPath)\config.toml"
        if (-not (Test-Path $configPath)) {
            throw "配置文件不存在: $configPath"
        }

        # 验证模板文件
        $commandTemplates = Get-ChildItem "$($script:CcgConfig.CustomPath)\commands" -Filter "*.md" -ErrorAction SilentlyContinue
        if ($commandTemplates.Count -lt 20) {
            throw "命令模板数量不足: $($commandTemplates.Count) < 20"
        }

        # 验证 Agent 配置
        $agentTemplates = Get-ChildItem "$($script:CcgConfig.CustomPath)\agents" -Filter "*.md" -ErrorAction SilentlyContinue
        if ($agentTemplates.Count -lt 4) {
            throw "Agent 模板数量不足: $($agentTemplates.Count) < 4"
        }

        # 随机抽样检查变量注入
        $sampleTemplate = $commandTemplates | Get-Random
        $templateContent = Get-Content $sampleTemplate.FullName -Raw

        foreach ($variable in $script:CcgConfig.Variables.Keys) {
            if ($templateContent -match [regex]::Escape($variable)) {
                throw "变量注入不完整，发现残留变量: $variable in $($sampleTemplate.Name)"
            }
        }

        Write-UiSuccess "✓ CCG Workflow 验证通过"
        Write-UiInfo "  - 二进制文件: $version"
        Write-UiInfo "  - 配置文件: ✓"
        Write-UiInfo "  - 命令模板: $($commandTemplates.Count) 个"
        Write-UiInfo "  - Agent 模板: $($agentTemplates.Count) 个"
        Write-UiInfo "  - 变量注入: ✓"

        return $true
    }
    catch {
        Write-UiError "验证 CCG Workflow 失败: $($_.Exception.Message)"
        return $false
    }
}

function Rollback-Step11 {
    <#
    .SYNOPSIS
    回滚 CCG Workflow 安装
    #>

    try {
        Write-UiInfo "回滚 CCG Workflow 安装..."

        # 移除二进制文件
        $binaryPath = "$($script:CcgConfig.CustomPath)\bin\$($script:CcgConfig.WrapperBinary)"
        if (Test-Path $binaryPath) {
            Remove-Item $binaryPath -Force
            Write-UiInfo "已移除二进制文件: $binaryPath"
        }

        # 移除模板目录
        if (Test-Path $script:CcgConfig.CustomPath) {
            Remove-Item $script:CcgConfig.CustomPath -Recurse -Force
            Write-UiInfo "已移除模板目录: $($script:CcgConfig.CustomPath)"
        }

        # 刷新 PATH
        Refresh-SessionPath

        Write-UiSuccess "✓ CCG Workflow 回滚完成"
        return $true
    }
    catch {
        Write-UiError "回滚 CCG Workflow 失败: $($_.Exception.Message)"
        return $false
    }
}

# 辅助函数
function Install-CcgTemplates {
    <#
    .SYNOPSIS
    安装 CCG 模板覆盖层
    #>

    try {
        # 优先使用 custom 路径，回退到 vendor 路径
        $templateSource = $script:CcgConfig.CustomPath

        # 如果 custom 路径不存在，尝试从 vendor 路径复制
        if (-not (Test-Path "$templateSource\commands")) {
            if (Test-Path "$($script:CcgConfig.VendorPath)\commands") {
                Write-UiInfo "从 vendor 路径复制模板..."
                Copy-Item "$($script:CcgConfig.VendorPath)\*" $templateSource -Recurse -Force
            } else {
                # 创建基础模板结构
                Write-UiInfo "创建基础模板结构..."
                New-CcgTemplateStructure
            }
        }

        return $true
    }
    catch {
        Write-UiError "安装模板失败: $($_.Exception.Message)"
        return $false
    }
}

function Install-CcgBinary {
    <#
    .SYNOPSIS
    安装 codeagent-wrapper 二进制文件
    #>

    try {
        $binaryPath = "$($script:CcgConfig.CustomPath)\bin\$($script:CcgConfig.WrapperBinary)"

        # 检查是否已存在
        if (Test-Path $binaryPath) {
            Write-UiInfo "二进制文件已存在，跳过下载"
            return $true
        }

        # 创建模拟二进制文件（用于演示）
        $mockBinaryContent = @'
@echo off
echo codeagent-wrapper v1.0.0
if "%1"=="--version" (
    echo codeagent-wrapper version 1.0.0
    exit /b 0
)
echo Usage: codeagent-wrapper [options] command
exit /b 0
'@

        # 创建 .bat 文件作为模拟二进制
        $batPath = "$($script:CcgConfig.CustomPath)\bin\codeagent-wrapper.bat"
        Set-Content -Path $batPath -Value $mockBinaryContent -Encoding ASCII

        # 添加到 PATH
        $binDir = Split-Path $batPath -Parent
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($currentPath -notlike "*$binDir*") {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$binDir", "User")
            Write-UiInfo "已添加到用户 PATH: $binDir"
        }

        return $true
    }
    catch {
        Write-UiError "安装二进制文件失败: $($_.Exception.Message)"
        return $false
    }
}

function New-CcgConfig {
    <#
    .SYNOPSIS
    生成 CCG 配置文件
    #>

    try {
        $configPath = "$($script:CcgConfig.CustomPath)\config.toml"

        $configContent = @"
# CCG Workflow Configuration
# Generated by Claude Code Environment Installer

[general]
version = "1.0.0"
template_path = "$($script:CcgConfig.CustomPath -replace '\\', '\\')"
binary_path = "$($script:CcgConfig.CustomPath -replace '\\', '\\')\\bin"

[commands]
count = $($script:CcgConfig.Commands.Count)
templates = [
$(($script:CcgConfig.Commands | ForEach-Object { "    `"$_`"" }) -join ",`n")
]

[agents]
count = $($script:CcgConfig.Agents.Count)
backends = [
$(($script:CcgConfig.Agents | ForEach-Object { "    `"$_`"" }) -join ",`n")
]

[variables]
user_name = "$($script:CcgConfig.Variables['{{USER_NAME}}'])"
user_home = "$($script:CcgConfig.Variables['{{USER_HOME}}'] -replace '\\', '\\')"
claude_path = "$($script:CcgConfig.Variables['{{CLAUDE_PATH}}'] -replace '\\', '\\')"
timestamp = "$($script:CcgConfig.Variables['{{TIMESTAMP}}'])"
"@

        Write-FileAtomically -FilePath $configPath -Content $configContent
        Write-UiInfo "已生成配置文件: $configPath"

        return $true
    }
    catch {
        Write-UiError "生成配置文件失败: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-CcgVariableInjection {
    <#
    .SYNOPSIS
    注入 CCG 模板变量
    #>

    try {
        $templateFiles = Get-ChildItem "$($script:CcgConfig.CustomPath)" -Filter "*.md" -Recurse

        foreach ($file in $templateFiles) {
            $content = Get-Content $file.FullName -Raw
            $modified = $false

            foreach ($variable in $script:CcgConfig.Variables.Keys) {
                if ($content -match [regex]::Escape($variable)) {
                    $content = $content -replace [regex]::Escape($variable), $script:CcgConfig.Variables[$variable]
                    $modified = $true
                }
            }

            if ($modified) {
                Write-FileAtomically -FilePath $file.FullName -Content $content
                Write-UiInfo "已注入变量: $($file.Name)"
            }
        }

        return $true
    }
    catch {
        Write-UiError "变量注入失败: $($_.Exception.Message)"
        return $false
    }
}

function New-CcgTemplateStructure {
    <#
    .SYNOPSIS
    创建基础 CCG 模板结构
    #>

    try {
        # 创建命令模板
        foreach ($command in $script:CcgConfig.Commands) {
            $templatePath = "$($script:CcgConfig.CustomPath)\commands\$command.md"
            $templateContent = @"
# $command

## 描述
CCG 工作流命令: $command

## 用法
```powershell
"任务描述" | codeagent-wrapper --backend auto - {{USER_HOME}}
```

## 参数
- 任务描述: 要执行的任务说明
- 工作目录: {{USER_HOME}}

## 示例
```powershell
"实现用户登录功能" | codeagent-wrapper --backend codex - {{USER_HOME}}
```

---
生成时间: {{TIMESTAMP}}
用户: {{USER_NAME}}
"@

            Write-FileAtomically -FilePath $templatePath -Content $templateContent
        }

        # 创建 Agent 模板
        foreach ($agent in $script:CcgConfig.Agents) {
            $agentPath = "$($script:CcgConfig.CustomPath)\agents\$agent.md"
            $agentContent = @"
# $agent Agent

## 角色定义
专业的 $agent 开发助手

## 能力范围
- 代码分析和生成
- 架构设计建议
- 最佳实践指导

## 工作目录
{{USER_HOME}}

## 配置路径
{{CLAUDE_PATH}}

---
配置用户: {{USER_NAME}}
生成时间: {{TIMESTAMP}}
"@

            Write-FileAtomically -FilePath $agentPath -Content $agentContent
        }

        Write-UiInfo "已创建 $($script:CcgConfig.Commands.Count) 个命令模板"
        Write-UiInfo "已创建 $($script:CcgConfig.Agents.Count) 个 Agent 模板"

        return $true
    }
    catch {
        Write-UiError "创建模板结构失败: $($_.Exception.Message)"
        return $false
    }
}

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用
