# PowerShell 语法检查脚本
# 作者: 哈雷酱 (本小姐的专业测试工具！)

param(
    [string]$Path = "installer"
)

Write-Host "🔍 开始检查 PowerShell 脚本语法..." -ForegroundColor Cyan

$scriptFiles = Get-ChildItem $Path -Recurse -Filter "*.ps1"
$totalFiles = $scriptFiles.Count
$passedFiles = 0
$failedFiles = 0

Write-Host "找到 $totalFiles 个 PowerShell 脚本文件" -ForegroundColor Yellow

foreach ($file in $scriptFiles) {
    Write-Host "检查: $($file.Name)" -NoNewline

    try {
        # 使用 PSParser 检查语法
        $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName -Raw), [ref]$null)
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