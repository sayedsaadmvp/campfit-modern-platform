[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$Location,
    [Parameter(Mandatory)][string]$ContainerAppsEnvironment,
    [Parameter(Mandatory)][string]$ContainerRegistryName,
    [Parameter(Mandatory)][string]$KeyVaultName,
    [Parameter(Mandatory)][string]$UserAssignedIdentityName,
    [Parameter(Mandatory)][string]$PostgresHost,
    [Parameter(Mandatory)][string]$CoreImage,
    [Parameter(Mandatory)][string]$AdventureImage,
    [Parameter(Mandatory)][string]$BffImage,
    [Parameter(Mandatory)][string]$AnalyticsImage,
    [string]$BffAllowedCorsOrigin = "https://app.campfit.com",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $repoRoot "infrastructure/main.bicep"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI is required. Install it and run 'az login' first."
}

az account show --output none
if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI is not authenticated. Run 'az login' first."
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select Azure subscription '$SubscriptionId'."
}

$checks = @(
    @{ Label = "resource group"; Args = @("group", "show", "--name", $ResourceGroup) },
    @{ Label = "Container Apps environment"; Args = @("containerapp", "env", "show", "--name", $ContainerAppsEnvironment, "--resource-group", $ResourceGroup) },
    @{ Label = "container registry"; Args = @("acr", "show", "--name", $ContainerRegistryName, "--resource-group", $ResourceGroup) },
    @{ Label = "Key Vault"; Args = @("keyvault", "show", "--name", $KeyVaultName, "--resource-group", $ResourceGroup) },
    @{ Label = "managed identity"; Args = @("identity", "show", "--name", $UserAssignedIdentityName, "--resource-group", $ResourceGroup) }
)

foreach ($check in $checks) {
    Write-Host "Validating existing $($check.Label)..."
    & az @($check.Args) --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Required $($check.Label) was not found in resource group '$ResourceGroup'."
    }
}

$deploymentArguments = @(
    "deployment", "group",
    $(if ($WhatIf) { "what-if" } else { "create" }),
    "--name", "campfit-platform",
    "--resource-group", $ResourceGroup,
    "--template-file", $templatePath,
    "--parameters",
    "location=$Location",
    "containerAppsEnvironmentName=$ContainerAppsEnvironment",
    "containerRegistryName=$ContainerRegistryName",
    "keyVaultName=$KeyVaultName",
    "userAssignedIdentityName=$UserAssignedIdentityName",
    "postgresHost=$PostgresHost",
    "coreImage=$CoreImage",
    "adventureImage=$AdventureImage",
    "bffImage=$BffImage",
    "analyticsImage=$AnalyticsImage",
    "bffAllowedCorsOrigin=$BffAllowedCorsOrigin"
)

Write-Host $(if ($WhatIf) { "Previewing platform deployment..." } else { "Applying platform deployment..." })
& az @deploymentArguments
if ($LASTEXITCODE -ne 0) {
    throw "Azure platform deployment failed."
}

if (-not $WhatIf) {
    Write-Host "Platform deployment completed. Only Container Apps and required role assignments were changed."
}
