#!/usr/bin/env bash
set -euo pipefail
dotnet restore CampFit.Modern.slnx
dotnet build CampFit.Modern.slnx --configuration Release --no-restore
dotnet test CampFit.Modern.slnx --configuration Release --no-build
docker compose config --quiet
