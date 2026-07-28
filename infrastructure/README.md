# Infrastructure

`main.bicep` references existing shared Azure resources and manages only:

- Four Azure Container Apps
- Runtime identity attachments
- Managed-identity ACR configuration
- `AcrPull`
- `Key Vault Secrets User`
- Ingress, probes, scaling, revisions, and non-secret environment values

It never creates or deletes PostgreSQL, ACR, Key Vault, the Container Apps environment, or the managed identity.

Create an ignored local parameter file:

```powershell
Copy-Item infrastructure/azure.parameters.example.json infrastructure/azure.parameters.local.json
./scripts/deploy-platform.ps1 -ParametersFile infrastructure/azure.parameters.local.json -WhatIf
./scripts/deploy-platform.ps1 -ParametersFile infrastructure/azure.parameters.local.json
```

All image references must use immutable Git SHA tags. Only the BFF has external ingress.
