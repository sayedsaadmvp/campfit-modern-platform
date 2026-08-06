$repositories = @(
  'sayedsaadmvp/campfit-core-api',
  'sayedsaadmvp/campfit-adventure',
  'sayedsaadmvp/campfit-bff-mobile',
  'sayedsaadmvp/campfit-analytics'
)

if (-not $githubDeploymentClientId) {
  throw 'Set $githubDeploymentClientId to the Entra deployment application client ID before running this script.'
}

$existingCredentials = az ad app federated-credential list `
  --id $githubDeploymentClientId `
  --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
  throw 'Unable to list Entra federated credentials. Run az login and verify access to the deployment application.'
}

foreach ($repository in $repositories) {
  $metadata = gh api "repos/$repository" | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or -not $metadata.id -or -not $metadata.owner.id) {
    throw "Unable to resolve immutable GitHub IDs for $repository. Run gh auth login and retry."
  }

  $repositoryName = $metadata.name
  $credentialName = "${repositoryName}-production-immutable"
  $subject = "repo:$($metadata.owner.login)@$($metadata.owner.id)/$repositoryName@$($metadata.id)`:environment:production"
  $existingCredential = $existingCredentials | Where-Object { $_.name -eq $credentialName }

  if ($existingCredential) {
    if ($existingCredential.subject -ne $subject) {
      throw "Federated credential '$credentialName' exists with an unexpected subject. Remove it from Entra and rerun this script."
    }

    Write-Host "Federated credential already configured: $credentialName"
    continue
  }

  $credentialFile = Join-Path $env:TEMP "$repositoryName-oidc.json"
  try {
    @{
      name = $credentialName
      issuer = 'https://token.actions.githubusercontent.com'
      subject = $subject
      description = "CampFit production deployment from $repositoryName"
      audiences = @('api://AzureADTokenExchange')
    } | ConvertTo-Json | Set-Content -LiteralPath $credentialFile

    az ad app federated-credential create `
      --id $githubDeploymentClientId `
      --parameters $credentialFile

    if ($LASTEXITCODE -ne 0) {
      throw "Unable to create federated credential for $repository."
    }
  }
  finally {
    Remove-Item -LiteralPath $credentialFile -ErrorAction SilentlyContinue
  }
}




