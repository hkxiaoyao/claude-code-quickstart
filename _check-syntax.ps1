$files = @(
    "installer/windows/steps/Ccline.ps1"
    "installer/windows/steps/CcgWorkflow.ps1"
    "installer/windows/core/Registry.ps1"
    "installer/windows/core/Bootstrap.ps1"
    "installer/windows/steps/Mcp.ps1"
    "installer/windows/core/McpManager.ps1"
    "installer/windows/core/Provider.ps1"
    "installer/windows/Manage-ClaudeEnv.ps1"
    "installer/windows/Install-ClaudeEnv.ps1"
    "installer/build.ps1"
)
$hasError = $false
foreach ($f in $files) {
    $fullPath = Join-Path $PSScriptRoot $f
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        $hasError = $true
        foreach ($e in $errors) {
            Write-Host "FAIL [$f] Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "PASS [$f]" -ForegroundColor Green
    }
}
if ($hasError) { exit 1 }
