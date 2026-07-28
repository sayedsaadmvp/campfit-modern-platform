# CampFit Modern Platform

CampFit is split into four independently deployable services and one orchestration repository:

| Component | Runtime | Local port | Production ingress | Database |
| --- | --- | ---: | --- | --- |
| Mobile BFF | ASP.NET Core 10 | 7000 | Public | None |
| Core API | ASP.NET Core 10, EF Core 10 | 7001 | Internal | `campfit_core` |
| Adventure API | ASP.NET Core 10, EF Core 10 | 7002 | Internal | `campfit_adventure` |
| Analytics | FastAPI, Python 3.12 | 7003 | Internal | `campfit_analytics` read-only |
| AppHost | Aspire 13.4 | Dynamic | Not deployed as an API | Local orchestration |

Production uses one Azure environment. Local development is the non-production environment; no cloud staging environment is created.

## Architecture

```text
Flutter / Flutter Web
        |
        v
Public campfit-bff-mobile
        |
        +--> Internal campfit-core-api ------> campfit_core
        +--> Internal campfit-adventure -----> campfit_adventure
        +--> Internal analytics-read-service -> campfit_analytics (read-only)

All images --> shared Azure Container Registry
All services --> existing Azure Container Apps environment
Runtime identity --> Azure Key Vault and ACR pull
```

API Management is intentionally not included. It can be added later in front of the public BFF without exposing the three internal services.

## Aspire Responsibilities

Aspire models the local topology, starts PostgreSQL and the services, injects service references, waits for health, and provides the dashboard for logs and telemetry. Aspire does not own service repositories, EF models, production PostgreSQL, Key Vault secrets, or independent service deployments.

## Repository Model

The platform repository tracks four service repositories as Git submodules. Each service owns its Dockerfile, dependencies, migrations or models, tests, GitHub workflow, image, Container App, and release lifecycle.

Clone everything:

```powershell
git clone --recurse-submodules https://github.com/sayedsaadmvp/campfit-modern-platform.git
Set-Location campfit-modern-platform
git submodule update --init --recursive
```

Update one service pointer after that service has been committed and pushed:

```powershell
Set-Location services/campfit-core-api
git checkout main
git pull
Set-Location ../..
git add services/campfit-core-api
git commit -m "Update Core API submodule"
```

A service deployment never depends on updating this pointer. A push to a service repository deploys only that service.

## Prerequisites

- .NET SDK 10.0.302 or a compatible 10.0 feature band
- Aspire CLI 13.4 or `dotnet run` for the AppHost
- Docker Desktop with Linux containers
- Git
- PowerShell 7
- Python 3.12 and `pip` for standalone Analytics work
- Azure CLI with the Container Apps extension for cloud operations
- Azure subscription access for production deployment

Verify:

```powershell
dotnet --version
docker version
git --version
az version
aspire --version
```

## First-Time Local Setup

From the platform root:

```powershell
Copy-Item .env.example .env
dotnet restore CampFit.Modern.slnx
dotnet build CampFit.Modern.slnx --configuration Release
docker compose config
```

The checked-in local database credentials are development-only. Do not reuse `Test123` outside a developer machine.

## Run with Docker Compose

Docker Compose is the easiest fixed-port path:

```powershell
docker compose up --build --wait
docker compose ps
```

Test all public development endpoints:

```powershell
Invoke-RestMethod http://localhost:7000/health
Invoke-RestMethod http://localhost:7000/version
Invoke-RestMethod -Headers @{ "X-Dev-User" = "local-test-user" } http://localhost:7000/api/mobile/home
```

Bash:

```bash
docker compose up --build --wait
curl http://localhost:7000/health
curl http://localhost:7000/version
curl -H "X-Dev-User: local-test-user" http://localhost:7000/api/mobile/home
```

Stop without deleting data:

```powershell
docker compose down
```

Delete only the local PostgreSQL volume and rebuild from initialization scripts:

```powershell
docker compose down --volumes
docker compose up --build --wait
```

The volume command deletes local development data. It does not target Azure.

## Run with Aspire

Start from the platform root:

```powershell
aspire run --project platform/CampFit.AppHost/CampFit.AppHost.csproj
```

If the Aspire CLI is unavailable:

```powershell
dotnet run --project platform/CampFit.AppHost/CampFit.AppHost.csproj --launch-profile http
```

Open `http://localhost:18888` using the tokenized login URL printed by the command. This profile uses HTTP locally and does not require a trusted developer certificate. Aspire assigns service ports dynamically; use the BFF endpoint shown in the dashboard. Docker Compose is the fixed `7000`-`7003` option.

## API Documentation

With Docker Compose running, use these interactive development pages:

| Service | Interactive documentation | OpenAPI document |
|---|---|---|
| Mobile BFF | `http://localhost:7000/swagger` | `http://localhost:7000/swagger/v1/swagger.json` |
| Core API | `http://localhost:7001/swagger` | `http://localhost:7001/swagger/v1/swagger.json` |
| Adventure API | `http://localhost:7002/swagger` | `http://localhost:7002/swagger/v1/swagger.json` |
| Analytics | `http://localhost:7003/docs` | `http://localhost:7003/openapi.json` |

Analytics also provides ReDoc at `http://localhost:7003/redoc`. When using Aspire, open each resource endpoint from the dashboard and append `/swagger` for .NET services or `/docs` for Analytics. The .NET Swagger pages are enabled only in `Development`.

## Local Firebase Behavior

Development uses `DevelopmentFirebaseMiddleware` and the identity `local-test-user`. The `X-Dev-User` header can override it for local tests only. Outside Development, all protected APIs verify the Firebase token signature, issuer, audience, expiry, and UID through Firebase Admin.

Production request:

```powershell
$headers = @{ Authorization = "Bearer <firebase-id-token>" }
Invoke-RestMethod -Headers $headers https://<bff-fqdn>/api/mobile/home
```

## Local PostgreSQL

The local PostgreSQL container creates:

- `campfit_core`, owned by `core_user`
- `campfit_adventure`, owned by `adventure_user`
- `campfit_analytics`, connect-only access for `analytics_user`

Connect:

```powershell
docker compose exec postgres psql -U postgres -d campfit_core
docker compose exec postgres psql -U postgres -d campfit_adventure
docker compose exec postgres psql -U postgres -d campfit_analytics
```

Core and Adventure seed one development record. Production never seeds automatically.

## Health and Version Endpoints

Every service exposes:

- `/alive`: process liveness only
- `/health`: application readiness
- `/version`: service, semantic version, Git SHA, and environment

Analytics also exposes `/health/db` for database readiness. Azure probes call unauthenticated health routes; protected business routes still require Firebase.

## Production Model

Production attaches to existing resources:

- Resource group
- Azure Container Apps environment
- Azure Container Registry
- Azure Key Vault
- User-assigned runtime managed identity
- Azure Database for PostgreSQL Flexible Server
- Optional existing Log Analytics or Application Insights

The Bicep deployment in `infrastructure/main.bicep` does not create or delete those resources. It creates or updates the four Container Apps plus `AcrPull` and `Key Vault Secrets User` assignments for the runtime identity.

## Key Vault Configuration

Applications receive only these bootstrap values in Container Apps:

```text
APP_ENV=production
ENVIRONMENT=Production
KEY_VAULT_URI=https://<vault>.vault.azure.net/
KEY_VAULT_NAME=<vault>
USER_ASSIGNED_IDENTITY_CLIENT_ID=<runtime-identity-client-id>
AZURE_CLIENT_ID=<runtime-identity-client-id>
```

The services directly read allowlisted secrets from Key Vault. Explicit environment variables are re-applied after Key Vault, so an explicit environment value wins.

Required baseline secret names:

```text
CORE-POSTGRES-HOST
CORE-POSTGRES-PORT
CORE-POSTGRES-DATABASE
CORE-POSTGRES-USERNAME
CORE-POSTGRES-PASSWORD
ADVENTURE-POSTGRES-HOST
ADVENTURE-POSTGRES-PORT
ADVENTURE-POSTGRES-DATABASE
ADVENTURE-POSTGRES-USERNAME
ADVENTURE-POSTGRES-PASSWORD
ANALYTICS-POSTGRES-HOST
ANALYTICS-POSTGRES-PORT
ANALYTICS-POSTGRES-DATABASE
ANALYTICS-POSTGRES-USERNAME
ANALYTICS-POSTGRES-PASSWORD
FIREBASE-PROJECT-ID
FIREBASE-SERVICE-ACCOUNT-JSON
```

Set Firebase JSON from a file so it is not pasted into repository files:

```powershell
az keyvault secret set `
  --vault-name <vault-name> `
  --name FIREBASE-SERVICE-ACCOUNT-JSON `
  --file C:\secure\firebase-service-account.json
```

Set each PostgreSQL value with `az keyvault secret set` or the Azure portal. Never commit the values or pass them as Container App secrets.

## Production Deployment: Path A

Path A is the initial platform bootstrap and is repeated only for shared topology, identities, ingress, scaling, or a new service.

1. Sign in and select the subscription:

```powershell
az login
az account set --subscription <subscription-id>
az extension add --name containerapp --upgrade
```

2. Verify the existing resources:

```powershell
az group show --name <resource-group>
az containerapp env show --resource-group <resource-group> --name <aca-environment>
az acr show --resource-group <resource-group> --name <acr-name>
az keyvault show --resource-group <resource-group> --name <vault-name>
az identity show --resource-group <resource-group> --name <runtime-identity>
az postgres flexible-server show --resource-group <resource-group> --name <postgres-server>
```

3. Create missing databases only after reviewing the preview:

```powershell
./scripts/configure-production-databases.ps1 `
  -ResourceGroup <resource-group> `
  -ServerName <postgres-server> `
  -WhatIf

./scripts/configure-production-databases.ps1 `
  -ResourceGroup <resource-group> `
  -ServerName <postgres-server> `
  -Confirm
```

Create separate least-privilege PostgreSQL roles with SSL required. Analytics must receive only `CONNECT`, `USAGE`, and `SELECT` on approved schemas/views.

4. Push one bootstrap image per service to the existing ACR:

```powershell
$tag = git rev-parse HEAD
az acr build --registry <acr-name> --image "campfit-core-api:$tag" services/campfit-core-api
az acr build --registry <acr-name> --image "campfit-adventure:$tag" services/campfit-adventure
az acr build --registry <acr-name> --image "campfit-bff-mobile:$tag" services/campfit-bff-mobile
az acr build --registry <acr-name> --image "analytics-read-service:$tag" services/analytics-read-service
```

5. Copy the parameter example to an ignored local file and fill in resource names and immutable image references:

```powershell
Copy-Item infrastructure/azure.parameters.example.json infrastructure/azure.parameters.local.json
```

6. Preview and apply:

```powershell
./scripts/deploy-platform.ps1 `
  -ParametersFile infrastructure/azure.parameters.local.json `
  -WhatIf

./scripts/deploy-platform.ps1 `
  -ParametersFile infrastructure/azure.parameters.local.json
```

7. Verify:

```powershell
$bffFqdn = az containerapp show `
  --resource-group <resource-group> `
  --name campfit-bff-mobile `
  --query properties.configuration.ingress.fqdn `
  --output tsv

Invoke-RestMethod "https://$bffFqdn/health"
Invoke-RestMethod "https://$bffFqdn/version"
```

Core, Adventure, and Analytics default to internal ingress. Only the BFF is public.

## Production Deployment: Path B

Path B is the normal release path. A push to a service `main` branch:

1. Restores and builds that service.
2. Runs that repository's tests.
3. Builds an image tagged with the full Git SHA.
4. Authenticates to Azure using GitHub OIDC.
5. Pushes to the shared ACR.
6. Updates only that service's Container App.
7. Waits for the active revision to become healthy.
8. Calls public BFF health when deploying the BFF.

Configure a GitHub environment named `production` in each service repository. Add approval protection because there is no cloud staging environment.

Required GitHub environment variables:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
AZURE_RESOURCE_GROUP
ACR_NAME
ACR_LOGIN_SERVER
CONTAINER_APP_NAME
```

These IDs and names are not secrets. The OIDC identity needs `AcrPush` on the registry and permission to update only the intended Container App. Do not add an Azure client secret.

The platform repository uses additional variables listed in `docs/azure-deployment.md`.

## EF Migrations

Each .NET service owns a pinned `dotnet-ef` tool and its migration history.

Create a migration:

```powershell
Set-Location services/campfit-core-api
dotnet tool restore
dotnet ef migrations add <MigrationName> --output-dir Data/Migrations
```

Apply locally:

```powershell
dotnet ef database update
```

For production, back up the database, open a temporary single-IP firewall rule or use private network access, export that service's production database environment variables, and run `dotnet ef database update` exactly once as an explicit release operation. APIs do not call `Database.Migrate()` in production.

See `docs/database-migrations.md` for exact Core and Adventure commands.

## Temporary PostgreSQL Firewall Access

Use one exact public IPv4 and remove the rule immediately:

```powershell
./scripts/postgres-firewall.ps1 `
  -Action Add `
  -ResourceGroup <resource-group> `
  -ServerName <postgres-server> `
  -WhatIf

./scripts/postgres-firewall.ps1 `
  -Action Add `
  -ResourceGroup <resource-group> `
  -ServerName <postgres-server>
```

The script prints the exact removal command. Never allow `0.0.0.0` through `255.255.255.255`.

## Rollback

List revisions and images:

```powershell
az containerapp revision list `
  --resource-group <resource-group> `
  --name <container-app-name> `
  --output table
```

Single revision mode creates immutable revisions but directs traffic to the latest healthy revision. To roll back, update the app to the previous immutable image:

```powershell
az containerapp update `
  --resource-group <resource-group> `
  --name <container-app-name> `
  --image <acr>.azurecr.io/<image>:<previous-full-git-sha>
```

Do not delete the previous working image. Database rollback requires a separately reviewed migration or backup restore; never assume an application rollback reverses schema changes.

## Logs and Troubleshooting

```powershell
az containerapp logs show `
  --resource-group <resource-group> `
  --name <container-app-name> `
  --follow
```

Common checks:

```powershell
dotnet build CampFit.Modern.slnx --configuration Release
docker compose config
docker compose ps
docker compose logs campfit-bff-mobile
docker compose logs postgres
```

See `docs/troubleshooting.md` for authentication, Key Vault, ACR, PostgreSQL, and health-probe failures.

## Security Checklist

- No secrets or Firebase JSON in Git
- No `.env` or credentials copied into images
- GitHub OIDC instead of client secrets
- User-assigned managed identity for runtime ACR pull and Key Vault access
- Full Git SHA image tags
- Non-root containers
- TLS terminated by Azure Container Apps
- Internal ingress for Core, Adventure, and Analytics
- Firebase Admin token verification on protected .NET routes
- Read-only Analytics database role
- Explicit production migrations and backups
- Exact-IP temporary database firewall rules
- No production seed data
- No automatic destructive database action
- API Management deferred to a later layer in front of the BFF

## Additional Documentation

- `docs/local-development.md`
- `docs/azure-deployment.md`
- `docs/configuration.md`
- `docs/database-migrations.md`
- `docs/troubleshooting.md`
- `docs/architecture.md`
- `docs/repository-strategy.md`
- `TODO-MIGRATION.md`
