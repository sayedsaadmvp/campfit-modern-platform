# Non-secret production values exported from the existing CampFit deployment session.
# Passwords, connection strings, API keys, and service-account data intentionally
# remain in Key Vault or are requested interactively by the deployment scripts.

$subscriptionId = 'cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2'
$tenantId = '11423709-e146-43dd-95da-cd5ddd7b359b'
$resourceGroup = 'rg-campfit-prod'
$location = 'eastus'

$acrName = 'acrcampfitprodcb5afb7d'
$acrLoginServer = 'acrcampfitprodcb5afb7d.azurecr.io'
$containerAppsEnvironment = 'cae-campfit-prod'
$keyVaultName = 'kv-campfit-prod-cb5afb'
$logAnalyticsName = 'log-campfit-prod'
$appInsightsName = 'appinsight-campfit-prod'

$runtimeIdentityName = 'id-campfit-prod'
$runtimeIdentityClientId = 'edcebb18-581a-45fc-8e61-b37658bab128'
$runtimeIdentityPrincipalId = '8f38c873-048b-4622-8967-3ac94aca0d7f'

$postgresServerName = 'psql-campfit-prod'
$postgresHost = 'psql-campfit-prod.postgres.database.azure.com'
$postgresAdminUser = 'campfitpgadmin'
$analyticsDatabaseName = 'campfit_analytics'
$analyticsRuntimeRole = 'campfit_analytics_app'

$githubDeploymentAppName = 'github-campfit-prod-deployer'
$githubDeploymentClientId = 'b0cae329-2ddc-4776-a3ab-6fa59f4ae312'
$bffFqdn = 'campfit-bff-mobile.whiteriver-e19ed6bb.eastus.azurecontainerapps.io'

$coreContainerAppName = 'campfit-core-api'
$bffContainerAppName = 'campfit-bff-mobile'
$analyticsContainerAppName = 'campfit-analytics'
$adventureContainerAppName = 'campfit-adventure'

# New Friends Feed resources. Storage account names must be globally unique.
$storageAccountName = 'stcampfitprodcb5afb7d'
$feedQueueName = 'campfit-feed-events'
$feedSnapshotContainerName = 'campfit-feed-snapshots'
