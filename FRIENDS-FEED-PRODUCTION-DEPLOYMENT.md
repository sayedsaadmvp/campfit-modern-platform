# Friends Feed Production Deployment

This is the manual production procedure for the CampFit Friends Feed. Every Azure change is performed by a PowerShell script that can be rerun safely.

Core database migration `20261004032534_AddCompetitionLeaderboardState` has already been deployed and is not part of this procedure. Analytics SQL is applied directly with `psql`; the Python migration runner and `analytics.schema_migrations` are not used.

## Deployment Values

Load the non-secret values recovered from the existing production deployment session:

```powershell
Set-Location C:\ssaad\CampFit\Development\campfit-modern-platform
. .\infrastructure\deploy\campfit-production.variables.ps1
```

Important values:

| Variable | Value |
| --- | --- |
| `$subscriptionId` | `cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2` |
| `$resourceGroup` | `rg-campfit-prod` |
| `$location` | `eastus` |
| `$runtimeIdentityName` | `id-campfit-prod` |
| `$runtimeIdentityClientId` | `edcebb18-581a-45fc-8e61-b37658bab128` |
| `$runtimeIdentityPrincipalId` | `8f38c873-048b-4622-8967-3ac94aca0d7f` |
| `$postgresServerName` | `psql-campfit-prod` |
| `$postgresHost` | `psql-campfit-prod.postgres.database.azure.com` |
| `$analyticsDatabaseName` | `campfit_analytics` |
| `$storageAccountName` | `stcampfitprodcb5afb7d` |
| `$feedQueueName` | `campfit-feed-events` |
| `$feedSnapshotContainerName` | `campfit-feed-snapshots` |

`stcampfitprodcb5afb7d` is a new globally unique storage account name. If Azure reports that it is unavailable, change `$storageAccountName` in the variables file and pass the replacement to both deployment scripts.

The attached variable export contained database passwords and other secrets. Those values are deliberately not copied into this repository. Database passwords remain interactive or in Key Vault.

## Prerequisites

```powershell
az login
az account set --subscription $subscriptionId
az account show --query '{Name:name,Id:id,Tenant:tenantId}' --output table
psql --version
```

The operator needs Contributor on `rg-campfit-prod`, Owner or User Access Administrator for RBAC, PostgreSQL firewall access, and the PostgreSQL administrator password for `campfitpgadmin`.

## 1. Provision Storage and RBAC

```powershell
$storageArguments = @{
  SubscriptionId = $subscriptionId
  ResourceGroup = $resourceGroup
  Location = $location
  StorageAccountName = $storageAccountName
  QueueName = $feedQueueName
  SnapshotContainerName = $feedSnapshotContainerName
  CorePrincipalId = $runtimeIdentityPrincipalId
  BffPrincipalId = $runtimeIdentityPrincipalId
  AnalyticsPrincipalId = $runtimeIdentityPrincipalId
}
.\infrastructure\deploy\provision-friends-feed-storage.ps1 @storageArguments -WhatIf
.\infrastructure\deploy\provision-friends-feed-storage.ps1 @storageArguments
```

The script creates or reuses the secure storage account, queue, private blob container, and role assignments through Azure Resource Manager. It does not read or print a storage account key.

| Service | Resource | Role |
| --- | --- | --- |
| Core API | Feed queue | `Storage Queue Data Message Sender` |
| Mobile BFF | Feed queue | `Storage Queue Data Message Sender` |
| Mobile BFF | Snapshot container | `Storage Blob Data Contributor` |
| Analytics | Feed queue | `Storage Queue Data Message Processor` |
| Analytics | Snapshot container | `Storage Blob Data Reader` |

All three services currently use `id-campfit-prod`, so the shared identity receives the union of these permissions. The script accepts separate principal IDs if service-specific identities are introduced later.

## 2. Deploy Analytics SQL Manually

The deployment script applies ordinary SQL files with `psql`; it does not run Entity Framework, Alembic, or the Analytics Python migration runner.

The PostgreSQL login role `campfit_analytics_app` must already exist with the password stored in `ANALYTICS-POSTGRES-PASSWORD`. The preparation SQL stops without changing tables when that role is missing.

For a first deployment of the Analytics database:

```powershell
$analyticsDatabaseArguments = @{
  SubscriptionId = $subscriptionId
  ResourceGroup = $resourceGroup
  PostgresServerName = $postgresServerName
  PostgresHost = $postgresHost
  DatabaseName = $analyticsDatabaseName
  DatabaseAdminUser = $postgresAdminUser
}
.\services\campfit-analytics\scripts\Deploy-AnalyticsDatabaseManual.ps1 @analyticsDatabaseArguments
```

This applies, in order:

1. `schemas/manual/000_prepare_analytics_schema.sql`
2. `schemas/migrations/001_create_ai_recommendation.sql`
3. `schemas/migrations/002_change_ai_recommendation_competition_id_to_uuid.sql`
4. `schemas/migrations/004_create_ai_recommendation_general.sql`
5. `schemas/migrations/005_create_friends_feed.sql`
6. `schemas/verify_friends_feed.sql`

If the base Analytics tables were already applied and only Friends Feed is required:

```powershell
$analyticsDatabaseArguments.IncludeBaseAnalyticsTables = $false
.\services\campfit-analytics\scripts\Deploy-AnalyticsDatabaseManual.ps1 @analyticsDatabaseArguments
```

The script creates `campfit_analytics` through Azure CLI when it is missing, requests the PostgreSQL administrator password securely, forces TLS with `PGSSLMODE=require`, and tests authentication before applying any SQL. It stops on the first SQL error and restores the prior PostgreSQL environment variables. Pass `-CreateDatabaseIfMissing $false` if database creation must be prohibited. To use pgAdmin instead, execute the same files in the listed order against `campfit_analytics`. Do not apply them to `fitnesstrackerservice` or `campfit_adventure`.

If the authentication preflight reports `password authentication failed`, reset the Flexible Server administrator password and rerun the deployment:

```powershell
$newPostgresAdminPassword = Read-Host 'New PostgreSQL administrator password'
az postgres flexible-server update `
  --resource-group $resourceGroup `
  --name $postgresServerName `
  --admin-password $newPostgresAdminPassword `
  --output none
$newPostgresAdminPassword = $null
```

The password must be 8-128 characters and contain characters from at least three of these categories: uppercase letters, lowercase letters, numbers, and non-alphanumeric characters. Resetting the administrator password does not change the application role password stored in `ANALYTICS-POSTGRES-PASSWORD`.

No new Key Vault migration connection string is required. Runtime Analytics continues to use the existing `ANALYTICS-POSTGRES-*`, `ANALYTICS-CORE-DATABASE`, `ANALYTICS-ADVENTURE-DATABASE`, and `ANALYTICS-APPINSIGHTS-CONNECTION-STRING` secrets.

Confirm the runtime write database:

```powershell
az keyvault secret show `
  --vault-name $keyVaultName `
  --name ANALYTICS-POSTGRES-DATABASE `
  --query value `
  --output tsv
```

Expected value: `campfit_analytics`.

## 3. Update Container Apps

```powershell
$containerAppArguments = @{
  SubscriptionId = $subscriptionId
  ResourceGroup = $resourceGroup
  RuntimeIdentityName = $runtimeIdentityName
  RuntimeIdentityClientId = $runtimeIdentityClientId
  StorageAccountName = $storageAccountName
  QueueName = $feedQueueName
  SnapshotContainerName = $feedSnapshotContainerName
}
.\infrastructure\deploy\update-friends-feed-containerapps.ps1 @containerAppArguments -WhatIf
.\infrastructure\deploy\update-friends-feed-containerapps.ps1 @containerAppArguments
```

The script verifies that the shared runtime identity is attached and updates Core, BFF, and Analytics. Adventure is intentionally unchanged because it does not publish or consume Friends Feed data.

| Variable | Core | BFF | Analytics |
| --- | --- | --- | --- |
| `AZURE_STORAGE_ACCOUNT_NAME` | Yes | Yes | Yes |
| `CAMPFIT_FEED_QUEUE_NAME` | Yes | Yes | Yes |
| `CAMPFIT_FEED_SNAPSHOT_CONTAINER` | No | Yes | Yes |
| `USER_ASSIGNED_IDENTITY_CLIENT_ID` | Yes | Yes | Yes |
| `AZURE_CLIENT_ID` | Yes | Yes | Yes |
| `FEED_QUEUE_BATCH_SIZE=8` | No | No | Yes |
| `FEED_QUEUE_VISIBILITY_TIMEOUT_SECONDS=120` | No | No | Yes |
| `FEED_QUEUE_EMPTY_DELAY_SECONDS=2` | No | No | Yes |
| `FEED_QUEUE_MAX_EMPTY_DELAY_SECONDS=30` | No | No | Yes |
| `FEED_QUEUE_MAX_DEQUEUE_COUNT=5` | No | No | Yes |
| `FEED_PLAYER_RANK_JUMP_THRESHOLD=3` | No | No | Yes |
| `FEED_TEAM_RANK_JUMP_THRESHOLD=1` | No | No | Yes |

These are non-secret settings. Do not add storage keys, connection strings, or SAS tokens to Container Apps or Key Vault.

## 4. Deploy Service Images

After storage and Analytics SQL are ready, deploy through the existing GitHub Actions workflows in this order: Analytics, Core API, Mobile BFF, then Adventure only if it has independent changes. No new GitHub Actions secret or variable is required.

## 5. Verify

```powershell
az storage account show `
  --resource-group $resourceGroup `
  --name $storageAccountName `
  --query '{Name:name,Location:location,HttpsOnly:enableHttpsTrafficOnly,MinimumTls:minimumTlsVersion}' `
  --output table

$apps = @('campfit-core-api', 'campfit-bff-mobile', 'campfit-analytics')
foreach ($app in $apps) {
  az containerapp revision list `
    --resource-group $resourceGroup `
    --name $app `
    --query '[?properties.active].{Revision:name,Health:properties.healthState,Running:properties.runningState}' `
    --output table
}

az containerapp logs show `
  --resource-group $resourceGroup `
  --name campfit-analytics `
  --tail 100
```

Look for `Friends Feed queue consumer started`. Submit a workout or request a complete leaderboard and confirm `Friends Feed event processed`.

Verify the authenticated public endpoint:

```powershell
curl.exe `
  -H "Authorization: Bearer <firebase-id-token>" `
  "https://$bffFqdn/api/analytics/feed?limit=30"
```

## Repeat and Rollback

All three deployment scripts are idempotent and can be rerun. RBAC propagation may take several minutes. Application rollback means redeploying the previous image revision. Do not delete the queue during rollback. The SQL is additive and uses `IF NOT EXISTS`; database rollback requires a reviewed corrective script or Azure PostgreSQL restore.
