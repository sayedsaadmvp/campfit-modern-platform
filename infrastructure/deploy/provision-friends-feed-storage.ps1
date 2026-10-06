[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SubscriptionId = 'cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2',
    [string]$ResourceGroup = 'rg-campfit-prod',
    [string]$Location = 'eastus',
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccountName = 'stcampfitprodcb5afb7d',
    [string]$QueueName = 'campfit-feed-events',
    [string]$SnapshotContainerName = 'campfit-feed-snapshots',
    [string]$CorePrincipalId = '8f38c873-048b-4622-8967-3ac94aca0d7f',
    [string]$BffPrincipalId = '8f38c873-048b-4622-8967-3ac94aca0d7f',
    [string]$AnalyticsPrincipalId = '8f38c873-048b-4622-8967-3ac94aca0d7f'
)

# Windows PowerShell converts native stderr into ErrorRecord objects. Azure CLI's
# storage extension currently emits a non-fatal pkg_resources warning on stderr,
# so native failures are determined from LASTEXITCODE below instead.
$ErrorActionPreference = 'Continue'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required.'
}

az account show --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not authenticated. Run az login first.'
}

az account set --subscription $SubscriptionId --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select subscription '$SubscriptionId'."
}

az group show --name $ResourceGroup --output none
if ($LASTEXITCODE -ne 0) {
    throw "Resource group '$ResourceGroup' does not exist."
}

$storageExists = $true
az storage account show `
    --resource-group $ResourceGroup `
    --name $StorageAccountName `
    --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    $storageExists = $false
}

if (-not $storageExists) {
    if (-not $PSCmdlet.ShouldProcess(
        "$ResourceGroup/$StorageAccountName",
        'Create secure general-purpose v2 storage account')) {
        return
    }

    az storage account create `
        --resource-group $ResourceGroup `
        --name $StorageAccountName `
        --location $Location `
        --kind StorageV2 `
        --sku Standard_LRS `
        --https-only true `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false `
        --tags Environment=Production Application=CampFit Purpose=FriendsFeed `
        --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create storage account '$StorageAccountName'. The name may already be used globally."
    }
}
else {
    Write-Host "Storage account '$StorageAccountName' already exists."
}

$storageScope = az storage account show `
    --resource-group $ResourceGroup `
    --name $StorageAccountName `
    --query id `
    --output tsv 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($storageScope)) {
    throw "Unable to resolve storage account '$StorageAccountName'."
}

$queueScope = "$storageScope/queueServices/default/queues/$QueueName"
$containerScope = "$storageScope/blobServices/default/containers/$SnapshotContainerName"
$managementEndpoint = 'https://management.azure.com'

if ($PSCmdlet.ShouldProcess($queueScope, 'Create or update Friends Feed queue')) {
    az rest `
        --method put `
        --url "${managementEndpoint}${queueScope}?api-version=2023-05-01" `
        --body '{}' `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create queue '$QueueName'."
    }
}

if ($PSCmdlet.ShouldProcess($containerScope, 'Create or update private snapshot container')) {
    az rest `
        --method put `
        --url "${managementEndpoint}${containerScope}?api-version=2023-05-01" `
        --body '{}' `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create blob container '$SnapshotContainerName'."
    }
}

function Grant-RoleIfMissing {
    param(
        [Parameter(Mandatory)][string]$PrincipalId,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Scope,
        [Parameter(Mandatory)][string]$Service
    )

    $count = az role assignment list `
        --assignee $PrincipalId `
        --scope $Scope `
        --query "[?roleDefinitionName=='$Role'] | length(@)" `
        --output tsv
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect '$Role' for $Service."
    }
    if ([int]$count -gt 0) {
        Write-Host "$Service already has '$Role'."
        return
    }

    if ($PSCmdlet.ShouldProcess("$Service ($PrincipalId)", "Grant '$Role' on $Scope")) {
        az role assignment create `
            --assignee-object-id $PrincipalId `
            --assignee-principal-type ServicePrincipal `
            --role $Role `
            --scope $Scope `
            --output none
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to grant '$Role' to $Service."
        }
    }
}

Grant-RoleIfMissing -PrincipalId $CorePrincipalId -Role 'Storage Queue Data Message Sender' -Scope $queueScope -Service 'Core API'
Grant-RoleIfMissing -PrincipalId $BffPrincipalId -Role 'Storage Queue Data Message Sender' -Scope $queueScope -Service 'Mobile BFF'
Grant-RoleIfMissing -PrincipalId $BffPrincipalId -Role 'Storage Blob Data Contributor' -Scope $containerScope -Service 'Mobile BFF'
Grant-RoleIfMissing -PrincipalId $AnalyticsPrincipalId -Role 'Storage Queue Data Message Processor' -Scope $queueScope -Service 'Analytics'
Grant-RoleIfMissing -PrincipalId $AnalyticsPrincipalId -Role 'Storage Blob Data Reader' -Scope $containerScope -Service 'Analytics'

Write-Host ''
Write-Host $(if ($WhatIfPreference) { 'Friends Feed storage provisioning preview completed.' } else { 'Friends Feed storage provisioning completed.' })
Write-Host "AZURE_STORAGE_ACCOUNT_NAME=$StorageAccountName"
Write-Host "CAMPFIT_FEED_QUEUE_NAME=$QueueName"
Write-Host "CAMPFIT_FEED_SNAPSHOT_CONTAINER=$SnapshotContainerName"
Write-Host 'RBAC changes can take several minutes to propagate.'
