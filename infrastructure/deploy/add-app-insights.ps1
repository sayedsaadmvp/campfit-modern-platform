$url = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/components/$appInsightsName" + "?api-version=2020-02-02"

write-host "Creating Application Insights resource '$appInsightsName' in resource group '$resourceGroup'... URL: $url "    

$workspaceResourceId = az monitor log-analytics workspace show `
    --resource-group $resourceGroup `
    --workspace-name $logAnalyticsName `
    --query id `
    --output tsv

$body = @{
    location = $location
    kind = "web"
    properties = @{
        Application_Type = "web"
        WorkspaceResourceId = $workspaceResourceId
    }
} 
$body_json = $body | ConvertTo-Json -Depth 5
write-host "Request body: $body_json"
$body_json | Out-File appinsights.json -Encoding utf8

az rest `
    --method put `
    --url $url `
    --headers "Content-Type=application/json" `
    --body "@appinsights.json"

$appInsightsConnectionString = az rest `
    --method GET `
    --url $url `
    --query "properties.ConnectionString" `
    -o tsv

Write-Host $appInsightsConnectionString