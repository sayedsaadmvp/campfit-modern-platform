param(
  [string]$SubscriptionId = 'cb5afb7d-c9f1-4c89-a71e-af4d0022d8d2',
  [string]$ResourceGroup = 'rg-campfit-prod'
)

$ErrorActionPreference = 'Stop'

$services = @(
  @{
    Name = 'campfit-core-api'
    Setting = 'CoreDatabase__SslMode=Require'
  },
  @{
    Name = 'campfit-adventure'
    Setting = 'AdventureDatabase__SslMode=Require'
  },
  @{
    Name = 'campfit-analytics'
    Setting = 'POSTGRES_SSLMODE=require'
  }
)

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
  throw 'Unable to select the Azure subscription. Run az login and retry.'
}

$revisionSuffix = "sslfix-$(Get-Date -Format 'yyMMddHHmmss')"

foreach ($service in $services) {
  Write-Host "Configuring PostgreSQL TLS for $($service.Name)..."
  az containerapp update `
    --name $service.Name `
    --resource-group $ResourceGroup `
    --set-env-vars $service.Setting `
    --revision-suffix $revisionSuffix `
    --output none

  if ($LASTEXITCODE -ne 0) {
    throw "Failed to update $($service.Name)."
  }
}

az containerapp revision list `
  --name 'campfit-core-api' `
  --resource-group $ResourceGroup `
  --query "[].{Name:name,Active:properties.active,Health:properties.healthState,Running:properties.runningState}" `
  --output table

az containerapp revision list `
  --name 'campfit-adventure' `
  --resource-group $ResourceGroup `
  --query "[].{Name:name,Active:properties.active,Health:properties.healthState,Running:properties.runningState}" `
  --output table

az containerapp revision list `
  --name 'campfit-analytics' `
  --resource-group $ResourceGroup `
  --query "[].{Name:name,Active:properties.active,Health:properties.healthState,Running:properties.runningState}" `
  --output table
