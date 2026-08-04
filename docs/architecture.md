# Architecture

Public ingress:

- `campfit-bff-mobile`

Internal services:

- `campfit-core-api`
- `campfit-adventure`
- `campfit-analytics`

Each service owns its own deployment lifecycle, Dockerfile, workflow, and PostgreSQL database.
