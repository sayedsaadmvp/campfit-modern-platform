# CampFit AppHost

This is the project-based Aspire AppHost for local orchestration and topology verification.

- `DeploymentMode=Local` starts PostgreSQL and runs the .NET services plus the analytics Dockerfile locally.
- `DeploymentMode=Production` avoids provisioning PostgreSQL and only applies non-secret bootstrap environment variables expected by Azure Container Apps.

API Management is intentionally omitted in this phase. It will later sit in front of `campfit-bff-mobile`.
