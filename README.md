# How to install

## Prerequirenments
- Web Server for redirection (optional: Server Certificate)
- Postfix
- Docker

## Docker Variables (.env)
| Variable | Example | Description |
|----------|--------|-------------|
| ZNUNY_VERSION         | latest<br>7.3.3  | Znuny version         |
| CONTAINER_NAME_SUFFIX | <br>instance1    | optional: Suffix for Dockername. Can be empty |
| external_port         | 8080             | Apache external Port  |
| DB_HOST               | znuny-db         | Database IP-Adresse   |
| DB_NAME               | znuny            | Database Name         |
| DB_USER               | znuny_user       | Database Username     |
| DB_USER_PASS          | !mysecretpwd!    | Database Password     |

## Run Docker
### Run Docker default
```
docker compose up -d
```

### Run Docker with different instances
1. Create a copy from .env
2. Rename the copy f.e. to .env.instance1
3. Run (TODO -p instance1 not used)
```
docker compose --env-file .env.instance1 up -d
docker compose --env-file .env.instance2 up -d
```

### Run Docker with Mariadb
```
docker compose -f docker-compose.yml -f docker-compose-db.yml up -d
```

# Znuny Commandline

## Running console commands
Directly from the host:
```
docker exec -u znuny znuny_httpd /opt/znuny/bin/znuny.Console.pl
```
_znuny_httpd_ - container name or id<br><br>
Or from an interactive shell inside the container:
```
docker exec -ti -u znuny znuny_httpd /bin/bash
./bin/znuny.Console.pl
```

## Starting / stopping the daemon:
```
docker exec -u znuny znuny_httpd /opt/znuny/bin/otrs.Daemon.pl stop
docker exec -u znuny znuny_httpd /opt/znuny/bin/otrs.Daemon.pl start
```