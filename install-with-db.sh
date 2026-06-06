#!/bin/bash
cd "$(dirname "$0")/src"

docker compose --env-file .env -f docker-compose.yml -f docker-compose-db.yml up -d