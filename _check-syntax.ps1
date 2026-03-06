$files = @(
    "installer/steps/Ccline.ps1"
    "installer/steps/CcgWorkflow.ps1"
    "installer/core/Registry.ps1"
    "installer/core/Bootstrap.ps1"
    "installer/steps/Mcp.ps1"
    "installer/core/McpManager.ps1"
    "installer/core/Provider.ps1"
    "installer/Manage-ClaudeEnv.ps1"
    "installer/Install-ClaudeEnv.ps1"
    "installer/build/Build-SingleFile.ps1"
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
