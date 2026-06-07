$ErrorActionPreference = 'Stop'

$errors = [System.Management.Automation.PSParseError[]]@()
$null = [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content "F:/web/claude-code-quickstart/installer/windows/core/Process.ps1" -Raw),
    [ref]$errors
)

if ($errors.Count -gt 0) {
    Write-Host "SYNTAX ERRORS:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: Syntax OK" -ForegroundColor Green

Import-Module "F:/web/claude-code-quickstart/installer/windows/core/Process.ps1" -Force

$required = @(
    'Invoke-ExternalCommand',
    'Invoke-WingetInstall',
    'Invoke-NpmGlobalInstall',
    'Test-CommandAvailable',
    'Get-CommandVersion',
    'Refresh-SessionPath'
)

$exported = Get-Command -Module Process | Select-Object -ExpandProperty Name
$missing = $required | Where-Object { $_ -notin $exported }

if ($missing.Count -gt 0) {
    Write-Host "MISSING EXPORTS:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: All required functions exported" -ForegroundColor Green
$exported | ForEach-Object { Write-Host "  + $_" -ForegroundColor White }

$testResult = Test-CommandAvailable -Command "pwsh"
if ($testResult -ne $true) {
    Write-Host "FAIL: Test-CommandAvailable returned unexpected result" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Test-CommandAvailable works" -ForegroundColor Green

$ver = Get-CommandVersion -Command "pwsh"
if (-not $ver -or $ver -eq "未安装") {
    Write-Host "FAIL: Get-CommandVersion returned unexpected result: $ver" -ForegroundColor Red
    exit 1
}
Write-Host "PASS: Get-CommandVersion works, pwsh version: $ver" -ForegroundColor Green

Write-Host "`nAll validations passed!" -ForegroundColor Green
