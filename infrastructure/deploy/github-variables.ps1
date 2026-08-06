$repositories = @(
  'sayedsaadmvp/campfit-core-api',
  'sayedsaadmvp/campfit-adventure',
  'sayedsaadmvp/campfit-bff-mobile',
  'sayedsaadmvp/campfit-analytics'
)

foreach ($repository in $repositories) {
  gh api --method PUT "repos/$repository/environments/production"
}

# Azure validates GitHub's immutable repository subject before workflows can log in.
& (Join-Path $PSScriptRoot 'github-federation.ps1')

if ($LASTEXITCODE -ne 0) {
  throw 'GitHub OIDC federation setup failed.'
}

foreach ($repository in $repositories) {
  gh variable set AZURE_CLIENT_ID --repo $repository --env production --body $githubDeploymentClientId
  gh variable set AZURE_TENANT_ID --repo $repository --env production --body $tenantId
  gh variable set AZURE_SUBSCRIPTION_ID --repo $repository --env production --body $subscriptionId
  gh variable set AZURE_RESOURCE_GROUP --repo $repository --env production --body $resourceGroup
  gh variable set ACR_NAME --repo $repository --env production --body $acrName
  gh variable set ACR_LOGIN_SERVER --repo $repository --env production --body $acrLoginServer
}
