# Configuration

Development uses local `appsettings*.json` and `.env`.

Production uses:

- `APP_ENV=production`
- `ENVIRONMENT=Production`
- `KEY_VAULT_URI`
- `USER_ASSIGNED_IDENTITY_CLIENT_ID`
- `AZURE_CLIENT_ID`

Environment variables must win over Key Vault values.
