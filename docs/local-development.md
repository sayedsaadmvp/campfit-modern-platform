# Local Development

## Docker Compose

Use Docker Compose when stable ports are useful:

```powershell
Copy-Item .env.example .env
docker compose config
docker compose up --build --wait
docker compose ps
```

Endpoints:

```text
http://localhost:7000  Mobile BFF
http://localhost:7001  Core API
http://localhost:7002  Adventure API
http://localhost:7003  Analytics
localhost:5432         PostgreSQL
```

If another PostgreSQL instance already uses `5432`, set `POSTGRES_HOST_PORT=55432` in `.env`. Containers still connect to PostgreSQL on internal port `5432`.

Smoke test:

```powershell
Invoke-RestMethod http://localhost:7000/health
Invoke-RestMethod http://localhost:7000/version
Invoke-RestMethod -Headers @{ "X-Dev-User" = "local-test-user" } http://localhost:7000/api/mobile/home
```

Interactive API documentation:

```text
http://localhost:7000/swagger  Mobile BFF
http://localhost:7001/swagger  Core API
http://localhost:7002/swagger  Adventure API
http://localhost:7003/docs     Analytics Swagger UI
http://localhost:7003/redoc    Analytics ReDoc
```

The machine-readable documents are available at `/swagger/v1/swagger.json` for the .NET services and `/openapi.json` for Analytics. Under Aspire, use each dynamic endpoint shown in the dashboard and append the same path.

Inspect:

```powershell
docker compose logs --follow campfit-bff-mobile
docker compose exec postgres psql -U postgres -d campfit_core
```

Stop while retaining the named database volume:

```powershell
docker compose down
```

If initialization SQL changed and disposable local data can be removed:

```powershell
docker compose down --volumes
docker compose up --build --wait
```

## Aspire

```powershell
dotnet restore CampFit.Modern.slnx
dotnet build CampFit.Modern.slnx
dotnet run --project platform/CampFit.AppHost/CampFit.AppHost.csproj --launch-profile http
```

The tokenized dashboard login URL appears in the terminal and the dashboard listens on `http://localhost:18888`. This local profile does not require a trusted HTTPS developer certificate. Aspire service ports are dynamic. Open the `campfit-bff-mobile` endpoint from the dashboard and use its logs, traces, and health status for cross-service debugging.

If the Aspire CLI is installed, this is equivalent:

```powershell
aspire run --project platform/CampFit.AppHost/CampFit.AppHost.csproj
```

## Standalone Services

Run a .NET service from its repository:

```powershell
Set-Location services/campfit-core-api
dotnet restore
dotnet run
```

Run Analytics:

```powershell
Set-Location services/campfit-analytics
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m uvicorn app.main:app --reload --port 7003
```

Standalone services need the corresponding database and downstream URLs in environment variables or local settings.

## Local Authentication

Development middleware sets `local-test-user`; no Azure or Firebase credentials are needed. The bypass is enabled only when `ASPNETCORE_ENVIRONMENT=Development`. Production rejects missing or invalid Firebase bearer tokens.
