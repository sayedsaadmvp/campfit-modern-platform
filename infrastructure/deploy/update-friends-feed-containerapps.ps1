[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SubscriptionId = 'cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2',
    [string]$ResourceGroup = 'rg-campfit-prod',
    [string]$RuntimeIdentityName = 'id-campfit-prod',
    [string]$RuntimeIdentityClientId = 'edcebb18-581a-45fc-8e61-b37658bab128',
    [string]$StorageAccountName = 'stcampfitprodcb5afb7d',
    [string]$QueueName = 'campfit-feed-events',
    [string]$SnapshotContainerName = 'campfit-feed-snapshots'
)

# Use native exit codes because Windows PowerShell treats Azure CLI warnings on
# stderr as PowerShell errors even when Azure CLI exits successfully.
$ErrorActionPreference = 'Continue'

az account show --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not authenticated. Run az login first.'
}
az account set --subscription $SubscriptionId --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select subscription '$SubscriptionId'."
}

$runtimeIdentity = az identity show `
    --resource-group $ResourceGroup `
    --name $RuntimeIdentityName `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $null -eq $runtimeIdentity) {
    throw "Unable to read runtime identity '$RuntimeIdentityName'."
}
if ($runtimeIdentity.clientId -ne $RuntimeIdentityClientId) {
    throw "Runtime identity client ID does not match '$RuntimeIdentityName'."
}

az storage account show `
    --resource-group $ResourceGroup `
    --name $StorageAccountName `
    --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Storage account '$StorageAccountName' does not exist. Run provision-friends-feed-storage.ps1 first."
}

$serviceSettings = [ordered]@{
    'campfit-core-api' = @(
        "AZURE_STORAGE_ACCOUNT_NAME=$StorageAccountName",
        "CAMPFIT_FEED_QUEUE_NAME=$QueueName",
        "USER_ASSIGNED_IDENTITY_CLIENT_ID=$RuntimeIdentityClientId",
        "AZURE_CLIENT_ID=$RuntimeIdentityClientId"
    )
    'campfit-bff-mobile' = @(
        "AZURE_STORAGE_ACCOUNT_NAME=$StorageAccountName",
        "CAMPFIT_FEED_QUEUE_NAME=$QueueName",
        "CAMPFIT_FEED_SNAPSHOT_CONTAINER=$SnapshotContainerName",
        "USER_ASSIGNED_IDENTITY_CLIENT_ID=$RuntimeIdentityClientId",
        "AZURE_CLIENT_ID=$RuntimeIdentityClientId"
    )
    'campfit-analytics' = @(
        "AZURE_STORAGE_ACCOUNT_NAME=$StorageAccountName",
        "CAMPFIT_FEED_QUEUE_NAME=$QueueName",
        "CAMPFIT_FEED_SNAPSHOT_CONTAINER=$SnapshotContainerName",
        "USER_ASSIGNED_IDENTITY_CLIENT_ID=$RuntimeIdentityClientId",
        "AZURE_CLIENT_ID=$RuntimeIdentityClientId",
        'FEED_QUEUE_BATCH_SIZE=8',
        'FEED_QUEUE_VISIBILITY_TIMEOUT_SECONDS=120',
        'FEED_QUEUE_EMPTY_DELAY_SECONDS=2',
        'FEED_QUEUE_MAX_EMPTY_DELAY_SECONDS=30',
        'FEED_QUEUE_MAX_DEQUEUE_COUNT=5',
        'FEED_PLAYER_RANK_JUMP_THRESHOLD=3',
        'FEED_TEAM_RANK_JUMP_THRESHOLD=1'
    )
}

foreach ($entry in $serviceSettings.GetEnumerator()) {
    $appName = $entry.Key
    $settings = $entry.Value
    $app = az containerapp show `
        --resource-group $ResourceGroup `
        --name $appName `
        --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $null -eq $app) {
        throw "Container App '$appName' does not exist."
    }

    $attachedIdentityIds = @($app.identity.userAssignedIdentities.PSObject.Properties.Name)
    if ($runtimeIdentity.id -notin $attachedIdentityIds) {
        throw "Runtime identity '$RuntimeIdentityName' is not attached to '$appName'."
    }

    if ($PSCmdlet.ShouldProcess($appName, 'Update Friends Feed environment variables')) {
        $arguments = @(
            'containerapp', 'update',
            '--resource-group', $ResourceGroup,
            '--name', $appName,
            '--set-env-vars'
        ) + $settings + @('--only-show-errors', '--output', 'none')
        & az @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to update Container App '$appName'."
        }
    }
}

Write-Host "Adventure was not changed because it does not publish or consume Friends Feed data."
Write-Host ''
foreach ($appName in $serviceSettings.Keys) {
    az containerapp revision list `
        --resource-group $ResourceGroup `
        --name $appName `
        --query '[?properties.active].{Revision:name,Health:properties.healthState,Provisioning:properties.provisioningState,Running:properties.runningState}' `
        --output table
}
