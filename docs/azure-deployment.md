# Azure Production Deployment

CampFit has one cloud environment: Production. The absence of staging is mitigated by local Aspire integration checks, CI tests, immutable SHA images, protected GitHub environments, health probes, and retained previous images.

## Existing Resources

The platform deployment requires existing:

- Resource group
- Container Apps environment
- Azure Container Registry
- Key Vault using Azure RBAC
- User-assigned runtime managed identity
- PostgreSQL Flexible Server

`infrastructure/main.bicep` does not create PostgreSQL, ACR, Key Vault, the managed environment, or the identity.

## One-Time Platform Deployment

Build and push initial images, copy `infrastructure/azure.parameters.example.json` to the ignored `infrastructure/azure.parameters.local.json`, and run:

```powershell
./scripts/deploy-platform.ps1 `
  -ParametersFile infrastructure/azure.parameters.local.json `
  -WhatIf

./scripts/deploy-platform.ps1 `
  -ParametersFile infrastructure/azure.parameters.local.json
```

The deployment:

- Attaches the user-assigned identity to all apps.
- Grants that identity `AcrPull` and `Key Vault Secrets User`.
- Configures managed-identity ACR pulls.
- Exposes only `campfit-bff-mobile` publicly.
- Configures `/alive` liveness probes, `/health` readiness for .NET services, and `/health/db` readiness for Analytics.
- Uses single revision mode.
- Sets only non-secret bootstrap environment variables.

## Platform GitHub Environment

Create a protected `production` environment in `campfit-modern-platform`. Add:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
AZURE_RESOURCE_GROUP
AZURE_LOCATION
AZURE_CONTAINER_APPS_ENVIRONMENT
AZURE_CONTAINER_REGISTRY_NAME
AZURE_KEY_VAULT_NAME
AZURE_USER_ASSIGNED_IDENTITY_NAME
AZURE_POSTGRES_HOST
CORE_IMAGE
ADVENTURE_IMAGE
BFF_IMAGE
ANALYTICS_IMAGE
BFF_ALLOWED_CORS_ORIGIN
```

The four image values must be full ACR references with immutable SHA tags.

The platform OIDC principal needs resource-group deployment permission and permission to create role assignments. Keep this principal separate from the runtime identity when possible.

## Service GitHub Environments

Create a protected `production` environment in each service repository:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
AZURE_RESOURCE_GROUP
ACR_NAME
ACR_LOGIN_SERVER
CONTAINER_APP_NAME
```

Use these `CONTAINER_APP_NAME` values:

```text
campfit-core-api
campfit-adventure
campfit-bff-mobile
analytics-read-service
```

The deployment OIDC principal needs `AcrPush` and narrowly scoped Container App update permission. No client secret is used.

## GitHub OIDC Subject

Because workflows target the `production` environment, the federated subject for each repository is:

```text
repo:<github-org>/<repository>:environment:production
```

Create one federated credential per repository on the chosen Azure deployment identity. Confirm issuer `https://token.actions.githubusercontent.com` and audience `api://AzureADTokenExchange`.

## Normal Service Deployment

Push to a service's `main` branch or run its `Build and Deploy` workflow manually. It restores, tests, builds, pushes a full-SHA image, updates only its Container App, and waits for a healthy revision.

Internal Core, Adventure, and Analytics health is enforced by Container Apps readiness probes. The BFF workflow also calls its public `/health` endpoint.

## Rollback

Find the previous image:

```powershell
az containerapp revision list `
  --resource-group <resource-group> `
  --name <app-name> `
  --query "[].{Revision:name,Active:properties.active,Health:properties.healthState,Image:properties.template.containers[0].image}" `
  --output table
```

Update back to the previous SHA image:

```powershell
az containerapp update `
  --resource-group <resource-group> `
  --name <app-name> `
  --image <acr>.azurecr.io/<image>:<previous-sha>
```

For a canary, switch to multiple revision mode, deploy the new revision with zero traffic, validate it from inside the environment, then split traffic. Return to single revision mode after the rollout if that remains the operating standard.

## Operational Verification

```powershell
az containerapp show --resource-group <resource-group> --name campfit-bff-mobile --output table
az containerapp revision list --resource-group <resource-group> --name campfit-bff-mobile --output table
az containerapp logs show --resource-group <resource-group> --name campfit-bff-mobile --follow
```

API Management will be introduced later in front of the public BFF. It must not route directly to internal services.
