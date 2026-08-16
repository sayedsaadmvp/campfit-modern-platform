# CampFit Azure Production Deployment

This is the authoritative first-production-deployment runbook for:

```text
Subscription: Visual Studio Enterprise Subscription
Subscription ID: cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2
Resource group: rg-campfit-prod
Default region: eastus
GitHub owner: sayedsaadmvp
```

Review every command before running it. Commands are written for PowerShell 7 and Azure CLI. Change `$location` before creating resources if `eastus` is not the intended production region.

## What Gets Deployed

Aspire is the local orchestrator and is not deployed as a production service. Azure runs four independent Container Apps:

| Container App | Image | Ingress | Database |
| --- | --- | --- | --- |
| `campfit-bff-mobile` | `campfit-bff-mobile` | External | None |
| `campfit-core-api` | `campfit-core-api` | Internal by default | `campfit_core` |
| `campfit-adventure` | `campfit-adventure` | Internal | `campfit_adventure` |
| `campfit-analytics` | `campfit-analytics` | Internal | Read-only access to `campfit_core` |

Analytics views select from Core's `public` tables. Do not create a separate empty `campfit_analytics` database for this deployment.

The deployment uses:

- One Azure Container Registry
- One Azure Container Apps environment
- One runtime user-assigned managed identity
- One RBAC-enabled Key Vault
- One Log Analytics workspace
- One workspace-based Application Insights resource
- One PostgreSQL Flexible Server with `campfit_core` and `campfit_adventure`

## Deployment Phases

Run the phases in this order:

1. Validate tools and Azure access.
2. Create shared Azure resources.
3. Create databases, roles, schemas, and migrations.
4. Add Key Vault secrets.
5. Build and push initial images.
6. Deploy the four Container Apps using Bicep.
7. Configure GitHub OIDC and variables.
8. Merge each service and deploy through GitHub Actions.

## 1. Prerequisites

Install and authenticate:

```powershell
az version
gh --version
git --version
docker version
psql --version

az login
az account set --subscription 'cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2'
az account show --query '{Name:name,Id:id,Tenant:tenantId}' --output table
```

The output must show `Visual Studio Enterprise Subscription` and the expected subscription ID.

Install or update required Azure CLI extensions:

```powershell
az extension add --name containerapp --upgrade --yes
az extension add --name application-insights --upgrade --yes
```

Register resource providers. Registration may take several minutes:

```powershell
$providers = @(
  'Microsoft.App',
  'Microsoft.ContainerRegistry',
  'Microsoft.DBforPostgreSQL',
  'Microsoft.Insights',
  'Microsoft.KeyVault',
  'Microsoft.ManagedIdentity',
  'Microsoft.OperationalInsights'
)

$providers | ForEach-Object { az provider register --namespace $_ }
$providers | ForEach-Object {
  az provider show --namespace $_ --query '{Provider:namespace,State:registrationState}' --output table
}
```

Required setup permissions:

- `Contributor` on the subscription or new resource group
- `Owner` or `User Access Administrator` to create role assignments
- GitHub `Admin` access on all four service repositories

Clone all repositories and start from the platform root:

```powershell
git clone --recurse-submodules https://github.com/sayedsaadmvp/campfit-modern-platform.git
Set-Location campfit-modern-platform
git submodule update --init --recursive
```

## 2. Set Deployment Names

The globally unique resource names below use a suffix derived from the subscription ID. If Azure reports that an ACR, Key Vault, or PostgreSQL name is unavailable, change only that name and use the replacement consistently throughout this document.

```powershell
$subscriptionId = 'cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2'
$resourceGroup = 'rg-campfit-prod'
$location = 'eastus'

$acrName = 'acrcampfitprodcb5afb7d'
$acrLoginServer = "$acrName.azurecr.io"
$containerAppsEnvironment = 'cae-campfit-prod'
$runtimeIdentityName = 'id-campfit-prod'
$keyVaultName = 'kv-campfit-prod-cb5afb'
$logAnalyticsName = 'log-campfit-prod'
$appInsightsName = 'appinsight-campfit-prod'
$postgresServerName = 'psql-campfit-prod-cb5afb'
$postgresHost = "$postgresServerName.postgres.database.azure.com"
$postgresAdminUser = 'campfitpgadmin'
```

## 3. Create Shared Azure Resources

### Resource Group

```powershell
az group create `
  --name $resourceGroup `
  --location $location `
  --tags Environment=Production Application=CampFit ManagedBy=CampFitPlatform
```

### Log Analytics and Application Insights

```powershell
az monitor log-analytics workspace create `
  --resource-group $resourceGroup `
  --workspace-name $logAnalyticsName `
  --location $location `
  --retention-time 30

$workspaceResourceId = az monitor log-analytics workspace show `
  --resource-group $resourceGroup `
  --workspace-name $logAnalyticsName `
  --query id --output tsv

az monitor app-insights component create `
  --app $appInsightsName `
  --resource-group $resourceGroup `
  --location $location `
  --kind web `
  --application-type web `
  --workspace $workspaceResourceId

$appInsightsConnectionString = az monitor app-insights component show `
  --app $appInsightsName `
  --resource-group $resourceGroup `
  --query connectionString --output tsv
```

### Application insights 
Call this script to create the app insights
```
C:\ssaad\CampFit\Development\campfit-modern-platform\infrastructure\deploy\add-app-insights.ps1
```

Keep `$appInsightsConnectionString` in memory only. Do not write it into a repository file.

### Azure Container Registry

The current Bicep uses `AcrPull`, so create the registry in classic RBAC mode rather than ABAC repository mode:

```powershell
az acr create `
  --name $acrName `
  --resource-group $resourceGroup `
  --location $location `
  --sku Standard `
  --admin-enabled false `
  --role-assignment-mode rbac

$acrResourceId = az acr show `
  --name $acrName `
  --resource-group $resourceGroup `
  --query id --output tsv

$signedInUserObjectId = az ad signed-in-user show --query id --output tsv

az role assignment create `
  --assignee-object-id $signedInUserObjectId `
  --assignee-principal-type User `
  --role AcrPush `
  --scope $acrResourceId
```

### Runtime Managed Identity

```powershell
$runtimeIdentityResourceId = az identity create `
  --name $runtimeIdentityName `
  --resource-group $resourceGroup `
  --location $location `
  --query id --output tsv

$runtimeIdentityClientId = az identity show `
  --name $runtimeIdentityName `
  --resource-group $resourceGroup `
  --query clientId --output tsv

$runtimeIdentityPrincipalId = az identity show `
  --name $runtimeIdentityName `
  --resource-group $resourceGroup `
  --query principalId --output tsv
```

### Key Vault

```powershell
az keyvault create `
  --name $keyVaultName `
  --resource-group $resourceGroup `
  --location $location `
  --enable-rbac-authorization true `
  --enable-purge-protection true

$keyVaultResourceId = az keyvault show `
  --name $keyVaultName `
  --resource-group $resourceGroup `
  --query id --output tsv

az role assignment create `
  --assignee-object-id $signedInUserObjectId `
  --assignee-principal-type User `
  --role 'Key Vault Secrets Officer' `
  --scope $keyVaultResourceId
```

RBAC assignments can take several minutes to become effective. If the first secret write returns `Forbidden`, wait and retry rather than changing the vault to legacy access policies.

### Container Apps Environment

```powershell
$workspaceCustomerId = az monitor log-analytics workspace show `
  --resource-group $resourceGroup `
  --workspace-name $logAnalyticsName `
  --query customerId --output tsv

$workspaceSharedKey = az monitor log-analytics workspace get-shared-keys `
  --resource-group $resourceGroup `
  --workspace-name $logAnalyticsName `
  --query primarySharedKey --output tsv

az containerapp env create `
  --name $containerAppsEnvironment `
  --resource-group $resourceGroup `
  --location $location `
  --environment-mode ConsumptionOnly `
  --logs-destination log-analytics `
  --logs-workspace-id $workspaceCustomerId `
  --logs-workspace-key $workspaceSharedKey

Remove-Variable workspaceSharedKey
```

## 4. Create PostgreSQL

This runbook uses public PostgreSQL networking because it is compatible with the current Container Apps environment and manual migrations from your local machine. The `0.0.0.0` rule allows Azure-hosted services, not the entire public internet. For stronger isolation, plan a later VNet-integrated Container Apps environment and private PostgreSQL deployment.

Create a strong administrator password and retain it only for initial administration:

```powershell
$postgresAdminPassword = Read-Host 'New PostgreSQL administrator password'

az postgres flexible-server create `
  --name $postgresServerName `
  --resource-group $resourceGroup `
  --location $location `
  --admin-user $postgresAdminUser `
  --admin-password $postgresAdminPassword `
  --version 16 `
  --tier GeneralPurpose `
  --sku-name Standard_D2s_v3 `
  --storage-size 128 `
  --storage-auto-grow Enabled `
  --public-access None

az postgres flexible-server firewall-rule create `
  --resource-group $resourceGroup `
  --name $postgresServerName `
  --rule-name AllowAzureServices `
  --start-ip-address 0.0.0.0 `
  --end-ip-address 0.0.0.0
```

Temporarily allow only your current public IPv4 for database setup:

```powershell
.\scripts\postgres-firewall.ps1 `
  -Action Add `
  -ResourceGroup $resourceGroup `
  -ServerName $postgresServerName `
  -RuleName campfit-initial-deployment
```

Create only the two databases:

```powershell
.\scripts\configure-production-databases.ps1 `
  -ResourceGroup $resourceGroup `
  -ServerName $postgresServerName `
  -DatabaseNames @('campfit_core', 'campfit_adventure') `
  -WhatIf

.\scripts\configure-production-databases.ps1 `
  -ResourceGroup $resourceGroup `
  -ServerName $postgresServerName `
  -DatabaseNames @('campfit_core', 'campfit_adventure') `
  -Confirm
```

### Database Roles

Generate three different strong passwords:

```powershell
$coreDatabasePassword = Read-Host 'New campfit_core application password'
$adventureDatabasePassword = Read-Host 'New campfit_adventure application password'
$analyticsDatabasePassword = Read-Host 'New analytics read-only password'
$env:PGPASSWORD = $postgresAdminPassword
```

Use `psql` or pgAdmin Query Tool as `$postgresAdminUser`. Replace the three password placeholders below before executing and do not save the populated SQL in the repository:

```sql
CREATE ROLE campfit_core_app LOGIN PASSWORD '<CORE_PASSWORD>';
CREATE ROLE campfit_adventure_app LOGIN PASSWORD '<ADVENTURE_PASSWORD>';
CREATE ROLE campfit_analytics_read LOGIN PASSWORD '<ANALYTICS_PASSWORD>';

GRANT CONNECT ON DATABASE fitnesstrackerservice TO campfit_analytics_read;
ALTER DATABASE fitnesstrackerservice OWNER TO campfit_core_app;
ALTER DATABASE campfit_adventure OWNER TO campfit_adventure_app;


GRANT CONNECT ON DATABASE fitnesstrackerservice TO campfit_core_app;
GRANT USAGE ON SCHEMA public TO campfit_core_app;

GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLE "__EFMigrationsHistory"
TO campfit_core_app;

GRANT USAGE ON SCHEMA public TO campfit_core_app;

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO campfit_core_app;

GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA public
TO campfit_core_app;

--## Grant Access to future tables 
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLES TO campfit_core_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT
ON SEQUENCES TO campfit_core_app;
```

### Grant Analytics Role Access
```
-- Create the login role
CREATE ROLE campfit_analytics_read
LOGIN
PASSWORD '<ANALYTICS_PASSWORD>';

-- Allow connecting to the database
GRANT CONNECT ON DATABASE campfit_core TO campfit_analytics_read;

-- Allow using the public schema
GRANT USAGE ON SCHEMA public TO campfit_analytics_read;

-- Read access to all existing tables and views
GRANT SELECT ON ALL TABLES IN SCHEMA public
TO campfit_analytics_read;

-- Automatically grant SELECT on future tables and views
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES
TO campfit_analytics_read;

-- Allow executing all existing functions/procedures
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public
TO campfit_analytics_read;

-- Automatically grant EXECUTE on future functions/procedures
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE ON FUNCTIONS
TO campfit_analytics_read;
```

Apply Core and Adventure EF migrations before deploying the APIs:

```powershell
Set-Location services\campfit-core-api
dotnet tool restore
$env:CAMPFIT_PROD_CONNECTION_STRING = "Host=$postgresHost;Port=5432;Database=campfit_core;Username=campfit_core_app;Password=$coreDatabasePassword;SSL Mode=Require"
.\scripts\Update-Database.ps1 -Context FitnessTrackingContext
Remove-Item Env:CAMPFIT_PROD_CONNECTION_STRING

Set-Location ..\campfit-adventure
dotnet tool restore
$env:CAMPFIT_PROD_CONNECTION_STRING = "Host=$postgresHost;Port=5432;Database=campfit_adventure;Username=campfit_adventure_app;Password=$adventureDatabasePassword;SSL Mode=Require"
.\scripts\Update-Database.ps1
Remove-Item Env:CAMPFIT_PROD_CONNECTION_STRING

Set-Location ..\..
```

Create Analytics views in `campfit_core` after Core migrations:

```powershell
$env:PGPASSWORD = $coreDatabasePassword
psql "host=$postgresHost port=5432 dbname=campfit_core user=campfit_core_app sslmode=require" `
  -v ON_ERROR_STOP=1 `
  -c 'CREATE SCHEMA IF NOT EXISTS analytics AUTHORIZATION campfit_core_app;'
psql "host=$postgresHost port=5432 dbname=campfit_core user=campfit_core_app sslmode=require" `
  -v ON_ERROR_STOP=1 `
  -f services\campfit-analytics\scripts\sql-views\generated_views.sql
```

Grant Analytics read-only access after the views exist:

```powershell
$env:PGPASSWORD = $coreDatabasePassword
psql "host=$postgresHost port=5432 dbname=campfit_core user=campfit_core_app sslmode=require" -v ON_ERROR_STOP=1 -c 'GRANT USAGE ON SCHEMA analytics TO campfit_analytics_read;'
psql "host=$postgresHost port=5432 dbname=campfit_core user=campfit_core_app sslmode=require" -v ON_ERROR_STOP=1 -c 'GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO campfit_analytics_read;'
psql "host=$postgresHost port=5432 dbname=campfit_core user=campfit_core_app sslmode=require" -v ON_ERROR_STOP=1 -c 'ALTER DEFAULT PRIVILEGES IN SCHEMA analytics GRANT SELECT ON TABLES TO campfit_analytics_read;'
Remove-Item Env:PGPASSWORD
```

## 5. Add Key Vault Secrets

Applications read Key Vault directly through the runtime identity. The Container Apps receive only the vault URI/name and managed-identity client ID. Adding or rotating a secret does not require adding a corresponding Container App environment variable.

### Shared Firebase Secrets

Export a Firebase Admin service-account JSON file from the CampFit Firebase project and keep it outside the repository:

```powershell
az keyvault secret set `
  --vault-name $keyVaultName `
  --name FIREBASE-PROJECT-ID `
  --value '<firebase-project-id>'

az keyvault secret set `
  --vault-name $keyVaultName `
  --name FIREBASE-SERVICE-ACCOUNT-JSON `
  --file 'C:\secure\firebase-service-account.json'
```

### Core Secrets

```powershell
az keyvault secret set --vault-name $keyVaultName --name CORE-POSTGRES-HOST --value $postgresHost
az keyvault secret set --vault-name $keyVaultName --name CORE-POSTGRES-PORT --value '5432'
az keyvault secret set --vault-name $keyVaultName --name CORE-POSTGRES-DATABASE --value 'campfit_core'
az keyvault secret set --vault-name $keyVaultName --name CORE-POSTGRES-USERNAME --value 'campfit_core_app'
az keyvault secret set --vault-name $keyVaultName --name CORE-POSTGRES-PASSWORD --value $coreDatabasePassword
az keyvault secret set --vault-name $keyVaultName --name CORE-APPINSIGHTS-CONNECTION-STRING --value $appInsightsConnectionString
```

Add these only for integrations enabled in production:

```text
FITBIT-CLIENT-ID
FITBIT-CLIENT-SECRET
FITBIT-AUTH-CODE-REDIRECT-URL
FITBIT-REDIRECT-URL
FITBIT-AUTHORIZATION-URI
FITBIT-ACCESS-REFRESH-TOKEN-REQUEST-URI
GARMIN-CLIENT-ID
GARMIN-CLIENT-SECRET
GARMIN-AUTH-CODE-REDIRECT-URL
STRIPE-SECRET-KEY
STRIPE-WEBHOOK-SECRET
```

Use `Read-Host` for secret values, for example:

```powershell
az keyvault secret set `
  --vault-name $keyVaultName `
  --name STRIPE-SECRET-KEY `
  --value (Read-Host 'Stripe production secret key')
```

### Adventure Secrets

```powershell
az keyvault secret set --vault-name $keyVaultName --name ADVENTURE-POSTGRES-HOST --value $postgresHost
az keyvault secret set --vault-name $keyVaultName --name ADVENTURE-POSTGRES-PORT --value '5432'
az keyvault secret set --vault-name $keyVaultName --name ADVENTURE-POSTGRES-DATABASE --value 'campfit_adventure'
az keyvault secret set --vault-name $keyVaultName --name ADVENTURE-POSTGRES-USERNAME --value 'campfit_adventure_app'
az keyvault secret set --vault-name $keyVaultName --name ADVENTURE-POSTGRES-PASSWORD --value $adventureDatabasePassword
az keyvault secret set --vault-name $keyVaultName --name ADVENTURE-APPINSIGHTS-CONNECTION-STRING --value $appInsightsConnectionString
```

### BFF Secrets

```powershell
az keyvault secret set --vault-name $keyVaultName --name BFF-APPINSIGHTS-CONNECTION-STRING --value $appInsightsConnectionString
```

The BFF uses the shared Firebase secrets already added above and has no database secret.

### Analytics Secrets

Analytics connects read-only to `campfit_core`:

```powershell
az keyvault secret set --vault-name $keyVaultName --name ANALYTICS-POSTGRES-HOST --value $postgresHost
az keyvault secret set --vault-name $keyVaultName --name ANALYTICS-POSTGRES-PORT --value '5432'
az keyvault secret set --vault-name $keyVaultName --name ANALYTICS-POSTGRES-DATABASE --value 'campfit_core'
az keyvault secret set --vault-name $keyVaultName --name ANALYTICS-POSTGRES-USERNAME --value 'campfit_analytics_read'
az keyvault secret set --vault-name $keyVaultName --name ANALYTICS-POSTGRES-PASSWORD --value $analyticsDatabasePassword
az keyvault secret set --vault-name $keyVaultName --name ANALYTICS-APPINSIGHTS-CONNECTION-STRING --value $appInsightsConnectionString
```

Remove password variables after Key Vault and database setup:

```powershell
Remove-Variable postgresAdminPassword, coreDatabasePassword, adventureDatabasePassword, analyticsDatabasePassword, appInsightsConnectionString
```

## 6. Build Initial Images

The Container Apps workflow can update only existing apps, while Bicep needs valid initial images. Build the first images directly in ACR:

```powershell
$coreSha = (git -C services\campfit-core-api rev-parse HEAD).Trim()
$adventureSha = (git -C services\campfit-adventure rev-parse HEAD).Trim()
$bffSha = (git -C services\campfit-bff-mobile rev-parse HEAD).Trim()
$analyticsSha = (git -C services\campfit-analytics rev-parse HEAD).Trim()

az acr build --registry $acrName --image "campfit-core-api:$coreSha" services\campfit-core-api
az acr build --registry $acrName --image "campfit-adventure:$adventureSha" services\campfit-adventure
az acr build --registry $acrName --image "campfit-bff-mobile:$bffSha" services\campfit-bff-mobile
az acr build --registry $acrName --image "campfit-analytics:$analyticsSha" services\campfit-analytics
```

Verify:

```powershell
az acr repository list --name $acrName --output table
```

## 7. Deploy the Container Apps

Create the ignored local parameter file:

```powershell
Copy-Item infrastructure\azure.parameters.example.json infrastructure\azure.parameters.local.json
```

Required Variables to fill the template 
```

write-host $subscriptionId 
write-host $resourceGroup 
write-host $location
write-host $acrName 
write-host $acrLoginServer 
write-host $containerAppsEnvironment 
write-host $runtimeIdentityName 
write-host $keyVaultName 
write-host $logAnalyticsName
write-host $appInsightsName 
write-host $postgresServerName 
write-host $postgresHost 
write-host $postgresAdminUser 

```

Populate it with the following structure and the SHA variables from the previous phase:

```json
{
  "Azure": {
    "SubscriptionId": "cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2",
    "ResourceGroup": "rg-campfit-prod",
    "Location": "eastus",
    "ContainerAppsEnvironment": "cae-campfit-prod",
    "ContainerRegistryName": "acrcampfitprodcb5afb7d",
    "ContainerRegistryLoginServer": "acrcampfitprodcb5afb7d.azurecr.io",
    "KeyVaultName": "kv-campfit-prod-cb5afb",
    "KeyVaultUri": "https://kv-campfit-prod-cb5afb.vault.azure.net/",
    "UserAssignedIdentityName": "id-campfit-prod",
    "UserAssignedIdentityClientId": "<runtime-identity-client-id>",
    "UserAssignedIdentityResourceId": "<runtime-identity-resource-id>",
    "PostgresHost": "psql-campfit-prod-cb5afb.postgres.database.azure.com",
    "PostgresPort": 5432
  },
  "Images": {
    "Core": "acrcampfitprodcb5afb7d.azurecr.io/campfit-core-api:<core-sha>",
    "Adventure": "acrcampfitprodcb5afb7d.azurecr.io/campfit-adventure:<adventure-sha>",
    "Bff": "acrcampfitprodcb5afb7d.azurecr.io/campfit-bff-mobile:<bff-sha>",
    "Analytics": "acrcampfitprodcb5afb7d.azurecr.io/campfit-analytics:<analytics-sha>"
  },
  "BffAllowedCorsOrigin": "https://app.campfit.com"
}
```

Use the actual web client origin. Do not use `*` for production browser CORS.

Preview and apply:

```powershell
.\scripts\deploy-platform.ps1 `
  -ParametersFile infrastructure\azure.parameters.local.json `
  -WhatIf

.\scripts\deploy-platform.ps1 `
  -ParametersFile infrastructure\azure.parameters.local.json
```

The Bicep deployment assigns the runtime identity `AcrPull` and `Key Vault Secrets User`, attaches it to all apps, configures probes, and exposes only the BFF.

The apps explicitly depend on the two runtime role assignments. Azure RBAC can still take several minutes to propagate; if a first revision reports Key Vault or ACR authorization failure, wait five minutes and create a new revision instead of adding credentials to the Container App.

### External Callback Decision

Fitbit, Garmin, and Stripe cannot call an internal-only Core API. Before registering production callback URLs, choose one of these paths:

1. Recommended long-term: expose only callback routes through API Management or another controlled public gateway.
2. Simpler initial path: deliberately change Core ingress to external in `infrastructure/main.bicep`, retain Firebase protection for business routes, and keep only the documented callback routes anonymous.
3. Keep Core internal and leave those integrations disabled.

Do not make a one-off portal ingress change; the next Bicep deployment would revert it.

### Verify Initial Deployment

```powershell
$bffFqdn = az containerapp show `
  --resource-group $resourceGroup `
  --name campfit-bff-mobile `
  --query properties.configuration.ingress.fqdn `
  --output tsv

Invoke-RestMethod "https://$bffFqdn/alive"
Invoke-RestMethod "https://$bffFqdn/health"
Invoke-RestMethod "https://$bffFqdn/version"

az containerapp list --resource-group $resourceGroup --output table
az containerapp revision list --resource-group $resourceGroup --name campfit-bff-mobile --output table
```

Check startup logs and Application Insights:

```powershell
az containerapp logs show --resource-group $resourceGroup --name campfit-core-api --tail 100
az containerapp logs show --resource-group $resourceGroup --name campfit-adventure --tail 100
az containerapp logs show --resource-group $resourceGroup --name campfit-analytics --tail 100
az containerapp logs show --resource-group $resourceGroup --name campfit-bff-mobile --tail 100
```

Core, Adventure, and Analytics require encrypted PostgreSQL connections in Azure. Bicep configures their production SSL modes explicitly. If these apps were created before that setting was deployed, apply it once to all PostgreSQL-backed Container Apps:

```powershell
az login
.\infrastructure\deploy\configure-postgres-ssl.ps1
```

The script creates a new revision for each database-backed service and prints its health. The BFF is excluded because it has no PostgreSQL connection.

Remove temporary local PostgreSQL access after migrations and views are complete:

```powershell
.\scripts\postgres-firewall.ps1 `
  -Action Remove `
  -ResourceGroup $resourceGroup `
  -ServerName $postgresServerName `
  -RuleName campfit-initial-deployment
```

## 8. Create the GitHub Deployment Identity

Use one Microsoft Entra application for the four service workflows. It has no client secret; GitHub authenticates using OIDC.

```powershell
$githubDeploymentAppName = 'github-campfit-prod-deployer'
$githubDeploymentClientId = az ad app create `
  --display-name $githubDeploymentAppName `
  --query appId --output tsv

$githubDeploymentPrincipalId = az ad sp create `
  --id $githubDeploymentClientId `
  --query id --output tsv

$tenantId = az account show --query tenantId --output tsv
$resourceGroupId = az group show --name $resourceGroup --query id --output tsv
$acrResourceId = az acr show --name $acrName --resource-group $resourceGroup --query id --output tsv

az role assignment create `
  --assignee-object-id $githubDeploymentPrincipalId `
  --assignee-principal-type ServicePrincipal `
  --role 'Container Apps Contributor' `
  --scope $resourceGroupId

az role assignment create `
  --assignee-object-id $githubDeploymentPrincipalId `
  --assignee-principal-type ServicePrincipal `
  --role AcrPush `
  --scope $acrResourceId

az role assignment create `
  --assignee-object-id $githubDeploymentPrincipalId `
  --assignee-principal-type ServicePrincipal `
  --role Reader `
  --scope $acrResourceId
```

Create one federated credential for each service repository because each workflow uses the GitHub environment named `production`. GitHub repositories created after July 15, 2026 use immutable owner and repository IDs in OIDC subjects. Resolve those IDs through the authenticated GitHub CLI instead of constructing subjects from names alone:

```powershell
$repositoryNames = @(
  'campfit-core-api',
  'campfit-adventure',
  'campfit-bff-mobile',
  'campfit-analytics'
)

foreach ($repository in $repositoryNames) {
  $metadata = gh api "repos/sayedsaadmvp/$repository" | ConvertFrom-Json
  if (-not $metadata.id -or -not $metadata.owner.id) {
    throw "Could not resolve immutable GitHub IDs for $repository. Run 'gh auth login' and retry."
  }

  $credentialFile = Join-Path $env:TEMP "$repository-oidc.json"
  @{
    name = "$repository-production-immutable"
    issuer = 'https://token.actions.githubusercontent.com'
    subject = "repo:$($metadata.owner.login)@$($metadata.owner.id)/$($metadata.name)@$($metadata.id)`:environment:production"
    description = "CampFit production deployment from $repository"
    audiences = @('api://AzureADTokenExchange')
  } | ConvertTo-Json | Set-Content -LiteralPath $credentialFile

  az ad app federated-credential create `
    --id $githubDeploymentClientId `
    --parameters $credentialFile

  Remove-Item -LiteralPath $credentialFile
}
```

Verify the registered subjects:

```powershell
az ad app federated-credential list `
  --id $githubDeploymentClientId `
  --query "[].{Name:name,Subject:subject,Issuer:issuer,Audience:audiences[0]}" `
  --output table
```

For example, the Core API production workflow currently presents this exact subject:

```text
repo:sayedsaadmvp@309130955/campfit-core-api@1312084023:environment:production
```

If `AADSTS700213` reports no matching federated identity record, compare the assertion subject in the error with the `Subject` column above. They must match character for character. Re-run the creation loop to add the immutable credentials; the older name-based credentials can be removed later from **Microsoft Entra ID > App registrations > github-campfit-prod-deployer > Certificates & secrets > Federated credentials**. Do not use interactive `az login` in GitHub Actions.

## 9. Configure GitHub Actions

Authenticate GitHub CLI with an account that has `Admin` access:

```powershell
gh auth login
gh auth status
```

The service workflows use GitHub environment variables, not GitHub secrets. Create the `production` environment in every repository:

```powershell
$repositories = @(
  'sayedsaadmvp/campfit-core-api',
  'sayedsaadmvp/campfit-adventure',
  'sayedsaadmvp/campfit-bff-mobile',
  'sayedsaadmvp/campfit-analytics'
)

foreach ($repository in $repositories) {
  gh api --method PUT "repos/$repository/environments/production"
}
```

Add the six shared variables to every repository:

```powershell
foreach ($repository in $repositories) {
  gh variable set AZURE_CLIENT_ID --repo $repository --env production --body $githubDeploymentClientId
  gh variable set AZURE_TENANT_ID --repo $repository --env production --body $tenantId
  gh variable set AZURE_SUBSCRIPTION_ID --repo $repository --env production --body $subscriptionId
  gh variable set AZURE_RESOURCE_GROUP --repo $repository --env production --body $resourceGroup
  gh variable set ACR_NAME --repo $repository --env production --body $acrName
  gh variable set ACR_LOGIN_SERVER --repo $repository --env production --body $acrLoginServer
}
```

Add the service-specific Container App variable:

```powershell
gh variable set CONTAINER_APP_NAME --repo sayedsaadmvp/campfit-core-api --env production --body campfit-core-api
gh variable set CONTAINER_APP_NAME --repo sayedsaadmvp/campfit-adventure --env production --body campfit-adventure
gh variable set CONTAINER_APP_NAME --repo sayedsaadmvp/campfit-bff-mobile --env production --body campfit-bff-mobile
gh variable set CONTAINER_APP_NAME --repo sayedsaadmvp/campfit-analytics --env production --body campfit-analytics
```

Required GitHub Actions secrets: **none**. Do not create `AZURE_CREDENTIALS` or an Azure client secret. Database, Firebase, fitness-provider, Stripe, and telemetry values remain in Azure Key Vault.

In each repository's GitHub settings:

1. Open `Settings > Environments > production`.
2. Add a required reviewer for production.
3. Restrict deployment branches to `main`.
4. Confirm Actions are enabled.
5. Confirm the seven environment variables are visible.

## 10. Merge and Deploy with GitHub Actions

The four services are separate Git repositories. Commit and merge each service before updating its submodule pointer in the platform repository.

Recommended release order:

1. Core API
2. Adventure API
3. Analytics
4. Mobile BFF
5. Platform repository submodule pointers and deployment documentation

For each service:

```powershell
Set-Location services\<service-directory>
git status
git checkout -b deploy/production
git add --all
git commit -m 'Prepare service for Azure production deployment'
git push --set-upstream origin deploy/production
```

Open a pull request, wait for CI, review it, and merge into `main`. A push to `main` starts that service's `.github/workflows/deploy.yml` workflow. The workflow:

1. Restores, builds, and tests the service.
2. Builds an image tagged with the full commit SHA.
3. Logs into Azure with OIDC.
4. Pushes the image to ACR.
5. Updates only that service's Container App.
6. Waits for a healthy active revision.

Monitor workflows:

```powershell
gh run list --repo sayedsaadmvp/campfit-core-api --limit 5
gh run list --repo sayedsaadmvp/campfit-adventure --limit 5
gh run list --repo sayedsaadmvp/campfit-analytics --limit 5
gh run list --repo sayedsaadmvp/campfit-bff-mobile --limit 5
```

After all service merges, update platform submodule pointers:

```powershell
Set-Location C:\ssaad\CampFit\Development\campfit-modern-platform
git add services\campfit-core-api services\campfit-adventure services\campfit-analytics services\campfit-bff-mobile
git add AZURE-PRODUCTION-DEPLOYMENT.md infrastructure README.md
git commit -m 'Document and reference Azure production deployment'
git push
```

The platform repository push does not deploy services. Service repository workflows own normal deployments.

## 11. Final Production Checklist

- Azure CLI shows the intended subscription ID and tenant.
- All resources are in `rg-campfit-prod` and tagged `Environment=Production`.
- ACR admin credentials are disabled.
- Key Vault uses RBAC and purge protection.
- Runtime identity has `AcrPull` and `Key Vault Secrets User`.
- GitHub deployment identity has no client secret.
- Each repository has a `production` OIDC federated credential.
- Each repository has the seven required GitHub environment variables.
- Core and Adventure migrations are applied manually.
- Analytics views exist in `campfit_core`.
- Analytics login has read-only grants.
- Analytics login has no direct grants on Core's `public` tables.
- Temporary local PostgreSQL firewall access is removed.
- BFF is external; Adventure and Analytics are internal.
- Core callback ingress has an explicit documented decision.
- `/alive`, `/health`, `/version`, and `/health/db` pass where applicable.
- Firebase-authenticated BFF requests succeed.
- Application Insights receives traces and logs from all four services.
- Full request/response body telemetry remains disabled.
- Previous immutable image SHA tags remain available for rollback.

## Rollback

List revisions and their images:

```powershell
az containerapp revision list `
  --resource-group $resourceGroup `
  --name '<container-app-name>' `
  --query '[].{Revision:name,Active:properties.active,Health:properties.healthState,Image:properties.template.containers[0].image}' `
  --output table
```

Deploy the previous image SHA:

```powershell
az containerapp update `
  --resource-group $resourceGroup `
  --name '<container-app-name>' `
  --image "$acrLoginServer/<image-name>:<previous-full-sha>"
```

Application rollback does not reverse database migrations. Database rollback requires a separately reviewed migration or Azure PostgreSQL restore.

## References

- [Azure Container Apps environments](https://learn.microsoft.com/azure/container-apps/environment)
- [Azure Container Registry RBAC](https://learn.microsoft.com/azure/container-registry/container-registry-rbac-built-in-roles-directory-reference)
- [Azure Key Vault RBAC](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
- [GitHub Actions OIDC with Azure](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect)
- [GitHub OIDC immutable subject claims](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims)
- [PostgreSQL Flexible Server networking](https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-networking)
- [Workspace-based Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/create-workspace-resource)
