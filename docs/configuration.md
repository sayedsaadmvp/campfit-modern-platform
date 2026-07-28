# Configuration

## Local

Docker Compose reads `.env`; `.env` is ignored. `appsettings.Development.json` contains only safe development defaults. Development never contacts Azure Key Vault.

## Production Bootstrap

Container Apps receive non-secret resource identifiers:

```text
APP_ENV
ENVIRONMENT
ASPNETCORE_ENVIRONMENT
KEY_VAULT_URI
KEY_VAULT_NAME
USER_ASSIGNED_IDENTITY_CLIENT_ID
AZURE_CLIENT_ID
GIT_SHA
```

The BFF also receives internal service URLs and an explicit browser CORS origin.

## Key Vault Allowlists

Core loads `CORE-*`, `FIREBASE-*`, and `FITBIT-*`. Adventure loads `ADVENTURE-*` and `FIREBASE-*`. The BFF loads only `FIREBASE-*`. Analytics uses its explicit mapping in `app/core/key_vault.py`.

Environment variables are re-applied after Key Vault in .NET and checked before assignment in Python, so explicit environment values win.

## Firebase

Production requires:

```text
FIREBASE-PROJECT-ID
FIREBASE-SERVICE-ACCOUNT-JSON
```

`FIREBASE-SERVICE-ACCOUNT-BASE64` is also supported by .NET. Analytics maps the same names to its existing runtime credential materialization.

Never log or commit the JSON. Store it as a Key Vault secret and grant only `Key Vault Secrets User` to the runtime identity.

## PostgreSQL

Production database secrets are individual values instead of one opaque connection string. Set SSL mode to `VerifyFull` where supported and use separate runtime users:

```text
core_app
adventure_app
analytics_reader
```

Analytics receives no write grants.
