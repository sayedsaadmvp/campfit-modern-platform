# Azure Deployment

Production uses existing Azure resources:

- shared ACR
- existing Container Apps environment
- existing PostgreSQL Flexible Server
- existing Key Vault
- existing user-assigned managed identity

Applications load secrets directly from Key Vault at runtime. Container Apps should only hold non-secret bootstrap settings like `KEY_VAULT_URI` and `USER_ASSIGNED_IDENTITY_CLIENT_ID`.
