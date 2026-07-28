[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("Add", "Remove")][string]$Action,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ServerName,
    [string]$RuleName,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is required."
}

if ($Action -eq "Add") {
    $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
    if ($publicIp -notmatch '^(?:\d{1,3}\.){3}\d{1,3}$') {
        throw "Unable to resolve a valid public IPv4 address."
    }

    if ([string]::IsNullOrWhiteSpace($RuleName)) {
        $RuleName = "campfit-support-$($env:USERNAME)-$(Get-Date -Format 'yyyyMMddHHmmss')"
    }

    $command = "az postgres flexible-server firewall-rule create --resource-group `"$ResourceGroup`" --name `"$ServerName`" --rule-name `"$RuleName`" --start-ip-address `"$publicIp`" --end-ip-address `"$publicIp`""
    Write-Host $command
    if (-not $WhatIf) {
        az postgres flexible-server firewall-rule create `
            --resource-group $ResourceGroup `
            --name $ServerName `
            --rule-name $RuleName `
            --start-ip-address $publicIp `
            --end-ip-address $publicIp `
            --output table
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create PostgreSQL firewall rule."
        }
    }

    Write-Host "Remove immediately after support work:"
    Write-Host "az postgres flexible-server firewall-rule delete --resource-group `"$ResourceGroup`" --name `"$ServerName`" --rule-name `"$RuleName`" --yes"
    return
}

if ([string]::IsNullOrWhiteSpace($RuleName)) {
    throw "-RuleName is required when -Action Remove."
}

$removeCommand = "az postgres flexible-server firewall-rule delete --resource-group `"$ResourceGroup`" --name `"$ServerName`" --rule-name `"$RuleName`" --yes"
Write-Host $removeCommand
if (-not $WhatIf) {
    az postgres flexible-server firewall-rule delete `
        --resource-group $ResourceGroup `
        --name $ServerName `
        --rule-name $RuleName `
        --yes
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to remove PostgreSQL firewall rule."
    }
}
