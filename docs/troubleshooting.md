# Troubleshooting

## Solution Build Says No Projects

Use `CampFit.Modern.slnx`, which contains all four .NET projects:

```powershell
dotnet sln CampFit.Modern.slnx list
dotnet build CampFit.Modern.slnx --configuration Release
```

## Deprecated Aspire Workload Error

The AppHost uses `Aspire.AppHost.Sdk/13.4.0`. Remove any old workload-era `<IsAspireHost>` property. The Aspire workload is no longer required.

## Aspire HTTPS Certificate Error

Use the repository's HTTP launch profile:

```powershell
dotnet run --project platform/CampFit.AppHost/CampFit.AppHost.csproj --launch-profile http
```

The dashboard listens on `http://localhost:18888` and still requires the token printed in the terminal. No developer certificate is required. If you intentionally switch to an HTTPS profile, repair the local certificate separately with `dotnet dev-certs https --trust`.

## Compose Service Is Unhealthy

```powershell
docker compose ps
docker compose logs postgres
docker compose logs campfit-core-api
docker compose logs campfit-adventure
```

If a pre-existing local volume was created before database initialization changed and local data is disposable:

```powershell
docker compose down --volumes
docker compose up --build --wait
```

## Key Vault Startup Failure

Confirm the identity is attached, bootstrap values are present, and RBAC has propagated:

```powershell
az containerapp identity show --resource-group <rg> --name <app>
az containerapp show --resource-group <rg> --name <app> --query properties.template.containers[0].env
az role assignment list --assignee <identity-principal-id> --scope <key-vault-resource-id> --output table
```

Do not print secret values.

## ACR Pull Failure

Check the app's registry identity and `AcrPull`:

```powershell
az containerapp registry list --resource-group <rg> --name <app> --output table
az role assignment list --assignee <identity-principal-id> --scope <acr-resource-id> --output table
```

## Firebase 401

Confirm the request contains a Firebase ID token rather than a custom token, `FIREBASE-PROJECT-ID` matches its audience, the service-account JSON is valid, and the token is not expired. Health routes intentionally do not require Firebase.

## BFF Returns Analytics Degraded

The BFF treats Analytics as optional. Check the internal Analytics FQDN, its revision health, Key Vault settings, and PostgreSQL read-only login.

## PostgreSQL Connection Failure

Check host, database, user, SSL mode, firewall/private DNS, and role grants. Use an exact temporary public IP rule only for controlled support work.

## Revision Never Becomes Healthy

```powershell
az containerapp revision list --resource-group <rg> --name <app> --output table
az containerapp logs show --resource-group <rg> --name <app> --type system
az containerapp logs show --resource-group <rg> --name <app> --follow
```

Roll back to the previous immutable SHA image after collecting startup logs.
