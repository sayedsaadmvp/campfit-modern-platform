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

All image references must use immutable Git SHA tags. BFF and Core currently retain external
ingress; make Core internal only after every third-party callback has moved to the BFF URL.

## Deploy Changes to Existing Production Apps

Azure resource-group deployments are incremental by default. This deployment updates the
existing Container Apps and role assignments declared in `main.bicep`; it does not recreate
the resource group, PostgreSQL server, Container Apps environment, ACR, Key Vault, or managed
identities.

From the repository root, authenticate and select production:

```powershell
az login
az account set --subscription cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2
az account show --query '{name:name,id:id}' --output table
```

Before every infrastructure deployment, list the images currently running in Azure:

```powershell
az containerapp list `
  --resource-group rg-campfit-prod `
  --query '[].{name:name,image:properties.template.containers[0].image}' `
  --output table
```

Update the ignored `infrastructure/azure.parameters.local.json` so all four `Images` values
exactly match the deployed immutable image tags. Otherwise an infrastructure deployment can
roll a service back to an older image. The local production file is intentionally excluded
from Git.

Always preview first:

```powershell
.\scripts\deploy-platform.ps1 `
  -ParametersFile infrastructure\azure.parameters.local.json `
  -WhatIf
```

Do not continue if the preview removes identities, environment variables, secrets, or other
service-specific configuration. Expected Azure-generated property and environment-array order
differences may appear as `Modify` operations.

Apply the same reviewed parameters without `-WhatIf`:

```powershell
.\scripts\deploy-platform.ps1 `
  -ParametersFile infrastructure\azure.parameters.local.json
```

Verify the resulting revisions and scaling configuration:

```powershell
az containerapp list `
  --resource-group rg-campfit-prod `
  --query '[].{name:name,revision:properties.latestReadyRevisionName,min:properties.template.scale.minReplicas,max:properties.template.scale.maxReplicas,image:properties.template.containers[0].image}' `
  --output table

az containerapp revision list `
  --name campfit-bff-mobile `
  --resource-group rg-campfit-prod `
  --query '[?properties.active].{name:name,health:properties.healthState,running:properties.runningState,replicas:properties.replicas}' `
  --output table

```

Finally, verify the public BFF endpoints and one authenticated BFF-to-Core request. Keep Core
and BFF at a minimum of one replica for interactive mobile traffic; Adventure and Analytics may
scale to zero when their cold-start tradeoff is acceptable.

Production liveness and readiness probes run every 240 seconds, the maximum interval supported
by Azure Container Apps. Platform probes run only while a replica exists and do not prevent an
app configured with zero minimum replicas from scaling to zero. Local Docker health checks remain
more frequent because Compose uses them to order service startup.
