param(
    [switch]$WhatIf
)

Write-Host "Validate existing Azure resources and apply non-secret bootstrap settings only."
Write-Host "This script is intentionally idempotent and does not write secrets."
