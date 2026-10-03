[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg-campfit-prod",
    [ValidateRange(1, 240)][int]$PeriodSeconds = 240
)

$ErrorActionPreference = "Stop"
$apps = @(
    "campfit-bff-mobile",
    "campfit-core-api",
    "campfit-adventure",
    "campfit-analytics"
)
$healthPaths = @("/alive", "/health", "/health/db")

foreach ($app in $apps) {
    $config = az containerapp show `
        --resource-group $ResourceGroup `
        --name $app `
        --output json | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read Container App '$app'."
    }

    $setArguments = @()
    for ($containerIndex = 0; $containerIndex -lt $config.properties.template.containers.Count; $containerIndex++) {
        $container = $config.properties.template.containers[$containerIndex]
        for ($probeIndex = 0; $probeIndex -lt $container.probes.Count; $probeIndex++) {
            $probe = $container.probes[$probeIndex]
            if ($probe.httpGet.path -in $healthPaths) {
                $setArguments += "properties.template.containers[$containerIndex].probes[$probeIndex].periodSeconds=$PeriodSeconds"
            }
        }
    }

    if ($setArguments.Count -eq 0) {
        Write-Warning "No matching HTTP health probes found for '$app'."
        continue
    }

    $arguments = @(
        "resource", "update",
        "--ids", $config.id,
        "--api-version", "2024-03-01",
        "--set"
    ) + $setArguments + @("--only-show-errors", "--output", "none")
    & az @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to update health probes for '$app'."
    }

    Write-Host "Updated $($setArguments.Count) probe(s) on $app to $PeriodSeconds seconds."
}
