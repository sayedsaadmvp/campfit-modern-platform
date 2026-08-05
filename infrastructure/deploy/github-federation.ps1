$repositories = @(
  'campfit-core-api',
  'campfit-adventure',
  'campfit-bff-mobile',
  'campfit-analytics'
)

foreach ($repository in $repositories) {
  $credentialFile = Join-Path $env:TEMP "$repository-oidc.json"
  @{
    name = "$repository-production"
    issuer = 'https://token.actions.githubusercontent.com'
    subject = "repo:sayedsaadmvp/$repository`:environment:production"
    description = "CampFit production deployment from $repository"
    audiences = @('api://AzureADTokenExchange')
  } | ConvertTo-Json | Set-Content -LiteralPath $credentialFile

  az ad app federated-credential create `
    --id $githubDeploymentClientId `
    --parameters $credentialFile

  Remove-Item -LiteralPath $credentialFile
}




