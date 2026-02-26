# TUI 组件库 - CCQ
# 作者: 哈雷酱 (本小姐的杰作！)
# 功能: 提供终端用户界面组件，包括彩色输出、菜单、进度条等

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 终端能力检测
$script:IsWindowsTerminal = $false
$script:SupportsAnsi = $false

function Initialize-TerminalCapabilities {
    <#
    .SYNOPSIS
    检测终端能力并初始化 ANSI 支持
    #>

    # 检测 Windows Terminal
    $script:IsWindowsTerminal = $env:WT_SESSION -ne $null

    # 检测 ANSI 支持
    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell 6+ 默认支持 ANSI
            $script:SupportsAnsi = $true
        } elseif ($script:IsWindowsTerminal) {
            # Windows Terminal 支持 ANSI
            $script:SupportsAnsi = $true
        } else {
            # PowerShell 5.1 在普通控制台中不支持 ANSI
            # 只有在 Windows Terminal 或 VS Code 终端中才支持
            $script:SupportsAnsi = $false
        }
    } catch {
        $script:SupportsAnsi = $false
    }

    # 检测 Emoji 支持（只有 Windows Terminal 和 PowerShell 7+ 支持）
    $script:SupportsEmoji = $script:IsWindowsTerminal -or ($PSVersionTable.PSVersion.Major -ge 7)
}

# Emoji 映射表（Emoji -> 纯文本替代）
$script:EmojiMap = @{
    "🔍" = "[检测]"
    "🖥️" = "[终端]"
    "⚡" = "[PS7]"
    "🔧" = "[配置]"
    "🚀" = "[启动]"
    "📋" = "[摘要]"
    "💡" = "[提示]"
    "🎉" = "[完成]"
    "⚠" = "[警告]"
    "✓" = "[成功]"
    "✗" = "[失败]"
    "🔐" = "[权限]"
}

function Convert-EmojiToText {
    <#
    .SYNOPSIS
    将 Emoji 转换为纯文本（如果终端不支持 Emoji）
    .PARAMETER Text
    包含 Emoji 的文本
    .RETURNS
    转换后的文本
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if ($script:SupportsEmoji) {
        return $Text
    }

    # 替换所有 Emoji
    $result = $Text
    foreach ($emoji in $script:EmojiMap.Keys) {
        $result = $result -replace [regex]::Escape($emoji), $script:EmojiMap[$emoji]
    }

    return $result
}

# ANSI 颜色代码定义
# 注意：PowerShell 5.1 不支持 `e 转义序列，需要使用 [char]27
$script:EscapeChar = [char]27
$script:AnsiColors = @{
    Reset = "$script:EscapeChar[0m"
    Bold = "$script:EscapeChar[1m"

    # 主色调：Claude 官方橙色（标题、重点）
    # 使用 24-bit RGB 颜色（Windows Terminal / PS 7+ 支持）
    Primary = "$script:EscapeChar[38;2;217;119;87m"        # Claude 主色 #D97757
    BrightPrimary = "$script:EscapeChar[38;2;232;148;106m" # Claude 亮色 #E8946A

    # 成功：亮绿色
    Green = "$script:EscapeChar[32m"
    BrightGreen = "$script:EscapeChar[92m"

    # 警告：黄色
    Yellow = "$script:EscapeChar[33m"
    BrightYellow = "$script:EscapeChar[93m"

    # 错误：亮红色
    Red = "$script:EscapeChar[31m"
    BrightRed = "$script:EscapeChar[91m"

    # 辅助：灰色
    Gray = "$script:EscapeChar[90m"
    White = "$script:EscapeChar[97m"
}

# ─── 输出模式控制 ────────────────────────────────────────────────────────────

enum CcqOutputMode {
    Normal = 0
    Developer = 1
}

enum CcqOutputLevel {
    Essential = 0
    Detail = 1
    Debug = 2
}

if (-not (Get-Variable -Scope Script -Name CcqOutputMode -ErrorAction SilentlyContinue)) {
    $script:CcqOutputMode = [CcqOutputMode]::Normal
}

function Write-UiInfo {
    <#
    .SYNOPSIS
    输出信息级别的彩色文本
    .PARAMETER Message
    要输出的消息
    .PARAMETER NoNewline
    不添加换行符
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$NoNewline
    )

    # 转换 Emoji
    $Message = Convert-EmojiToText -Text $Message

    if ($script:SupportsAnsi) {
        $coloredMessage = "$($script:AnsiColors.Primary)$Message$($script:AnsiColors.Reset)"
    } else {
        $coloredMessage = $Message
    }

    if ($NoNewline) {
        Write-Host $coloredMessage -NoNewline
    } else {
        Write-Host $coloredMessage
    }
}

function Write-UiSuccess {
    <#
    .SYNOPSIS
    输出成功级别的彩色文本
    .PARAMETER Message
    要输出的消息
    .PARAMETER NoNewline
    不添加换行符
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$NoNewline
    )

    # 转换 Emoji
    $Message = Convert-EmojiToText -Text $Message

    if ($script:SupportsAnsi) {
        $coloredMessage = "$($script:AnsiColors.BrightGreen)$Message$($script:AnsiColors.Reset)"
    } else {
        $coloredMessage = $Message
    }

    if ($NoNewline) {
        Write-Host $coloredMessage -NoNewline
    } else {
        Write-Host $coloredMessage
    }
}

function Write-UiWarn {
    <#
    .SYNOPSIS
    输出警告级别的彩色文本
    .PARAMETER Message
    要输出的消息
    .PARAMETER NoNewline
    不添加换行符
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$NoNewline
    )

    # 转换 Emoji
    $Message = Convert-EmojiToText -Text $Message

    if ($script:SupportsAnsi) {
        $coloredMessage = "$($script:AnsiColors.BrightYellow)$Message$($script:AnsiColors.Reset)"
    } else {
        $coloredMessage = $Message
    }

    if ($NoNewline) {
        Write-Host $coloredMessage -NoNewline
    } else {
        Write-Host $coloredMessage
    }
}

function Write-UiError {
    <#
    .SYNOPSIS
    输出错误级别的彩色文本
    .PARAMETER Message
    要输出的消息
    .PARAMETER NoNewline
    不添加换行符
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$NoNewline
    )

    # 转换 Emoji
    $Message = Convert-EmojiToText -Text $Message

    if ($script:SupportsAnsi) {
        $coloredMessage = "$($script:AnsiColors.BrightRed)$Message$($script:AnsiColors.Reset)"
    } else {
        $coloredMessage = $Message
    }

    if ($NoNewline) {
        Write-Host $coloredMessage -NoNewline
    } else {
        Write-Host $coloredMessage
    }
}

# ─── 输出级别控制函数 ────────────────────────────────────────────────────────

function Write-UiOutput {
    <#
    .SYNOPSIS
    带级别控制的统一输出函数，根据当前输出模式过滤
    .PARAMETER Message
    要输出的消息
    .PARAMETER Level
    输出级别：Essential（必要）, Detail（详细）, Debug（调试）
    .PARAMETER Type
    输出类型：Info, Success, Warn, Error
    .PARAMETER NoNewline
    不添加换行符
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [CcqOutputLevel]$Level = [CcqOutputLevel]::Essential,

        [ValidateSet('Info', 'Success', 'Warn', 'Error')]
        [string]$Type = 'Info',

        [switch]$NoNewline
    )

    if ($script:CcqOutputMode -eq [CcqOutputMode]::Normal) {
        if ($Level -gt [CcqOutputLevel]::Essential) {
            return
        }
    }

    switch ($Type) {
        'Info'    { Write-UiInfo $Message -NoNewline:$NoNewline }
        'Success' { Write-UiSuccess $Message -NoNewline:$NoNewline }
        'Warn'    { Write-UiWarn $Message -NoNewline:$NoNewline }
        'Error'   { Write-UiError $Message -NoNewline:$NoNewline }
    }
}

function Set-CcqOutputMode {
    <#
    .SYNOPSIS
    设置全局输出模式
    #>
    param(
        [Parameter(Mandatory = $true)]
        [CcqOutputMode]$Mode
    )
    $script:CcqOutputMode = $Mode
}

function Get-CcqOutputMode {
    <#
    .SYNOPSIS
    获取当前输出模式
    #>
    return $script:CcqOutputMode
}

function Get-StringDisplayWidth {
    <#
    .SYNOPSIS
    计算字符串在终端中的显示宽度（考虑中文字符占2个宽度）
    .PARAMETER Text
    要计算的字符串
    .RETURNS
    显示宽度
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $width = 0
    foreach ($char in $Text.ToCharArray()) {
        # 判断是否为全角字符（中文、日文、韩文等）
        $code = [int][char]$char
        if (($code -ge 0x4E00 -and $code -le 0x9FFF) -or    # CJK 统一汉字
            ($code -ge 0x3400 -and $code -le 0x4DBF) -or    # CJK 扩展 A
            ($code -ge 0x20000 -and $code -le 0x2A6DF) -or  # CJK 扩展 B
            ($code -ge 0x2A700 -and $code -le 0x2B73F) -or  # CJK 扩展 C
            ($code -ge 0x2B740 -and $code -le 0x2B81F) -or  # CJK 扩展 D
            ($code -ge 0x2B820 -and $code -le 0x2CEAF) -or  # CJK 扩展 E
            ($code -ge 0x3000 -and $code -le 0x303F) -or    # CJK 符号和标点
            ($code -ge 0xFF00 -and $code -le 0xFFEF)) {     # 全角 ASCII
            $width += 2
        } else {
            $width += 1
        }
    }
    return $width
}

function Show-AsciiBanner {
    <#
    .SYNOPSIS
    显示 ASCII Art 横幅，自适应终端宽度
    .PARAMETER Title
    横幅标题
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    # 转换 Emoji
    $Title = Convert-EmojiToText -Text $Title

    # 获取终端宽度
    $terminalWidth = 80
    try {
        $terminalWidth = [Console]::WindowWidth
        if ($terminalWidth -lt 40) { $terminalWidth = 80 }
    } catch {
        # 如果无法获取宽度，使用默认值
    }

    # 计算边框和内容宽度
    $borderWidth = [Math]::Min($terminalWidth - 4, 76)
    $contentWidth = $borderWidth - 4

    # 创建横幅
    $topBorder = "╔" + ("═" * $borderWidth) + "╗"
    $bottomBorder = "╚" + ("═" * $borderWidth) + "╝"
    $emptyLine = "║" + (" " * $borderWidth) + "║"

    # 处理标题文本（使用显示宽度而非字符长度）
    $titleLines = @()
    $titleDisplayWidth = Get-StringDisplayWidth -Text $Title

    if ($titleDisplayWidth -le $contentWidth) {
        $padding = [Math]::Floor(($contentWidth - $titleDisplayWidth) / 2)
        $remainingSpace = $contentWidth - $titleDisplayWidth - $padding
        $titleLine = "║  " + (" " * $padding) + $Title + (" " * $remainingSpace) + "  ║"
        $titleLines += $titleLine
    } else {
        # 如果标题太长，分行显示
        $words = $Title -split ' '
        $currentLine = ""

        foreach ($word in $words) {
            $testLine = if ($currentLine) { $currentLine + " " + $word } else { $word }
            $testWidth = Get-StringDisplayWidth -Text $testLine

            if ($testWidth -le $contentWidth) {
                $currentLine = $testLine
            } else {
                if ($currentLine) {
                    $lineWidth = Get-StringDisplayWidth -Text $currentLine
                    $padding = [Math]::Floor(($contentWidth - $lineWidth) / 2)
                    $remainingSpace = $contentWidth - $lineWidth - $padding
                    $titleLine = "║  " + (" " * $padding) + $currentLine + (" " * $remainingSpace) + "  ║"
                    $titleLines += $titleLine
                }
                $currentLine = $word
            }
        }

        if ($currentLine) {
            $lineWidth = Get-StringDisplayWidth -Text $currentLine
            $padding = [Math]::Floor(($contentWidth - $lineWidth) / 2)
            $remainingSpace = $contentWidth - $lineWidth - $padding
            $titleLine = "║  " + (" " * $padding) + $currentLine + (" " * $remainingSpace) + "  ║"
            $titleLines += $titleLine
        }
    }

    # 输出横幅
    Write-UiInfo $topBorder
    Write-UiInfo $emptyLine

    foreach ($line in $titleLines) {
        Write-UiInfo $line
    }

    Write-UiInfo $emptyLine
    Write-UiInfo $bottomBorder
    Write-Host ""
}

function Show-CcqLogo {
    <#
    .SYNOPSIS
    显示 CCQ ASCII Art Logo + 副标题
    .PARAMETER Subtitle
    Logo 下方的副标题文字（可选）
    #>
    param(
        [string]$Subtitle = ""
    )

    $logoLines = @(
        "  ██████╗  ██████╗  ██████╗ "
        " ██╔════╝ ██╔════╝ ██╔═══██╗"
        " ██║      ██║      ██║   ██║"
        " ██║      ██║      ██║▄▄ ██║"
        "  ╚██████╗ ╚██████╗ ╚██████╔╝"
        "  ╚═════╝  ╚═════╝  ╚══▀▀═╝ "
    )

    Write-Host ""
    foreach ($line in $logoLines) {
        Write-UiInfo $line
    }

    if ($Subtitle) {
        $Subtitle = Convert-EmojiToText -Text $Subtitle
        Write-Host ""
        Write-UiInfo "  $Subtitle"
    }
    Write-Host ""
}

function Show-SingleSelectMenu {
    <#
    .SYNOPSIS
    显示箭头键单选菜单
    .PARAMETER Title
    菜单标题
    .PARAMETER Options
    选项数组
    .PARAMETER DefaultIndex
    默认选中的索引
    .RETURNS
    选中的索引
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string[]]$Options,

        [int]$DefaultIndex = 0
    )

    if ($Options.Count -eq 0) {
        throw "选项数组不能为空"
    }

    $selectedIndex = [Math]::Max(0, [Math]::Min($DefaultIndex, $Options.Count - 1))

    # 如果不支持 ANSI，使用简化版本
    if (-not $script:SupportsAnsi) {
        Write-UiInfo $Title
        Write-Host ""

        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host "  $($i + 1). $($Options[$i])"
        }

        do {
            Write-Host ""
            $input = Read-Host "请选择 (1-$($Options.Count))"
            $choice = 0
            if ([int]::TryParse($input, [ref]$choice) -and $choice -ge 1 -and $choice -le $Options.Count) {
                return $choice - 1
            }
            Write-UiError "无效选择，请输入 1 到 $($Options.Count) 之间的数字"
        } while ($true)
    }

    # 支持 ANSI 的交互式菜单
    Write-UiInfo $Title
    Write-Host ""

    function Show-Menu {
        for ($i = 0; $i -lt $Options.Count; $i++) {
            # 清除当前行（使用 ANSI 序列）
            Write-Host "`e[2K" -NoNewline

            if ($i -eq $selectedIndex) {
                Write-UiSuccess "  ► $($Options[$i])"
            } else {
                Write-Host "    $($Options[$i])"
            }
        }
    }

    # 隐藏光标
    try { [Console]::CursorVisible = $false } catch { }

    try {
        Show-Menu

        while ($true) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    $selectedIndex = ($selectedIndex - 1 + $Options.Count) % $Options.Count
                    # 向上移动到菜单起始位置
                    for ($i = 0; $i -lt $Options.Count; $i++) {
                        Write-Host "`e[A" -NoNewline
                    }
                    Show-Menu
                }
                'DownArrow' {
                    $selectedIndex = ($selectedIndex + 1) % $Options.Count
                    # 向上移动到菜单起始位置
                    for ($i = 0; $i -lt $Options.Count; $i++) {
                        Write-Host "`e[A" -NoNewline
                    }
                    Show-Menu
                }
                'Enter' {
                    Write-Host ""
                    return $selectedIndex
                }
                'Escape' {
                    Write-Host ""
                    return -1
                }
            }
        }
    } finally {
        # 恢复光标
        try { [Console]::CursorVisible = $true } catch { }
    }
}

function Show-MultiSelectMenu {
    <#
    .SYNOPSIS
    显示箭头键多选菜单
    .PARAMETER Title
    菜单标题
    .PARAMETER Options
    选项数组
    .PARAMETER DefaultSelected
    默认选中的索引数组
    .RETURNS
    选中的索引数组
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string[]]$Options,

        [int[]]$DefaultSelected = @()
    )

    if ($Options.Count -eq 0) {
        throw "选项数组不能为空"
    }

    $selectedIndex = 0
    $selectedItems = @{}

    # 初始化默认选中项
    foreach ($index in $DefaultSelected) {
        if ($index -ge 0 -and $index -lt $Options.Count) {
            $selectedItems[$index] = $true
        }
    }

    # 如果不支持 ANSI，使用简化版本
    if (-not $script:SupportsAnsi) {
        Write-UiInfo $Title
        Write-Host ""

        for ($i = 0; $i -lt $Options.Count; $i++) {
            $checked = if ($selectedItems.ContainsKey($i)) { "[✓]" } else { "[ ]" }
            Write-Host "  $($i + 1). $checked $($Options[$i])"
        }

        Write-Host ""
        Write-Host "输入要切换的选项编号（用空格分隔），或直接按 Enter 确认："

        $input = Read-Host
        if ($input.Trim()) {
            $choices = $input -split '\s+' | Where-Object { $_ }
            foreach ($choice in $choices) {
                $index = 0
                if ([int]::TryParse($choice, [ref]$index) -and $index -ge 1 -and $index -le $Options.Count) {
                    $index--
                    if ($selectedItems.ContainsKey($index)) {
                        $selectedItems.Remove($index)
                    } else {
                        $selectedItems[$index] = $true
                    }
                }
            }
        }

        return @($selectedItems.Keys | Sort-Object)
    }

    # 支持 ANSI 的交互式菜单
    Write-UiInfo $Title
    Write-Host ""
    Write-UiInfo "使用 ↑↓ 导航，空格键选择/取消，Enter 确认，Esc 取消"
    Write-Host ""

    function Show-Menu {
        for ($i = 0; $i -lt $Options.Count; $i++) {
            # 清除当前行（使用 ANSI 序列）
            Write-Host "`e[2K" -NoNewline

            $checked = if ($selectedItems.ContainsKey($i)) { "[✓]" } else { "[ ]" }

            if ($i -eq $selectedIndex) {
                Write-UiSuccess "  ► $checked $($Options[$i])"
            } else {
                Write-Host "    $checked $($Options[$i])"
            }
        }
    }

    # 隐藏光标
    try { [Console]::CursorVisible = $false } catch { }

    try {
        Show-Menu

        while ($true) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    $selectedIndex = ($selectedIndex - 1 + $Options.Count) % $Options.Count
                    # 向上移动到菜单起始位置
                    for ($i = 0; $i -lt $Options.Count; $i++) {
                        Write-Host "`e[A" -NoNewline
                    }
                    Show-Menu
                }
                'DownArrow' {
                    $selectedIndex = ($selectedIndex + 1) % $Options.Count
                    # 向上移动到菜单起始位置
                    for ($i = 0; $i -lt $Options.Count; $i++) {
                        Write-Host "`e[A" -NoNewline
                    }
                    Show-Menu
                }
                'Spacebar' {
                    if ($selectedItems.ContainsKey($selectedIndex)) {
                        $selectedItems.Remove($selectedIndex)
                    } else {
                        $selectedItems[$selectedIndex] = $true
                    }
                    # 向上移动到菜单起始位置
                    for ($i = 0; $i -lt $Options.Count; $i++) {
                        Write-Host "`e[A" -NoNewline
                    }
                    Show-Menu
                }
                'Enter' {
                    Write-Host ""
                    return @($selectedItems.Keys | Sort-Object)
                }
                'Escape' {
                    Write-Host ""
                    return @()
                }
            }
        }
    } finally {
        # 恢复光标
        try { [Console]::CursorVisible = $true } catch { }
    }
}

function Show-StepProgress {
    <#
    .SYNOPSIS
    显示步骤进度条或 Spinner
    .PARAMETER StepName
    步骤名称
    .PARAMETER Status
    状态：Running, Success, Failed
    .PARAMETER ShowSpinner
    是否显示 Spinner 动画
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepName,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Running', 'Success', 'Failed', 'Skipped')]
        [string]$Status,

        [switch]$ShowSpinner
    )

    $statusIcon = switch ($Status) {
        'Running' { if ($ShowSpinner) { "......" } else { "[......]" } }
        'Success' { "[PASS]" }
        'Failed'  { "[FAIL]" }
        'Skipped' { "[SKIP]" }
    }

    $message = "  $statusIcon $StepName"

    switch ($Status) {
        'Running' { Write-UiInfo $message }
        'Success' { Write-UiSuccess $message }
        'Failed' { Write-UiError $message }
    }
}

function Show-InstallSummary {
    <#
    .SYNOPSIS
    显示安装摘要表格
    .PARAMETER Items
    安装项目数组，每个项目包含 Name, Status, Version 属性
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Items
    )

    if ($Items.Count -eq 0) {
        Write-UiWarn "没有安装项目"
        return
    }

    # 计算列宽
    $nameWidth = ($Items | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $statusWidth = ($Items | ForEach-Object { $_.Status.Length } | Measure-Object -Maximum).Maximum
    $versionWidth = ($Items | ForEach-Object { $_.Version.Length } | Measure-Object -Maximum).Maximum

    # 确保最小宽度
    $nameWidth = [Math]::Max($nameWidth, 10)
    $statusWidth = [Math]::Max($statusWidth, 8)
    $versionWidth = [Math]::Max($versionWidth, 8)

    # 表格边框
    $separator = "+" + ("-" * ($nameWidth + 2)) + "+" + ("-" * ($statusWidth + 2)) + "+" + ("-" * ($versionWidth + 2)) + "+"

    # 表头
    Write-UiInfo $separator
    $header = "| $("组件".PadRight($nameWidth)) | $("状态".PadRight($statusWidth)) | $("版本".PadRight($versionWidth)) |"
    Write-UiInfo $header
    Write-UiInfo $separator

    # 数据行
    foreach ($item in $Items) {
        $name = $item.Name.PadRight($nameWidth)
        $status = $item.Status.PadRight($statusWidth)
        $version = $item.Version.PadRight($versionWidth)

        $row = "| $name | $status | $version |"

        # 根据状态着色
        switch ($item.Status) {
            { $_ -match "成功|已安装|✓" } { Write-UiSuccess $row }
            { $_ -match "失败|错误|✗" } { Write-UiError $row }
            { $_ -match "警告|跳过" } { Write-UiWarn $row }
            default { Write-Host $row }
        }
    }

    Write-UiInfo $separator
}

function Show-ErrorDetails {
    <#
    .SYNOPSIS
    显示错误详情，支持友好信息和可展开详情
    .PARAMETER FriendlyMessage
    用户友好的错误信息
    .PARAMETER TechnicalDetails
    技术详情
    .PARAMETER ShowDetails
    是否默认显示详情
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FriendlyMessage,

        [string]$TechnicalDetails,

        [switch]$ShowDetails
    )

    Write-UiError "❌ $FriendlyMessage"

    if ($TechnicalDetails) {
        if ($ShowDetails) {
            Write-Host ""
            Write-UiInfo "技术详情："
            Write-Host $TechnicalDetails -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-UiInfo "按 [D] 键查看技术详情，或其他键跳过..."

            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'd' -or $key.KeyChar -eq 'D') {
                Write-Host ""
                Write-UiInfo "技术详情："
                Write-Host $TechnicalDetails -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
}

# 初始化终端能力
Initialize-TerminalCapabilities

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用