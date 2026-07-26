# CampFit Modern Platform

This repository is a small modernization template for CampFit. It keeps each deployable service independent while giving the team one place for local orchestration, Docker Compose, shared Azure bootstrap scripts, and migration notes.

## Included services

- `services/analytics-read-service`: existing FastAPI analytics service snapshot intended to be replaced by a Git submodule
- `services/campfit-core-api`: representative .NET 10 Core API template with EF Core, PostgreSQL, Firebase middleware, Key Vault bootstrap, and one functional endpoint
- `services/campfit-adventure`: representative .NET 10 Adventure API template with its own PostgreSQL schema and endpoint
- `services/campfit-bff-mobile`: public mobile BFF that aggregates downstream APIs
- `platform/CampFit.AppHost`: Aspire AppHost for local topology orchestration

## Clone model

```bash
git clone --recurse-submodules <platform-repository-url>
cd campfit-modern-platform
git submodule update --init --recursive
```

Update one service submodule:

```bash
cd services/campfit-core-api
git checkout main
git pull
cd ../..
git add services/campfit-core-api
git commit -m "Update Core API submodule"
```

## Local prerequisites

- .NET 10 SDK
- Docker Desktop
- Git
- PowerShell 7
- Python 3.12+ for the analytics service
- Aspire CLI when you want the richer local orchestration flow

## Local run

```bash
dotnet restore
dotnet build
docker compose up --build
```

PowerShell:

```powershell
dotnet restore
dotnet build
docker compose up --build
```

Expected local endpoints:

- BFF: `http://localhost:7000/health`
- Core: `http://localhost:7001/health`
- Adventure: `http://localhost:7002/health`
- Analytics: `http://localhost:7003/health`

Authenticated BFF test in development:

```bash
curl -H "X-Dev-User: local-test-user" http://localhost:7000/api/mobile/home
```

## Azure deployment split

Path A, platform bootstrap:

- validate resource group, Container Apps environment, ACR, Key Vault, managed identity, PostgreSQL host
- assign `AcrPull` and `Key Vault Secrets User`
- create or update Container Apps
- apply only non-secret bootstrap environment variables

Path B, normal service deployment:

- build one service
- test one service
- build and push one image tag by Git SHA
- update only that service's Container App
- verify `/health`

## Intentional omissions

- API Management is not implemented here
- no cloud staging environment
- no automatic destructive production migrations

API Management will later sit in front of `campfit-bff-mobile`.
