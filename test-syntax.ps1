# PowerShell 语法检查脚本
# 作者: 哈雷酱 (本小姐的专业测试工具！)

param(
    [string]$Path = "installer"
)

Write-Host "🔍 开始检查 PowerShell 脚本语法..." -ForegroundColor Cyan

# 收集所有需要检查的文件
$scriptFiles = @()
$scriptFiles += Get-ChildItem "$Path/windows" -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue
$scriptFiles += Get-ChildItem "$Path/contracts" -Recurse -Filter "*.ps1" -ErrorAction SilentlyContinue
$buildScript = Get-Item "$Path/build.ps1" -ErrorAction SilentlyContinue
if ($buildScript) {
    $scriptFiles += $buildScript
}

$totalFiles = $scriptFiles.Count
$passedFiles = 0
$failedFiles = 0

Write-Host "找到 $totalFiles 个 PowerShell 脚本文件" -ForegroundColor Yellow

foreach ($file in $scriptFiles) {
    Write-Host "检查: $($file.Name)" -NoNewline

    try {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -gt 0) {
            $messages = @($parseErrors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" })
            throw ($messages -join "; ")
        }
        Write-Host " ✓" -ForegroundColor Green
        $passedFiles++
    }
    catch {
        Write-Host " ✗" -ForegroundColor Red
        Write-Host "  错误: $($_.Exception.Message)" -ForegroundColor Red
        $failedFiles++
    }
}

Write-Host "`n📊 语法检查结果:" -ForegroundColor Cyan
Write-Host "  总文件数: $totalFiles" -ForegroundColor White
Write-Host "  通过: $passedFiles" -ForegroundColor Green
Write-Host "  失败: $failedFiles" -ForegroundColor Red

if ($failedFiles -eq 0) {
    Write-Host "`n🎉 所有脚本语法检查通过！" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n❌ 发现语法错误，请修复后重试" -ForegroundColor Red
    exit 1
}