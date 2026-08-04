targetScope = 'resourceGroup'

@description('Azure region containing the existing Container Apps environment.')
param location string = resourceGroup().location

@description('Name of the existing Azure Container Apps environment.')
param containerAppsEnvironmentName string

@description('Name of the existing Azure Container Registry.')
param containerRegistryName string

@description('Name of the existing Azure Key Vault.')
param keyVaultName string

@description('Name of the existing user-assigned managed identity.')
param userAssignedIdentityName string

@description('Existing production PostgreSQL Flexible Server host name.')
param postgresHost string

param coreAppName string = 'campfit-core-api'
param adventureAppName string = 'campfit-adventure'
param bffAppName string = 'campfit-bff-mobile'
param analyticsAppName string = 'analytics-read-service'

@description('Capture full redacted text request/response bodies. Keep false for normal production traffic.')
param telemetryCaptureFullBodies bool = false

@minValue(1)
@maxValue(4096)
param telemetryBodyPreviewCharacters int = 200

@description('Immutable, fully qualified image references. Use Git commit SHA tags.')
param coreImage string
param adventureImage string
param bffImage string
param analyticsImage string

@description('Allowed browser origin for the public BFF. Native mobile clients are not governed by browser CORS.')
param bffAllowedCorsOrigin string = 'https://app.campfit.com'

@minValue(0)
param minReplicas int = 1

@minValue(1)
param maxReplicas int = 3

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: containerAppsEnvironmentName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

var keyVaultUri = vault.properties.vaultUri
var runtimeIdentityId = runtimeIdentity.id
var runtimeIdentityClientId = runtimeIdentity.properties.clientId
var registryServer = registry.properties.loginServer
var commonEnvironment = [
  {
    name: 'APP_ENV'
    value: 'production'
  }
  {
    name: 'ENVIRONMENT'
    value: 'Production'
  }
  {
    name: 'ASPNETCORE_ENVIRONMENT'
    value: 'Production'
  }
  {
    name: 'KEY_VAULT_URI'
    value: keyVaultUri
  }
  {
    name: 'KEY_VAULT_NAME'
    value: keyVaultName
  }
  {
    name: 'USER_ASSIGNED_IDENTITY_CLIENT_ID'
    value: runtimeIdentityClientId
  }
  {
    name: 'AZURE_CLIENT_ID'
    value: runtimeIdentityClientId
  }
  {
    name: 'AZURE_POSTGRES_HOST'
    value: postgresHost
  }
]
var dotnetProbes = [
  {
    type: 'Liveness'
    httpGet: {
      path: '/alive'
      port: 8080
      scheme: 'HTTP'
    }
    initialDelaySeconds: 10
    periodSeconds: 20
  }
  {
    type: 'Readiness'
    httpGet: {
      path: '/health'
      port: 8080
      scheme: 'HTTP'
    }
    initialDelaySeconds: 10
    periodSeconds: 20
  }
]
var analyticsProbes = [
  {
    type: 'Liveness'
    httpGet: {
      path: '/alive'
      port: 8000
      scheme: 'HTTP'
    }
    initialDelaySeconds: 10
    periodSeconds: 20
  }
  {
    type: 'Readiness'
    httpGet: {
      path: '/health/db'
      port: 8000
      scheme: 'HTTP'
    }
    initialDelaySeconds: 10
    periodSeconds: 20
  }
]

resource core 'Microsoft.App/containerApps@2024-03-01' = {
  name: coreAppName
  location: location
  dependsOn: [
    acrPullRole
    keyVaultSecretsUserRole
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryServer
          identity: runtimeIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'campfit-core-api'
          image: coreImage
          env: concat(commonEnvironment, [
            {
              name: 'GIT_SHA'
              value: last(split(coreImage, ':'))
            }
            { name: 'OTEL_SERVICE_NAME', value: 'campfit-core-api' }
            { name: 'Telemetry__BodyCapture__Enabled', value: 'true' }
            { name: 'Telemetry__BodyCapture__CaptureFullBodies', value: string(telemetryCaptureFullBodies) }
            { name: 'Telemetry__BodyCapture__PreviewCharacters', value: string(telemetryBodyPreviewCharacters) }
            { name: 'Telemetry__BodyCapture__FullBodyMaxCharacters', value: '65536' }
          ])
          probes: dotnetProbes
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

resource adventure 'Microsoft.App/containerApps@2024-03-01' = {
  name: adventureAppName
  location: location
  dependsOn: [
    acrPullRole
    keyVaultSecretsUserRole
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryServer
          identity: runtimeIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'campfit-adventure'
          image: adventureImage
          env: concat(commonEnvironment, [
            {
              name: 'GIT_SHA'
              value: last(split(adventureImage, ':'))
            }
            { name: 'OTEL_SERVICE_NAME', value: 'campfit-adventure' }
            { name: 'Telemetry__BodyCapture__Enabled', value: 'true' }
            { name: 'Telemetry__BodyCapture__CaptureFullBodies', value: string(telemetryCaptureFullBodies) }
            { name: 'Telemetry__BodyCapture__PreviewCharacters', value: string(telemetryBodyPreviewCharacters) }
            { name: 'Telemetry__BodyCapture__FullBodyMaxCharacters', value: '65536' }
          ])
          probes: dotnetProbes
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

resource analytics 'Microsoft.App/containerApps@2024-03-01' = {
  name: analyticsAppName
  location: location
  dependsOn: [
    acrPullRole
    keyVaultSecretsUserRole
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 8000
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryServer
          identity: runtimeIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'analytics-read-service'
          image: analyticsImage
          env: concat(commonEnvironment, [
            {
              name: 'GIT_SHA'
              value: last(split(analyticsImage, ':'))
            }
            { name: 'OTEL_SERVICE_NAME', value: 'analytics-read-service' }
            { name: 'TELEMETRY_BODY_CAPTURE_ENABLED', value: 'true' }
            { name: 'TELEMETRY_CAPTURE_FULL_BODIES', value: string(telemetryCaptureFullBodies) }
            { name: 'TELEMETRY_BODY_PREVIEW_CHARS', value: string(telemetryBodyPreviewCharacters) }
            { name: 'TELEMETRY_FULL_BODY_MAX_CHARS', value: '65536' }
          ])
          probes: analyticsProbes
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

resource bff 'Microsoft.App/containerApps@2024-03-01' = {
  name: bffAppName
  location: location
  dependsOn: [
    acrPullRole
    keyVaultSecretsUserRole
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryServer
          identity: runtimeIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'campfit-bff-mobile'
          image: bffImage
          env: concat(commonEnvironment, [
            {
              name: 'Services__CoreApi__BaseUrl'
              value: 'https://${core.properties.configuration.ingress.fqdn}'
            }
            {
              name: 'Services__AdventureApi__BaseUrl'
              value: 'https://${adventure.properties.configuration.ingress.fqdn}'
            }
            {
              name: 'Services__AnalyticsApi__BaseUrl'
              value: 'https://${analytics.properties.configuration.ingress.fqdn}'
            }
            {
              name: 'AllowedCorsOrigins__0'
              value: bffAllowedCorsOrigin
            }
            {
              name: 'GIT_SHA'
              value: last(split(bffImage, ':'))
            }
            { name: 'OTEL_SERVICE_NAME', value: 'campfit-bff-mobile' }
            { name: 'Telemetry__BodyCapture__Enabled', value: 'true' }
            { name: 'Telemetry__BodyCapture__CaptureFullBodies', value: string(telemetryCaptureFullBodies) }
            { name: 'Telemetry__BodyCapture__PreviewCharacters', value: string(telemetryBodyPreviewCharacters) }
            { name: 'Telemetry__BodyCapture__FullBodyMaxCharacters', value: '65536' }
          ])
          probes: dotnetProbes
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

var acrPullRoleDefinitionId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var keyVaultSecretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, runtimeIdentity.id, acrPullRoleDefinitionId)
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleDefinitionId)
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, runtimeIdentity.id, keyVaultSecretsUserRoleDefinitionId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleDefinitionId)
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output bffUrl string = 'https://${bff.properties.configuration.ingress.fqdn}'
output coreInternalFqdn string = core.properties.configuration.ingress.fqdn
output adventureInternalFqdn string = adventure.properties.configuration.ingress.fqdn
output analyticsInternalFqdn string = analytics.properties.configuration.ingress.fqdn
output managedIdentityClientId string = runtimeIdentityClientId
