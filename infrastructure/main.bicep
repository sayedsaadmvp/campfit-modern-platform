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

@description('Name of the existing Foundry user-assigned identity used by Analytics.')
param analyticsFoundryIdentityName string = 'id-campfit-foundry-prod'

@description('Existing production PostgreSQL Flexible Server host name.')
param postgresHost string

param coreAppName string = 'campfit-core-api'
param adventureAppName string = 'campfit-adventure'
param bffAppName string = 'campfit-bff-mobile'
param analyticsAppName string = 'campfit-analytics'

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

@description('Minimum replicas for Adventure and Analytics. These non-entry-point services may scale to zero.')
@minValue(0)
param minReplicas int = 0

@description('Minimum replicas for Core API. Keep at least one warm for database-backed requests and background processing.')
@minValue(0)
param coreMinReplicas int = 1

@description('Minimum replicas for the public mobile BFF. Keep at least one warm to avoid user-facing cold starts.')
@minValue(0)
param bffMinReplicas int = 1

@minValue(1)
param maxReplicas int = 3

@description('Azure Container Apps health-probe interval. The platform maximum is 240 seconds.')
@minValue(1)
@maxValue(240)
param healthProbePeriodSeconds int = 240

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

resource analyticsFoundryIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: analyticsFoundryIdentityName
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
    periodSeconds: healthProbePeriodSeconds
  }
  {
    type: 'Readiness'
    httpGet: {
      path: '/health'
      port: 8080
      scheme: 'HTTP'
    }
    initialDelaySeconds: 10
    periodSeconds: healthProbePeriodSeconds
    timeoutSeconds: 5
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
    periodSeconds: healthProbePeriodSeconds
  }
  {
    type: 'Readiness'
    httpGet: {
      path: '/health/db'
      port: 8000
      scheme: 'HTTP'
    }
    initialDelaySeconds: 10
    periodSeconds: healthProbePeriodSeconds
    timeoutSeconds: 5
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
          name: 'campfit-core-api'
          image: coreImage
          env: concat(commonEnvironment, [
            {
              name: 'GIT_SHA'
              value: last(split(coreImage, ':'))
            }
            { name: 'OTEL_SERVICE_NAME', value: 'campfit-core-api' }
            { name: 'CoreDatabase__SslMode', value: 'Require' }
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
        minReplicas: coreMinReplicas
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
            { name: 'AdventureDatabase__SslMode', value: 'Require' }
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
      '${analyticsFoundryIdentity.id}': {}
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
          name: 'campfit-analytics'
          image: analyticsImage
          env: concat(commonEnvironment, [
            {
              name: 'GIT_SHA'
              value: last(split(analyticsImage, ':'))
            }
            { name: 'OTEL_SERVICE_NAME', value: 'campfit-analytics' }
            { name: 'POSTGRES_SSLMODE', value: 'require' }
            { name: 'TELEMETRY_BODY_CAPTURE_ENABLED', value: 'true' }
            { name: 'TELEMETRY_CAPTURE_FULL_BODIES', value: string(telemetryCaptureFullBodies) }
            { name: 'TELEMETRY_BODY_PREVIEW_CHARS', value: string(telemetryBodyPreviewCharacters) }
            { name: 'TELEMETRY_FULL_BODY_MAX_CHARS', value: '65536' }
            { name: 'APP_PORT', value: '8000' }
            { name: 'FIREBASE_PROJECT_ID', value: 'campfitnesschallenge' }
            { name: 'DATABASE_AUTH_MODE', value: 'password' }
            { name: 'DATABASE_POOL_SIZE', value: '5' }
            { name: 'DATABASE_MAX_OVERFLOW', value: '5' }
            { name: 'FOUNDRY_PROJECT_ENDPOINT', value: 'https://foundry-campfit.services.ai.azure.com/api/projects/campfit-analytics' }
            { name: 'AI_EXECUTION_MODE', value: 'agent_reference' }
            { name: 'AI_PRIMARY_PROVIDER', value: 'FOUNDRY' }
            { name: 'AI_FALLBACK_ENABLED', value: 'true' }
            { name: 'AI_FALLBACK_PROVIDER', value: 'FOUNDRY' }
            { name: 'AI_MODEL_TIMEOUT_SECONDS', value: '20' }
            { name: 'ENABLE_DOCS', value: 'false' }
            { name: 'LOG_LEVEL', value: 'INFO' }
            { name: 'TEST_SQL_VIEW_LIMIT', value: '10' }
            { name: 'AI_PRIMARY_AGENT_NAME', value: 'CampFit-Primary-Analytics' }
            { name: 'AI_PRIMARY_AGENT_VERSION', value: '13' }
            { name: 'AI_FALLBACK_AGENT_NAME', value: 'campfit-fallback-analytics' }
            { name: 'AI_FALLBACK_AGENT_VERSION', value: '9' }
            { name: 'FOUNDRY_USER_ASSIGNED_IDENTITY_CLIENT_ID', value: analyticsFoundryIdentity.properties.clientId }
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
    core
    adventure
    analytics
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
              value: 'http://${coreAppName}'
            }
            {
              name: 'Services__AdventureApi__BaseUrl'
              value: 'http://${adventureAppName}'
            }
            {
              name: 'Services__AnalyticsApi__BaseUrl'
              value: 'http://${analyticsAppName}'
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
        minReplicas: bffMinReplicas
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
