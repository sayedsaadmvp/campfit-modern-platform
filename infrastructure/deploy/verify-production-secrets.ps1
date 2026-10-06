[CmdletBinding()]
param(
    [string]$KeyVaultName = 'kv-campfit-prod-cb5afb'
)

# Azure CLI failures are checked explicitly with LASTEXITCODE for compatibility
# with Windows PowerShell native stderr handling.
$ErrorActionPreference = 'Continue'

az account show --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not authenticated. Run az login first.'
}

$availableSecrets = @(
    az keyvault secret list `
        --vault-name $KeyVaultName `
        --query '[?attributes.enabled].name' `
        --output tsv
)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list enabled secrets in Key Vault '$KeyVaultName'."
}

$secretSet = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($secretName in $availableSecrets) {
    if (-not [string]::IsNullOrWhiteSpace($secretName)) {
        [void]$secretSet.Add($secretName.Trim())
    }
}

$missing = [System.Collections.Generic.List[string]]::new()

function Require-Secret {
    param([Parameter(Mandatory)][string]$Name)

    if (-not $secretSet.Contains($Name)) {
        $missing.Add($Name)
    }
}

function Require-AnySecret {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        if ($secretSet.Contains($name)) {
            return
        }
    }
    $missing.Add("$Label (one of: $($Names -join ', '))")
}

@(
    'CORE-POSTGRES-HOST',
    'CORE-POSTGRES-PORT',
    'CORE-POSTGRES-DATABASE',
    'CORE-POSTGRES-USERNAME',
    'CORE-POSTGRES-PASSWORD',
    'ADVENTURE-POSTGRES-HOST',
    'ADVENTURE-POSTGRES-PORT',
    'ADVENTURE-POSTGRES-DATABASE',
    'ADVENTURE-POSTGRES-USERNAME',
    'ADVENTURE-POSTGRES-PASSWORD',
    'ANALYTICS-POSTGRES-HOST',
    'ANALYTICS-POSTGRES-PORT',
    'ANALYTICS-POSTGRES-DATABASE',
    'ANALYTICS-CORE-DATABASE',
    'ANALYTICS-ADVENTURE-DATABASE',
    'ANALYTICS-POSTGRES-USERNAME',
    'ANALYTICS-POSTGRES-PASSWORD',
    'FIREBASE-PROJECT-ID'
) | ForEach-Object { Require-Secret $_ }

Require-AnySecret -Label 'Firebase service account' -Names @(
    'FIREBASE-SERVICE-ACCOUNT-BASE64',
    'FIREBASE-SERVICE-ACCOUNT-JSON'
)
Require-AnySecret -Label 'Core Application Insights' -Names @(
    'CORE-APPINSIGHTS-CONNECTION-STRING',
    'APPINSIGHTS-CONNECTION-STRING'
)
Require-AnySecret -Label 'Adventure Application Insights' -Names @(
    'ADVENTURE-APPINSIGHTS-CONNECTION-STRING',
    'APPINSIGHTS-CONNECTION-STRING'
)
Require-AnySecret -Label 'BFF Application Insights' -Names @(
    'BFF-APPINSIGHTS-CONNECTION-STRING',
    'APPINSIGHTS-CONNECTION-STRING'
)
Require-AnySecret -Label 'Analytics Application Insights' -Names @(
    'ANALYTICS-APPINSIGHTS-CONNECTION-STRING',
    'APPINSIGHTS-CONNECTION-STRING'
)

if ($missing.Count -gt 0) {
    Write-Error "Missing or disabled production Key Vault requirements:`n - $($missing -join "`n - ")"
    exit 1
}

Write-Host "All required production secrets are enabled in Key Vault '$KeyVaultName'. Values were not read."
Write-Host 'Fitbit, Garmin, and Stripe secrets are feature-specific and should be validated when those integrations are enabled.'
