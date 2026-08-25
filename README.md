# DHA Disease Registry

Local development scaffold for a disease registry on licensed InterSystems IRIS for Health. Docker Compose starts IRIS for Health and a matching Web Gateway, creates the `DISEASEREGISTRY` namespace and database, and imports all ObjectScript classes under `src/`.

## Prerequisites

- Docker Desktop with Docker Compose v2
- Git
- Visual Studio Code
- The recommended VS Code extensions (VS Code will offer to install them)
- Access to the InterSystems Container Registry
- A valid IRIS for Health license key

## Start the instance

Authenticate to the InterSystems Container Registry if needed, then place your license at `license/iris.key`:

```bash
docker login containers.intersystems.com
./bin/start
```

The first start pulls the IRIS for Health image and can take several minutes. Follow bootstrap output with:

```bash
./bin/logs
```

When the logs show `Disease Registry bootstrap complete`, open:

- Management Portal: <http://localhost:52773/csp/sys/UtilHome.csp>
- IRIS terminal: `./bin/terminal`
- Namespace: `DISEASEREGISTRY`

The initial development credentials are `_SYSTEM` / `SYS`; IRIS may require a password change on first use. VS Code deliberately does not store the password—enter the current password when the ObjectScript extension prompts and allow your OS keychain to save it. The included Web Gateway connection uses the initial `CSPSystem` credentials and must be updated if that password changes.

## Development workflow

- Put ObjectScript classes in `src/<package path>/ClassName.cls`.
- Put unit tests in `tests/<package path>/TestName.cls`.
- The container imports `src/` each time it starts.
- With the ObjectScript extension connected, saving a `.cls` file compiles it directly into `DISEASEREGISTRY`.
- Run the smoke test with `./bin/test`.

Useful commands:

```bash
./bin/start       # Build and start IRIS
./bin/logs        # Follow IRIS logs
./bin/terminal    # Open an ObjectScript shell in DISEASEREGISTRY
./bin/test        # Import and run tests
./bin/stop        # Stop the container, preserving data
docker compose down -v  # Delete the container AND all local IRIS data
```

## Persistence and code injection

IRIS instance data and the application database live in the Docker named volume `disease-registry-iris-data`; Web Gateway state uses `disease-registry-webgateway-data`. The license is mounted read-only and excluded from Git. The `src/` and `tests/` directories are mounted read-only into the running container. The image also contains a snapshot of both directories, so it remains runnable without the development bind mounts if Compose is adjusted later.

The bootstrap flow is:

1. IRIS starts using durable `%SYS` at `/durable/config`.
2. `iris-main --after` executes `docker/bootstrap.sh`.
3. `docker/App.Installer.cls` creates the database and namespace when absent.
4. The installer recursively imports and compiles `src/`.

## Configuration

Defaults can be overridden by copying `.env.example` to `.env`. Keep `IRIS_IMAGE` and `WEBGATEWAY_IMAGE` on matching release tags, and pin both to an explicit version before using this outside local development.

This scaffold uses licensed IRIS for Health with development-oriented authentication and HTTP-only Web Gateway settings. Review licensing, credentials, TLS, auditing, data retention, backup, and healthcare privacy requirements before storing real patient data or deploying beyond a developer workstation.
