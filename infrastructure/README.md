# Infrastructure Notes

This repository assumes Azure production resources already exist. The platform scripts attach Container Apps to:

- an existing Container Apps environment
- one shared Azure Container Registry
- one existing Azure Key Vault
- one existing user-assigned managed identity
- one existing Azure Database for PostgreSQL Flexible Server

The AppHost must not recreate production PostgreSQL. Use `scripts/configure-azure.ps1` for idempotent configuration of non-secret bootstrap settings only.
