[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ParametersFile,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$resolvedParametersFile = (Resolve-Path $ParametersFile).Path
$parameters = Get-Content -Raw $resolvedParametersFile | ConvertFrom-Json
$azure = $parameters.Azure
$images = $parameters.Images

$arguments = @{
    SubscriptionId = $azure.SubscriptionId
    ResourceGroup = $azure.ResourceGroup
    Location = $azure.Location
    ContainerAppsEnvironment = $azure.ContainerAppsEnvironment
    ContainerRegistryName = $azure.ContainerRegistryName
    KeyVaultName = $azure.KeyVaultName
    UserAssignedIdentityName = $azure.UserAssignedIdentityName
    PostgresHost = $azure.PostgresHost
    CoreImage = $images.Core
    AdventureImage = $images.Adventure
    BffImage = $images.Bff
    AnalyticsImage = $images.Analytics
    BffAllowedCorsOrigin = $parameters.BffAllowedCorsOrigin
    WhatIf = $WhatIf
}

& (Join-Path $PSScriptRoot "configure-azure.ps1") @arguments
