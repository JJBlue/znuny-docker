#!/bin/bash
cd "$(dirname "$0")/src"

docker compose --profile build-only build
docker compose --env-file .env up -d