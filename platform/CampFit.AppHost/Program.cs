using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

var builder = DistributedApplication.CreateBuilder(args);

builder.Services.AddDataProtection().UseEphemeralDataProtectionProvider();
builder.Services.AddLogging(logging =>
{
    logging.ClearProviders();
    logging.AddConsole();
});

var mode = builder.Configuration["DeploymentMode"] ?? "Local";
var isLocal = mode.Equals("Local", StringComparison.OrdinalIgnoreCase);

if (isLocal)
{
    var postgresPassword = builder.AddParameter("postgres-password", secret: true);
    var postgres = builder.AddPostgres("campfit-postgres", password: postgresPassword)
        .WithBindMount("../../docker/postgres/init", "/docker-entrypoint-initdb.d")
        .WithDataVolume();

    var coreDb = postgres.AddDatabase("campfit-core-db", "campfit_core");
    var adventureDb = postgres.AddDatabase("campfit-adventure-db", "campfit_adventure");

    var coreApi = builder.AddProject<Projects.CampFit_Core_Api>("campfit-core-api")
        .WithReference(coreDb)
        .WithEnvironment("APP_ENV", "local")
        .WithEnvironment("ENVIRONMENT", "Development")
        .WithEnvironment("ASPNETCORE_ENVIRONMENT", "Development")
        .WaitFor(postgres)
        .WithHttpHealthCheck("/health");

    var adventureApi = builder.AddProject<Projects.CampFit_Adventure_Api>("campfit-adventure")
        .WithReference(adventureDb)
        .WithEnvironment("APP_ENV", "local")
        .WithEnvironment("ENVIRONMENT", "Development")
        .WithEnvironment("ASPNETCORE_ENVIRONMENT", "Development")
        .WaitFor(postgres)
        .WithHttpHealthCheck("/health");

    var analytics = builder.AddDockerfile("analytics-read-service", "../../services/analytics-read-service")
        .WithHttpEndpoint(targetPort: 8000)
        .WithReference(postgres)
        .WithEnvironment("APP_ENV", "local")
        .WithEnvironment("ENVIRONMENT", "local")
        .WithEnvironment("POSTGRES_HOST", postgres.GetEndpoint("tcp").Property(EndpointProperty.Host))
        .WithEnvironment("POSTGRES_PORT", postgres.GetEndpoint("tcp").Property(EndpointProperty.Port))
        .WithEnvironment("POSTGRES_DB", "campfit_analytics")
        .WithEnvironment("POSTGRES_USER", "analytics_user")
        .WithEnvironment("POSTGRES_PASSWORD", "Test123")
        .WithEnvironment("POSTGRES_SSLMODE", "disable")
        .WaitFor(postgres)
        .WithHttpHealthCheck("/health/db");

    builder.AddProject<Projects.CampFit_Bff_Mobile>("campfit-bff-mobile")
        .WithReference(coreApi)
        .WithReference(adventureApi)
        .WithEnvironment("APP_ENV", "local")
        .WithEnvironment("ENVIRONMENT", "Development")
        .WithEnvironment("ASPNETCORE_ENVIRONMENT", "Development")
        .WithEnvironment("Services__CoreApi__BaseUrl", coreApi.GetEndpoint("http"))
        .WithEnvironment("Services__AdventureApi__BaseUrl", adventureApi.GetEndpoint("http"))
        .WithEnvironment("Services__AnalyticsApi__BaseUrl", analytics.GetEndpoint("http"))
        .WithEnvironment("AllowedCorsOrigins__0", "http://localhost:7000")
        .WaitFor(coreApi)
        .WaitFor(adventureApi)
        .WaitFor(analytics)
        .WithExternalHttpEndpoints()
        .WithHttpHealthCheck("/health");
}
else
{
    var coreApi = builder.AddProject<Projects.CampFit_Core_Api>("campfit-core-api")
        .WithEnvironment("APP_ENV", "production")
        .WithEnvironment("ENVIRONMENT", "Production")
        .WithEnvironment("KEY_VAULT_URI", builder.Configuration["AZURE_KEY_VAULT_URI"] ?? builder.Configuration["KEY_VAULT_URI"] ?? string.Empty)
        .WithEnvironment("USER_ASSIGNED_IDENTITY_CLIENT_ID", builder.Configuration["AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID"] ?? builder.Configuration["USER_ASSIGNED_IDENTITY_CLIENT_ID"] ?? string.Empty)
        .WithHttpHealthCheck("/health");

    var adventureApi = builder.AddProject<Projects.CampFit_Adventure_Api>("campfit-adventure")
        .WithEnvironment("APP_ENV", "production")
        .WithEnvironment("ENVIRONMENT", "Production")
        .WithEnvironment("KEY_VAULT_URI", builder.Configuration["AZURE_KEY_VAULT_URI"] ?? builder.Configuration["KEY_VAULT_URI"] ?? string.Empty)
        .WithEnvironment("USER_ASSIGNED_IDENTITY_CLIENT_ID", builder.Configuration["AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID"] ?? builder.Configuration["USER_ASSIGNED_IDENTITY_CLIENT_ID"] ?? string.Empty)
        .WithHttpHealthCheck("/health");

    var analytics = builder.AddDockerfile("analytics-read-service", "../../services/analytics-read-service")
        .WithHttpEndpoint(targetPort: 8000)
        .WithEnvironment("APP_ENV", "production")
        .WithEnvironment("KEY_VAULT_NAME", builder.Configuration["AZURE_KEY_VAULT_NAME"] ?? builder.Configuration["KEY_VAULT_NAME"] ?? string.Empty)
        .WithEnvironment("USER_ASSIGNED_IDENTITY_CLIENT_ID", builder.Configuration["AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID"] ?? builder.Configuration["USER_ASSIGNED_IDENTITY_CLIENT_ID"] ?? string.Empty)
        .WithHttpHealthCheck("/health/db");

    builder.AddProject<Projects.CampFit_Bff_Mobile>("campfit-bff-mobile")
        .WithReference(coreApi)
        .WithReference(adventureApi)
        .WithEnvironment("APP_ENV", "production")
        .WithEnvironment("ENVIRONMENT", "Production")
        .WithEnvironment("KEY_VAULT_URI", builder.Configuration["AZURE_KEY_VAULT_URI"] ?? builder.Configuration["KEY_VAULT_URI"] ?? string.Empty)
        .WithEnvironment("USER_ASSIGNED_IDENTITY_CLIENT_ID", builder.Configuration["AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID"] ?? builder.Configuration["USER_ASSIGNED_IDENTITY_CLIENT_ID"] ?? string.Empty)
        .WithEnvironment("Services__AnalyticsApi__BaseUrl", builder.Configuration["Services__AnalyticsApi__BaseUrl"] ?? "http://analytics-read-service:8000")
        .WithExternalHttpEndpoints()
        .WithHttpHealthCheck("/health");
}

builder.Build().Run();
