# 文件安全编辑 - CCQ
# 作者: 哈雷酱 (本小姐的安全编辑杰作！)
# 功能: 提供文件备份、标记块编辑、原子写入等安全文件操作

#Requires -Version 5.1

# 严格模式
Set-StrictMode -Version Latest

# 全局配置
$script:BackupDirectory = "$env:TEMP\ClaudeEnvInstaller\Backups"
$script:ManagedBlockStartMarker = "# >>> Claude Code Quickstart >>>"
$script:ManagedBlockEndMarker = "# <<< Claude Code Quickstart <<<"

function Initialize-BackupDirectory {
    <#
    .SYNOPSIS
    初始化备份目录
    #>
    param()

    try {
        if (-not (Test-Path $script:BackupDirectory)) {
            New-Item -Path $script:BackupDirectory -ItemType Directory -Force | Out-Null
            Write-Host "✓ 备份目录已创建: $script:BackupDirectory" -ForegroundColor Green
        }
    } catch {
        Write-Host "警告: 无法创建备份目录: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Backup-FileWithTimestamp {
    <#
    .SYNOPSIS
    创建带时间戳的文件备份
    .PARAMETER FilePath
    要备份的文件路径
    .PARAMETER BackupReason
    备份原因（用于文件名）
    .RETURNS
    备份文件路径，如果备份失败则返回 $null
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$BackupReason = "edit"
    )

    if (-not (Test-Path $FilePath)) {
        Write-Host "文件不存在，无需备份: $FilePath" -ForegroundColor Gray
        return $null
    }

    try {
        # 确保备份目录存在
        Initialize-BackupDirectory

        # 生成备份文件名
        $fileInfo = Get-Item $FilePath
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFileName = "$($fileInfo.BaseName)_$($BackupReason)_$timestamp$($fileInfo.Extension)"
        $backupPath = Join-Path $script:BackupDirectory $backupFileName

        # 创建备份
        Copy-Item -Path $FilePath -Destination $backupPath -Force

        Write-Host "✓ 文件已备份: $backupPath" -ForegroundColor Green
        return $backupPath

    } catch {
        Write-Host "警告: 文件备份失败: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Get-ManagedBlockContent {
    <#
    .SYNOPSIS
    从文件中读取标记块内容
    .PARAMETER FilePath
    文件路径
    .PARAMETER StartMarker
    开始标记（可选，使用默认标记）
    .PARAMETER EndMarker
    结束标记（可选，使用默认标记）
    .RETURNS
    包含 Found, Content, StartLine, EndLine 的对象
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$StartMarker = $script:ManagedBlockStartMarker,

        [string]$EndMarker = $script:ManagedBlockEndMarker
    )

    $result = @{
        Found = $false
        Content = @()
        StartLine = -1
        EndLine = -1
        BeforeBlock = @()
        AfterBlock = @()
    }

    if (-not (Test-Path $FilePath)) {
        Write-Host "文件不存在: $FilePath" -ForegroundColor Gray
        return $result
    }

    try {
        $lines = Get-Content $FilePath -Encoding UTF8 -ErrorAction SilentlyContinue

        # 处理空文件或读取失败的情况
        if ($null -eq $lines) {
            $lines = @()
        } elseif ($lines -isnot [array]) {
            # 单行文件会返回字符串而不是数组
            $lines = @($lines)
        }

        $inBlock = $false
        $lineNumber = 0

        foreach ($line in $lines) {
            $lineNumber++

            if ($line.Trim() -eq $StartMarker.Trim()) {
                $result.StartLine = $lineNumber
                $inBlock = $true
                $result.Found = $true
                continue
            }

            if ($line.Trim() -eq $EndMarker.Trim() -and $inBlock) {
                $result.EndLine = $lineNumber
                $inBlock = $false
                continue
            }

            if ($inBlock) {
                $result.Content += $line
            } elseif ($result.StartLine -eq -1) {
                # 在标记块之前
                $result.BeforeBlock += $line
            } elseif ($result.EndLine -ne -1) {
                # 在标记块之后
                $result.AfterBlock += $line
            }
        }

        if ($result.Found) {
            Write-Host "✓ 找到标记块: 第 $($result.StartLine) - $($result.EndLine) 行" -ForegroundColor Green
        } else {
            Write-Host "未找到标记块" -ForegroundColor Gray
            # 如果没有找到标记块，所有内容都在 BeforeBlock 中
            $result.BeforeBlock = $lines
        }

        return $result

    } catch {
        Write-Host "读取文件失败: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Set-ManagedBlockInFile {
    <#
    .SYNOPSIS
    在文件中设置标记块内容
    .PARAMETER FilePath
    文件路径
    .PARAMETER Content
    要写入标记块的内容数组
    .PARAMETER StartMarker
    开始标记（可选，使用默认标记）
    .PARAMETER EndMarker
    结束标记（可选，使用默认标记）
    .PARAMETER CreateIfNotExists
    如果文件不存在是否创建
    .PARAMETER AppendIfNoBlock
    如果没有找到标记块是否追加到文件末尾
    .RETURNS
    操作成功返回 $true，失败返回 $false
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Content,

        [string]$StartMarker = $script:ManagedBlockStartMarker,

        [string]$EndMarker = $script:ManagedBlockEndMarker,

        [switch]$CreateIfNotExists,

        [switch]$AppendIfNoBlock
    )

    try {
        # 验证 Content 参数
        if ($null -eq $Content -or $Content.Count -eq 0) {
            Write-Host "内容为空，无法写入标记块" -ForegroundColor Yellow
            return $false
        }

        # 检查文件是否存在
        if (-not (Test-Path $FilePath)) {
            if ($CreateIfNotExists) {
                Write-Host "创建新文件: $FilePath" -ForegroundColor Cyan
                # 创建目录（如果不存在）
                $directory = Split-Path $FilePath -Parent
                if ($directory -and -not (Test-Path $directory)) {
                    New-Item -Path $directory -ItemType Directory -Force | Out-Null
                }
            } else {
                Write-Host "文件不存在: $FilePath" -ForegroundColor Red
                return $false
            }
        } else {
            # 备份现有文件
            $null = Backup-FileWithTimestamp -FilePath $FilePath -BackupReason "managed_block"
        }

        # 读取现有标记块
        $blockInfo = Get-ManagedBlockContent -FilePath $FilePath -StartMarker $StartMarker -EndMarker $EndMarker

        # 构建新的文件内容
        $newContent = [System.Collections.ArrayList]::new()

        # 添加标记块之前的内容
        if ($blockInfo.BeforeBlock -and $blockInfo.BeforeBlock.Count -gt 0) {
            foreach ($line in $blockInfo.BeforeBlock) {
                $null = $newContent.Add($line)
            }
        }

        # 如果没有找到标记块且需要追加
        if (-not $blockInfo.Found -and $AppendIfNoBlock) {
            # 如果文件不为空，添加空行分隔
            if ($newContent.Count -gt 0) {
                $null = $newContent.Add("")
            }
        }

        # 添加标记块
        $null = $newContent.Add($StartMarker)
        if ($Content -and $Content.Count -gt 0) {
            foreach ($line in $Content) {
                $null = $newContent.Add($line)
            }
        }
        $null = $newContent.Add($EndMarker)

        # 如果找到了标记块，添加标记块之后的内容
        if ($blockInfo.Found -and $blockInfo.AfterBlock -and $blockInfo.AfterBlock.Count -gt 0) {
            foreach ($line in $blockInfo.AfterBlock) {
                $null = $newContent.Add($line)
            }
        }

        # 转换为数组并原子写入文件
        $contentArray = $newContent.ToArray()
        $success = Write-FileAtomically -FilePath $FilePath -Content $contentArray

        if ($success) {
            Write-Host "✓ 标记块已更新: $FilePath" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ 标记块更新失败: $FilePath" -ForegroundColor Red
            return $false
        }

    } catch {
        Write-Host "设置标记块失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Write-FileAtomically {
    <#
    .SYNOPSIS
    原子写入文件（临时文件 + Move-Item）
    .PARAMETER FilePath
    目标文件路径
    .PARAMETER Content
    要写入的内容数组
    .PARAMETER Encoding
    文件编码
    .RETURNS
    操作成功返回 $true，失败返回 $false
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Content,

        [string]$Encoding = "UTF8"
    )

    $tempFile = $null

    try {
        # 验证 Content 参数（允许空数组，因为可能是空文件）
        if ($null -eq $Content) {
            Write-Host "内容为 null，使用空数组" -ForegroundColor Yellow
            $Content = @()
        }

        # 确保 Content 是数组类型
        if ($Content -isnot [array]) {
            $Content = @($Content)
        }

        # 确保目标目录存在
        $directory = Split-Path $FilePath -Parent
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }

        # 生成临时文件路径
        $tempFile = "$FilePath.tmp_$(Get-Random)"

        # 写入临时文件（处理空数组的情况）
        if ($Content.Count -eq 0) {
            # 创建空文件
            New-Item -Path $tempFile -ItemType File -Force | Out-Null
        } else {
            $Content | Out-File -FilePath $tempFile -Encoding $Encoding -Force
        }

        # 验证临时文件写入成功
        if (-not (Test-Path $tempFile)) {
            throw "临时文件写入失败"
        }

        # 原子移动（重命名）
        Move-Item -Path $tempFile -Destination $FilePath -Force

        # 验证最终文件存在
        if (-not (Test-Path $FilePath)) {
            throw "文件移动失败"
        }

        Write-Host "✓ 文件原子写入成功: $FilePath" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "原子写入失败: $($_.Exception.Message)" -ForegroundColor Red

        # 清理临时文件
        if ($tempFile -and (Test-Path $tempFile)) {
            try {
                Remove-Item $tempFile -Force
            } catch {
                Write-Host "警告: 无法清理临时文件: $tempFile" -ForegroundColor Yellow
            }
        }

        return $false
    }
}

function Remove-ManagedBlockFromFile {
    <#
    .SYNOPSIS
    从文件中移除标记块
    .PARAMETER FilePath
    文件路径
    .PARAMETER StartMarker
    开始标记（可选，使用默认标记）
    .PARAMETER EndMarker
    结束标记（可选，使用默认标记）
    .RETURNS
    操作成功返回 $true，失败返回 $false
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$StartMarker = $script:ManagedBlockStartMarker,

        [string]$EndMarker = $script:ManagedBlockEndMarker
    )

    if (-not (Test-Path $FilePath)) {
        Write-Host "文件不存在: $FilePath" -ForegroundColor Gray
        return $true  # 文件不存在，认为移除成功
    }

    try {
        # 备份文件
        $null = Backup-FileWithTimestamp -FilePath $FilePath -BackupReason "remove_block"

        # 读取标记块信息
        $blockInfo = Get-ManagedBlockContent -FilePath $FilePath -StartMarker $StartMarker -EndMarker $EndMarker

        if (-not $blockInfo.Found) {
            Write-Host "未找到标记块，无需移除" -ForegroundColor Gray
            return $true
        }

        # 构建新内容（移除标记块）
        $newContent = [System.Collections.ArrayList]::new()

        if ($blockInfo.BeforeBlock -and $blockInfo.BeforeBlock.Count -gt 0) {
            foreach ($line in $blockInfo.BeforeBlock) {
                $null = $newContent.Add($line)
            }
        }

        if ($blockInfo.AfterBlock -and $blockInfo.AfterBlock.Count -gt 0) {
            foreach ($line in $blockInfo.AfterBlock) {
                $null = $newContent.Add($line)
            }
        }

        # 转换为数组并原子写入
        $contentArray = $newContent.ToArray()
        $success = Write-FileAtomically -FilePath $FilePath -Content $contentArray

        if ($success) {
            Write-Host "✓ 标记块已移除: $FilePath" -ForegroundColor Green
            return $true
        } else {
            Write-Host "✗ 标记块移除失败: $FilePath" -ForegroundColor Red
            return $false
        }

    } catch {
        Write-Host "移除标记块失败: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Test-ManagedBlockExists {
    <#
    .SYNOPSIS
    检测文件中是否存在标记块
    .PARAMETER FilePath
    文件路径
    .PARAMETER StartMarker
    开始标记（可选，使用默认标记）
    .PARAMETER EndMarker
    结束标记（可选，使用默认标记）
    .RETURNS
    存在返回 $true，不存在返回 $false
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string]$StartMarker = $script:ManagedBlockStartMarker,

        [string]$EndMarker = $script:ManagedBlockEndMarker
    )

    if (-not (Test-Path $FilePath)) {
        return $false
    }

    try {
        $blockInfo = Get-ManagedBlockContent -FilePath $FilePath -StartMarker $StartMarker -EndMarker $EndMarker
        return $blockInfo.Found
    } catch {
        return $false
    }
}

function Get-BackupFiles {
    <#
    .SYNOPSIS
    获取备份文件列表
    .PARAMETER Pattern
    文件名模式（可选）
    .RETURNS
    备份文件信息数组
    #>
    param(
        [string]$Pattern = "*"
    )

    try {
        if (-not (Test-Path $script:BackupDirectory)) {
            Write-Host "备份目录不存在" -ForegroundColor Gray
            return @()
        }

        $backupFiles = Get-ChildItem -Path $script:BackupDirectory -Filter $Pattern | Sort-Object LastWriteTime -Descending

        $results = @()
        foreach ($file in $backupFiles) {
            $results += [PSCustomObject]@{
                Name = $file.Name
                FullPath = $file.FullName
                Size = $file.Length
                Created = $file.CreationTime
                Modified = $file.LastWriteTime
            }
        }

        return $results

    } catch {
        Write-Host "获取备份文件列表失败: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Clear-OldBackups {
    <#
    .SYNOPSIS
    清理旧的备份文件
    .PARAMETER DaysToKeep
    保留天数（默认 7 天）
    .PARAMETER MaxFiles
    最大文件数（默认 50 个）
    .RETURNS
    清理的文件数量
    #>
    param(
        [int]$DaysToKeep = 7,
        [int]$MaxFiles = 50
    )

    try {
        if (-not (Test-Path $script:BackupDirectory)) {
            return 0
        }

        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $allBackups = Get-ChildItem -Path $script:BackupDirectory | Sort-Object LastWriteTime -Descending

        $filesToDelete = @()

        # 按时间删除
        $filesToDelete += $allBackups | Where-Object { $_.LastWriteTime -lt $cutoffDate }

        # 按数量删除（保留最新的 MaxFiles 个）
        if ($allBackups.Count -gt $MaxFiles) {
            $filesToDelete += $allBackups | Select-Object -Skip $MaxFiles
        }

        # 去重
        $filesToDelete = $filesToDelete | Select-Object -Unique

        $deletedCount = 0
        foreach ($file in $filesToDelete) {
            try {
                Remove-Item $file.FullName -Force
                $deletedCount++
            } catch {
                Write-Host "警告: 无法删除备份文件: $($file.Name)" -ForegroundColor Yellow
            }
        }

        if ($deletedCount -gt 0) {
            Write-Host "✓ 已清理 $deletedCount 个旧备份文件" -ForegroundColor Green
        }

        return $deletedCount

    } catch {
        Write-Host "清理备份文件失败: $($_.Exception.Message)" -ForegroundColor Red
        return 0
    }
}

# 初始化备份目录
Initialize-BackupDirectory

# 注意：此脚本通过 dot-source 加载，不需要 Export-ModuleMember
# 所有函数在 dot-source 后自动可用