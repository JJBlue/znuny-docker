#!/bin/bash
cd "$(dirname "$0")/src"

# TODO Questions
# - Instance-Name
# - With-Database?
# - Instance-Number (0 = with daemon; ... != with deamon)

docker compose --env-file .env up -d
# docker compose --env-file .env -f docker-compose.yml -f docker-compose-db.yml up -d