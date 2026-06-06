#!/bin/bash
cd "$(dirname "$0")/src"

docker compose --env-file .env up -d