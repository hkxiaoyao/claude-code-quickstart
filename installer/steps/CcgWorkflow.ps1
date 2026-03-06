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

# CCG 规则文件模板（整合原 ccq-multimodel.md + ccq-workflow.md）
$script:CcgWorkflowRuleTemplate = @'
# 多模型协作 + 工作流增强（CCG）

> 自动生成，请勿手动编辑。由 CCG Workflow 步骤管理。

## 后端任务 → Codex

```powershell
"[任务描述]" | codeagent-wrapper --backend codex - [工作目录]
```

适用：后端 logic、算法实现、数据库操作、API 开发、性能优化、调试分析

## 前端任务 → Gemini

```powershell
"[任务描述]" | codeagent-wrapper --backend gemini - [工作目录]
```

适用：UI/UX 组件、CSS 样式、响应式布局、前端交互逻辑

## 会话复用

每次调用返回 `SESSION_ID: xxx`，后续用 `resume xxx` 复用上下文：

```powershell
"[后续任务]" | codeagent-wrapper --backend <codex|gemini> resume <SESSION_ID> - [工作目录]
```

## 并行调用

使用 `run_in_background: true` 启动后台任务，用 `TaskOutput` 等待结果。
必须等所有模型返回后才能进入下一阶段。

```python
# 示例：并行启动 Codex 和 Gemini
Bash(command='"任务描述" | codeagent-wrapper --backend codex ...', run_in_background=True)
Bash(command='"任务描述" | codeagent-wrapper --backend gemini ...', run_in_background=True)

# 等待结果
TaskOutput(task_id="<TASK_ID>", block=True, timeout=600000)
```

## 上下文检索（生成代码前执行）

**工具优先级**：

1. `mcp__ace-tool__search_context`（首选）- 纯语义搜索，适合开放性探索
2. `mcp__contextweaver__codebase-retrieval`（次选）- 混合引擎（语义+精确匹配）
3. `Glob` + `Grep`（回退）- MCP 不可用时的兜底方案

**检索策略**：

- 使用自然语言构建语义查询（Where/What/How）
- 完整性检查：获取相关类、函数、变量的完整定义与签名
- 若上下文不足，递归检索直至信息完整

## 需求对齐

若检索后需求仍有模糊空间，输出引导性问题列表，直至需求边界清晰。
'@

function Get-CcgWorkflowFingerprint {
    <#
    .SYNOPSIS
    计算 CcgWorkflow 步骤的组合内容指纹（引擎版本 + 规则模板哈希）
    .DESCRIPTION
    组合指纹确保引擎版本变更或规则模板变更都能触发更新检测。
    .RETURNS
    string - 组合指纹字符串，或空字符串（未安装时）
    #>
    $parts = @()

    # 引擎版本分量
    if (Test-CommandAvailable "codeagent-wrapper") {
        $parts += "engine:" + (Get-CommandVersion -Command "codeagent-wrapper")
    } else {
        $parts += "engine:unknown"
    }

    # 规则模板分量
    $parts += "rules:" + (Get-StringFingerprint -Text $script:CcgWorkflowRuleTemplate)

    return Get-StringFingerprint -Text ($parts -join "`n")
}

function Get-CcgWorkflowUpdateComponents {
    <#
    .SYNOPSIS
    独立检测 CcgWorkflow 的引擎版本与规则文件漂移状态
    .DESCRIPTION
    拆分检测引擎（npm 版本）和规则（文件内容+旧文件迁移）两个分量，
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

    # ── 规则分量：文件内容对比 + 遗留旧文件检查 ──
    $rulesDir = "$script:ClaudeDir\rules"
    $ccgRulePath = Join-Path $rulesDir "ccq-ccgworkflow.md"

    # 检查目标规则文件是否存在且内容一致
    $ruleContentMatch = $false
    if (Test-Path $ccgRulePath) {
        $existingRule = Get-Content $ccgRulePath -Raw -ErrorAction SilentlyContinue
        $ruleNormalized = $script:CcgWorkflowRuleTemplate -replace "`r`n", "`n"
        $existingNormalized = if ($existingRule) { $existingRule -replace "`r`n", "`n" } else { "" }
        $ruleContentMatch = ($ruleNormalized.Trim() -eq $existingNormalized.Trim())
    }

    # 检查遗留旧规则文件（需迁移删除）
    $legacyRuleFiles = @("ccq-multimodel.md", "ccq-tools.md", "ccq-workflow.md")
    $legacyFilesExist = $false
    foreach ($f in $legacyRuleFiles) {
        if (Test-Path (Join-Path $rulesDir $f)) {
            $legacyFilesExist = $true
            break
        }
    }

    if (-not $ruleContentMatch -or $legacyFilesExist) {
        $result.RulesNeedUpdate = $true
    }

    # ── 综合判定 ──
    if ($result.EngineNeedUpdate -and $result.RulesNeedUpdate) {
        $result.UpdateKind = "engine+rules"
        $result.StatusHint = "引擎与规则均需更新"
    } elseif ($result.EngineNeedUpdate) {
        $result.UpdateKind = "engine-only"
        $result.StatusHint = "引擎版本可更新 ($($result.LocalVersion) -> $($result.LatestVersion))"
    } elseif ($result.RulesNeedUpdate) {
        $result.UpdateKind = "rules-only"
        $result.StatusHint = "规则文件更新"
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

        # ── 写入 CCG 规则文件 ──
        $rulesDir = "$script:ClaudeDir\rules"
        if (-not (Test-Path $rulesDir)) {
            New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
        }
        $ccgRulePath = Join-Path $rulesDir "ccq-ccgworkflow.md"
        $ruleWriteResult = Write-FileAtomically -FilePath $ccgRulePath -Content $script:CcgWorkflowRuleTemplate
        if (-not $ruleWriteResult) {
            Write-UiWarn "CCG 规则文件写入失败，但不影响主安装"
        } else {
            Write-UiInfo "已写入: rules/ccq-ccgworkflow.md"
        }

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
        Write-UiInfo "更新 CCG Workflow..."

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

        Write-UiInfo "当前版本: $oldVersion"
        if ($components.LatestVersion) {
            Write-UiInfo "最新版本: $($components.LatestVersion)"
        }

        # ── 无更新 → noop ──
        if (-not $components.EngineNeedUpdate -and -not $components.RulesNeedUpdate) {
            Write-UiInfo "CCG Workflow 已是最新（引擎与规则均无变更）"
            $result.UpdatedItems = @("noop::CcgWorkflow::no-change")
            $result.Data["NewVersion"] = $oldVersion
            $result.Success = $true
            return $result
        }

        Write-UiInfo "更新类型: $($components.StatusHint)"

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
                            Write-UiWarn "检测到 .claude.json 中的 mcpServers 在更新过程中被修改，请手动检查"
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
                Write-UiSuccess "CCG Workflow 引擎已更新: $oldVersion -> $newVersion"
            } else {
                $result.UpdatedItems += "npx::ccg-workflow::reinstalled"
                Write-UiInfo "CCG Workflow 引擎已重新安装 ($newVersion)"
            }
        } else {
            $result.Data["NewVersion"] = $oldVersion
        }

        # ── 规则更新分支 ──
        if ($components.RulesNeedUpdate) {
            $rulesDir = "$script:ClaudeDir\rules"
            if (-not (Test-Path $rulesDir)) {
                New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
            }

            # 迁移：删除旧的 rules 文件（CcgWorkflow 所有权范围内的显式名单）
            $legacyRuleFiles = @("ccq-multimodel.md", "ccq-tools.md", "ccq-workflow.md")
            foreach ($oldFile in $legacyRuleFiles) {
                $oldPath = Join-Path $rulesDir $oldFile
                if (Test-Path $oldPath) {
                    try {
                        Remove-Item $oldPath -Force -ErrorAction Stop
                        $result.UpdatedItems += "file::rules/${oldFile}::migrated-deleted"
                        Write-UiInfo "已删除旧文件: rules/$oldFile（已整合）"
                    } catch {
                        Write-UiWarn "无法删除旧文件: $oldFile"
                    }
                }
            }

            # 写入/更新 CCG 规则文件
            $ccgRulePath = Join-Path $rulesDir "ccq-ccgworkflow.md"
            $ruleWriteResult = Write-FileAtomically -FilePath $ccgRulePath -Content $script:CcgWorkflowRuleTemplate
            if ($ruleWriteResult) {
                $result.UpdatedItems += "file::rules/ccq-ccgworkflow.md::overwritten"
                Write-UiSuccess "CCG Workflow 规则文件已更新"
            }
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
