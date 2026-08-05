$repositories = @(
  'sayedsaadmvp/campfit-core-api',
  'sayedsaadmvp/campfit-adventure',
  'sayedsaadmvp/campfit-bff-mobile',
  'sayedsaadmvp/campfit-analytics'
)

foreach ($repository in $repositories) {
  gh api --method PUT "repos/$repository/environments/production"
}


foreach ($repository in $repositories) {
  gh variable set AZURE_CLIENT_ID --repo $repository --env production --body $githubDeploymentClientId
  gh variable set AZURE_TENANT_ID --repo $repository --env production --body $tenantId
  gh variable set AZURE_SUBSCRIPTION_ID --repo $repository --env production --body $subscriptionId
  gh variable set AZURE_RESOURCE_GROUP --repo $repository --env production --body $resourceGroup
  gh variable set ACR_NAME --repo $repository --env production --body $acrName
  gh variable set ACR_LOGIN_SERVER --repo $repository --env production --body $acrLoginServer
}
