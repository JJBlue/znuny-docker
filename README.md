# Znuny in Docker

## Features

- Multiple instances on one host (one compose project per instance)
- External database, or optional MariaDB container
- Separate containers for Apache (httpd) and the Znuny daemon (when only frontend-server is needed)
- Automatic install / update / upgrade of Znuny on container start (version is tracked in the table `ZDocker`)
- Trust own CA-Certificates
- SSO (Kerberos; Apache accept Configuration) - Missing/Check?

## Prerequisites (server, not docker image)

- Docker with the compose plugin (`docker compose`, v2)

## Folder structure on the host

    ${ZNUNY_PERSISTENT_FOLDER}
      ├── os                    # Debian Volumes
      │   └── ca-certificates   # /usr/local/share/ca-certificates
      └── instances             # Znuny Volumes
          └── ${ZNUNY_INSTANCE}
              ├── app                 # Znuny application files (/opt/znuny in the container)
              ├── persistent
              │   └── Config.pm       # seeded on first start, then yours to edit
              ├── log
              ├── article
              ├── htdocs_custom
              └── smime
                ├── certs
                └── private

<details>
  <summary>Default</summary>

    /opt/znuny
    ├── os
    │   └── ca-certificates
    └── default
        └── znuny
            ├── app
            ├── persistent
            │   └── Config.pm
            ├── log
            ├── article
            ├── htdocs_custom
            └── smime
              ├── certs
              └── private
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

## Run

```
./install.sh                       # httpd + daemon, external database
./install.sh --with-db             # + MariaDB container
./install.sh --no-daemon           # httpd only
./install.sh --build               # rebuild images (after changing ZNUNY_VERSION)
```

Follow the first installation (takes a few minutes):

```
docker logs -f znuny_httpd_default
```

### Different instances

1. Copy `src/.env` to f.e. `src/.env.instance1`
2. Change at least `ZNUNY_INSTANCE`, `WEB_PORT` (and `ZNUNY_NodeID` for a clustered setup)
3. Create the secrets for the instance (or let `install.sh` do it)
4. Run

```
./install.sh --env-file .env.instance1
./install.sh --env-file .env.instance2
```

### Without install.sh

```
cd src
docker compose --env-file .env -f docker-compose.yml -f docker-compose-daemon.yml [-f docker-compose-db.yml] up -d
```

`docker-compose-daemon.yml` and `docker-compose-db.yml` are overrides: they only work together with `docker-compose.yml`.

### Run Docker with Mariadb
Only currently works with one instance only
```
docker compose -f docker-compose.yml -f docker-compose-db.yml up -d
```

## Running console commands

Directly from the host:

```
docker exec -u znuny znuny_httpd_default /opt/znuny/bin/znuny.Console.pl
```

Or from an interactive shell inside the container:

```
docker exec -ti -u znuny znuny_httpd_default /bin/bash
./bin/znuny.Console.pl
```

## Starting / stopping the daemon

The daemon runs in its own container and is supervised by a watchdog:

```
docker exec -u znuny znuny_daemon_default /opt/znuny/bin/znuny.Daemon.pl status
docker exec -u znuny znuny_daemon_default /opt/znuny/bin/znuny.Daemon.pl stop    # the watchdog starts it again
docker restart znuny_daemon_default
```

# Updates

Change `ZNUNY_VERSION` and run `./install.sh --build`. On start the httpd container compares the version in the
database (`ZDocker`) with the image and runs the migration. Stop the daemon container first
(`docker stop znuny_daemon_<instance>`) and make a database backup. The following is refused on purpose:

- downgrades
- skipping a minor version (7.0 -> 7.2): upgrade step by step