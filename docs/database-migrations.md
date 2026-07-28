# Database Migrations

Core and Adventure own separate EF Core migration histories. Analytics remains read-only and does not run operational schema migrations.

## Create a Migration

Core:

```powershell
Set-Location services/campfit-core-api
dotnet tool restore
dotnet ef migrations add <MigrationName> --output-dir Data/Migrations
dotnet ef migrations script --idempotent --output artifacts/migration.sql
```

Adventure:

```powershell
Set-Location services/campfit-adventure
dotnet tool restore
dotnet ef migrations add <MigrationName> --output-dir Data/Migrations
dotnet ef migrations script --idempotent --output artifacts/migration.sql
```

Review both the generated C# and SQL before commit.

## Apply Locally

Docker Compose starts with development `EnsureCreated` for fast template startup. To test the actual migration history against a fresh local database, create the database, export the relevant connection fields, and run:

```powershell
dotnet ef database update
```

## Apply to Production

1. Back up the target database or take a restore point.
2. Review the idempotent SQL and backward compatibility.
3. Use private networking or add one temporary exact-IP firewall rule.
4. Use a restricted migration account, not the runtime account.
5. Export only that service's settings.
6. Apply once.
7. Verify the migration history and application health.
8. Remove the firewall rule.

Core PowerShell environment:

```powershell
$env:CoreDatabase__Host = "<server>.postgres.database.azure.com"
$env:CoreDatabase__Port = "5432"
$env:CoreDatabase__Database = "campfit_core"
$env:CoreDatabase__Username = "<migration-user>"
$env:CoreDatabase__Password = "<password>"
$env:CoreDatabase__SslMode = "VerifyFull"
Set-Location services/campfit-core-api
dotnet tool restore
dotnet ef database update
```

Adventure uses `AdventureDatabase__Host`, `AdventureDatabase__Port`, `AdventureDatabase__Database`, `AdventureDatabase__Username`, `AdventureDatabase__Password`, and `AdventureDatabase__SslMode`.

Do not run `Database.Migrate()` from every production replica. Do not combine application rollback with an assumed schema rollback. Use a reviewed compensating migration or restore procedure.
