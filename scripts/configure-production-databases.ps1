[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ServerName,
    [string[]]$DatabaseNames = @("campfit_core", "campfit_adventure", "campfit_analytics")
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is required."
}

az postgres flexible-server show --resource-group $ResourceGroup --name $ServerName --output none
if ($LASTEXITCODE -ne 0) {
    throw "PostgreSQL Flexible Server '$ServerName' was not found."
}

foreach ($databaseName in $DatabaseNames) {
    az postgres flexible-server db show `
        --resource-group $ResourceGroup `
        --server-name $ServerName `
        --database-name $databaseName `
        --output none 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Database '$databaseName' already exists."
        continue
    }

    $description = "az postgres flexible-server db create --resource-group `"$ResourceGroup`" --server-name `"$ServerName`" --database-name `"$databaseName`""
    Write-Host $description
    if ($PSCmdlet.ShouldProcess("$ServerName/$databaseName", "Create missing database")) {
        az postgres flexible-server db create `
            --resource-group $ResourceGroup `
            --server-name $ServerName `
            --database-name $databaseName `
            --output table
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create database '$databaseName'."
        }
    }
}

Write-Host "No database was deleted or reset. Create least-privilege login roles separately with psql."
