# Architecture

Public ingress:

- `campfit-bff-mobile`

Internal services:

- `campfit-core-api`
- `campfit-adventure`
- `analytics-read-service`

Each service owns its own deployment lifecycle, Dockerfile, workflow, and PostgreSQL database.
