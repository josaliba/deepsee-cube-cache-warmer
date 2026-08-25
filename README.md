# DHA Disease Registry

Local development scaffold for a disease registry on licensed InterSystems IRIS for Health. Docker Compose starts IRIS for Health and a matching Web Gateway, creates the interoperability-enabled `DISEASEREGISTRY` namespace and database, and imports all ObjectScript classes under `src/`. Interoperability enablement supplies the mappings and portal registration required for Analytics.

Bootstrap also upgrades an existing `DISEASEREGISTRY` volume that was created
without interoperability support; deleting the Docker volume is not required.

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

The local development credentials are `_SYSTEM` / `SYS`. Bootstrap clears the first-login password-change requirement for `_SYSTEM` and `SuperUser`, so their password remains `SYS`. VS Code deliberately does not store the password—enter `SYS` when the ObjectScript extension prompts and allow your OS keychain to save it. The included Web Gateway connection uses the initial `CSPSystem` credentials and must be updated if that password changes.

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

## Business Intelligence cubes

The project includes two synchronized IRIS BI cubes:

| Persistent source | DSTIME | Logical cube |
| --- | --- | --- |
| `DiseaseRegistry.Model.Patient` | `AUTO` | `DiseaseRegistryPatients` |
| `DiseaseRegistry.Model.Diagnosis` | `AUTO` | `DiseaseRegistryDiagnoses` |

Both source classes use a five-second `DSINTERVAL`. Inserts, updates, and deletes
are therefore recorded in `^OBJ.DSTIME` and can be applied with cube
synchronization rather than a full rebuild.

### Load demo data and build

The analytics demo is opt-in. It is never run during container bootstrap. From
the `DISEASEREGISTRY` terminal, generate deterministic sample data, build both
cubes, create two saved pivots, and warm their queries:

```objectscript
set sc=##class(DiseaseRegistry.Util.Analytics).SetupDemo(50,500,1,1)
do $SYSTEM.OBJ.DisplayError(sc)
```

The third argument resets only `DiseaseRegistry.Model.Patient` and
`DiseaseRegistry.Model.Diagnosis`. Do not use reset mode after replacing the demo
model with real registry data.

The saved pivots are created under the BI user-library folder `Disease Registry`:

- `Patients by Status.pivot`
- `Diagnoses by Group.pivot`

### Exercise cube synchronization

Generate patient and diagnosis changes:

```objectscript
set sc=##class(DiseaseRegistry.Util.Analytics).MakeChanges(10,6,2,3)
do $SYSTEM.OBJ.DisplayError(sc)
```

Synchronize both cubes and warm their saved queries:

```objectscript
set sc=##class(DiseaseRegistry.Util.Analytics).SynchronizeAll(1)
do $SYSTEM.OBJ.DisplayError(sc)
```

`SynchronizeAll()` reports the number of patient and diagnosis facts updated.
You can inspect `^OBJ.DSTIME` between the two calls to see the pending source IDs.

### Configure automatic cache warming

The generated `DiseaseRegistry.CubeRegistry` is activated during bootstrap. It
registers each cube in an enabled Cube Manager schedule group that runs every
five minutes. Since both cubes support synchronization, routine updates use
cube synchronization. Cube Manager falls back to a build when a cube has not
yet been built.

Open **Analytics > Admin > Cube Manager** to inspect or adjust the schedules.
If you change the Cube Manager configuration, export the generated
`DiseaseRegistry.CubeRegistry` class back into `src/` to preserve the change.

The included registry uses the following Post-Build Code and Post-Synchronize
Code for each cube:

```objectscript
do ##class(DiseaseRegistry.Util.CacheWarmer).QueueCube("DiseaseRegistryPatients")
```

```objectscript
do ##class(DiseaseRegistry.Util.CacheWarmer).QueueCube("DiseaseRegistryDiagnoses")
```

The warmer runs as a background job, waits until the cube is queryable, and
coalesces duplicate workers for the same cube. This ensures it runs after the
build's final obsolete-cache purge. Outcomes are written to
`DeepSeeTasks_DISEASEREGISTRY.log` with source label `DiseaseReg`.

To execute an important MDX query that is not saved as a pivot:

```objectscript
set mdx="SELECT {[Measures].[%Count]} ON 0, [Disease].[Disease Group].Members ON 1 FROM [DiseaseRegistryDiagnoses]"
set sc=##class(DiseaseRegistry.Util.CacheWarmer).WarmMDX(mdx,.parameters,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

Cache warming consumes CPU and I/O, so production deployments should warm only
high-value dashboard queries and parameter combinations.

## Persistence and code injection

IRIS instance data and the application database live in the Docker named volume `disease-registry-iris-data`; Web Gateway state uses `disease-registry-webgateway-data`. The license is mounted read-only and excluded from Git. The `src/` and `tests/` directories are mounted read-only into the running container. The image also contains a snapshot of both directories, so it remains runnable without the development bind mounts if Compose is adjusted later.

The bootstrap flow is:

1. A one-shot initializer makes the named volume writable by the IRIS container user (UID `51773`).
2. IRIS starts using durable `%SYS` at `/durable/config`.
3. `iris-main --after` executes `docker/bootstrap.sh`.
4. `docker/App.Installer.cls` creates the database and namespace when absent.
5. The installer recursively imports and compiles `src/`.

Before starting, `bin/start` also verifies that the configured SuperServer and Web Gateway host ports are not already occupied by another process.

## Configuration

Defaults can be overridden by copying `.env.example` to `.env`. Keep `IRIS_IMAGE` and `WEBGATEWAY_IMAGE` on matching release tags, and pin both to an explicit version before using this outside local development.

This scaffold uses licensed IRIS for Health with development-oriented authentication and HTTP-only Web Gateway settings. Keeping predefined administrator passwords at `SYS` is intentionally insecure and suitable only for an isolated developer workstation. Change all default credentials and review licensing, TLS, auditing, data retention, backup, and healthcare privacy requirements before storing real patient data or deploying elsewhere.
