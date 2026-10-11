# Znuny in Docker

## Features

- Multiple instances on one host (one compose project per instance)
- External database, or optional MariaDB container
- Separate containers for Apache (httpd) and the Znuny daemon (when only frontend-server is needed)
- Automatic install / update / upgrade of Znuny on container start (version is tracked in the table `ZDocker`)
- SSO (Kerberos; Apache accept Configuration) - Missing/Check?

## Prerequisites (server, not docker image)

- Docker with the compose plugin (`docker compose`, v2)

## Folder structure on the host

    ${ZNUNY_PERSISTENT_FOLDER}
    └── ${ZNUNY_INSTANCE}
        ├── znuny            # Znuny application files (/opt/znuny in the container)
        ├── persistent
        │   └── Config.pm    # seeded on first start, then yours to edit
        ├── log
        ├── article
        └── htdocs_custom

<details>
  <summary>Default</summary>

    /opt/znuny
    └── default
        ├── znuny
        ├── persistent
        │   └── Config.pm
        ├── log
        ├── article
        └── htdocs_custom
</details>

<br>
<br>

# How to install

## Variables (`src/.env`)
| Variable | Example | Description |
|----------|---------|-------------|
| ZNUNY_PERSISTENT_FOLDER | `/opt/znuny` | Host folder for all instance data |
| ZNUNY_VERSION         | latest<br>7.3.3  | Znuny version         |
| ZNUNY_CHECKSUM | `true` / `false` | Verify the sha256 of the download |
| ZNUNY_SIGNATURE | `true` / `false` | Verify the GPG signature of the download |
| ZNUNY_INSTANCE | `default`<br>`instance1` | optional: Suffix for Dockername. Can be empty |
| ZNUNY_NodeID | `1` | Znuny NodeID (1 is the Management-Server, [0-9]+ are Frontend-Servers) |
| ZNUNY_DEFAULT_INTERFACE | `agent` / `customer` | Where `/` redirects to |
| WEB_PORT         | 8080             | Apache external Port  |
| DB_HOST               | `znuny-db`         | Database IP-Adresse   |
| DB_PORT | `3306` | Database port |
| DB_NAME               | `znuny`            | Database name         |
| DB_USER               | `znuny`       | Database username     |
| MARIADB_VERSION | `latest`, `11.8` | MariaDB image tag (docker-compose-db.yml) |
| WEB_PORT | `80` | Apache external port |
| *_MEMLIMIT, *_CPUS | `2048m`, `2` | Resource limits of db / httpd / daemon |

Database settings are written into `Config.pm` **once**, when the file is created. Later changes of
`DB_*` / `ZNUNY_NodeID` have to be done in `${ZNUNY_PERSISTENT_FOLDER}/${ZNUNY_INSTANCE}/persistent/Config.pm`.

## Docker secrets (`src/secrets/*`)
| File | Example Content | Description |
|------|-----------------|-------------|
| db_root_password | !mysecretpwd! | Database root password (only with the MariaDB container) |
| db_password_${ZNUNY_INSTANCE} | !mysecretpwd! | Password of the database user |
| znuny_admin_password_${ZNUNY_INSTANCE} | !mysecretpwd! | Password of the Znuny admin `root@localhost` (set on first install) Password |

## Run Docker
### Run Docker default
```
docker compose up -d
```

### Run Docker with different instances
1. Create a copy from .env
2. Rename the copy f.e. to .env.instance1
3. Run
```
docker compose --env-file .env.instance1 up -d
docker compose --env-file .env.instance2 up -d
```

### Run Docker with Mariadb
Only currently works with one instance only
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