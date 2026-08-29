# Install and run the demo

This guide creates a disposable local IRIS Community Edition environment,
installs the standalone cache-warmer package, loads the Disease Registry demo,
builds its two cubes, and verifies cache warming.

The environment is for local development only. It uses known credentials,
unencrypted HTTP, and named Docker volumes.

## What the demo contains

The demo installs:

| Component | Name |
| --- | --- |
| Namespace and database | `DISEASEREGISTRY` |
| Patient source class | `DiseaseRegistry.Model.Patient` |
| Diagnosis source class | `DiseaseRegistry.Model.Diagnosis` |
| Patient cube | `DiseaseRegistryPatients` |
| Diagnosis cube | `DiseaseRegistryDiagnoses` |
| Patient pivot | `Disease Registry/Patients by Status.pivot` |
| Diagnosis pivot | `Disease Registry/Diagnoses by Group.pivot` |
| Dashboard | `Disease Registry/Patient Overview.dashboard` |

Both source classes use DSTIME, allowing changes to be synchronized into the
cubes without rebuilding every fact.

## Prerequisites

- Docker Desktop with Docker Compose v2
- Git
- Network access to the InterSystems Container Registry
- Permission to pull the configured IRIS Community and Web Gateway images
- Optional: Visual Studio Code with the extensions recommended by the repository

## Clone and configure

```bash
git clone git@gitlab.iscinternal.com:jsaliba/deepsee-cube-cache-warmer.git
cd deepsee-cube-cache-warmer
```

The public [`iris-community:latest-em`](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=ACLOUD)
image includes its Community Edition license; no external `iris.key` file is
required. Authenticate to the InterSystems Container Registry only if pulling
the separate Web Gateway image requires it:

```bash
docker login containers.intersystems.com
```

The default configuration is:

| Setting | Default |
| --- | --- |
| IRIS image | `containers.intersystems.com/intersystems/iris-community:latest-em` |
| Web Gateway image | `containers.intersystems.com/intersystems/webgateway:latest-em` |
| IRIS SuperServer host port | `1972` |
| Web Gateway host port | `52773` |

To override a value, copy `.env.example` to `.env` and edit the copy. Keep the
IRIS and Web Gateway image releases compatible. Pin explicit image versions for
a repeatable long-lived environment.

## Start and wait for bootstrap

```bash
./bin/start
```

The script checks that the configured host ports are available, builds the IRIS
image, initializes the named volumes, and starts IRIS and the Web Gateway.

First-time bootstrap continues after `./bin/start` returns. Follow the IRIS log:

```bash
./bin/logs
```

Do not run the demo or tests until this line appears:

```text
Disease Registry bootstrap complete.
```

Bootstrap performs the following work:

1. Creates durable IRIS system storage.
2. Creates the `DISEASEREGISTRY` database and namespace.
3. Enables the namespace for interoperability and Analytics.
4. Imports and compiles `DHA.BI.CubeCacheWarmer`.
5. Imports and compiles the demo application.
6. Activates `DiseaseRegistry.CubeRegistry` and updater tasks.
7. Installs the dashboard-open and normalized-query-frequency audit hooks.

## Open the development environment

- Management Portal: <http://localhost:52773/csp/sys/UtilHome.csp>
- Namespace: `DISEASEREGISTRY`
- Username: `_SYSTEM`
- Password: `SYS`

Open an ObjectScript terminal with:

```bash
./bin/terminal
```

The terminal opens directly in `DISEASEREGISTRY`.

## Create the demo data and BI content

In the ObjectScript terminal, run:

```objectscript
set sc=##class(DiseaseRegistry.Util.Analytics).SetupDemo(50,500,1,1)
do $SYSTEM.OBJ.DisplayError(sc)
```

The arguments are:

1. Number of patients.
2. Number of diagnoses.
3. Reset existing demo Patient and Diagnosis extents first.
4. Warm saved queries after creating the BI content.

With the default arguments, the method:

1. Deletes existing demo Patient and Diagnosis rows.
2. Creates 50 deterministic patients.
3. Creates 500 deterministic diagnoses.
4. Builds the patient and diagnosis cubes.
5. Creates two saved pivots.
6. Creates `Patient Overview.dashboard`.
7. Executes the dashboard and pivot queries through the cache warmer.

Do not use `pReset=1` after replacing the demo model with real registry data.

Expected final output includes:

```text
Warmed 3 saved queries.
Source rows: 50 patients; 500 diagnoses.
```

The dashboard patient-status widget has two opening defaults:

- `@DiseaseRegistryDefaultStatus`, resolved to `Active` in the demo context.
- Emirate set to `Dubai`.

The warmer executes both the saved base pivot and the default-filter variant.

## Verify the installation

Run the package and application tests:

```bash
./bin/test
```

Both suites should report `All PASSED`.

From the ObjectScript terminal, verify source counts:

```objectscript
set sc=##class(DiseaseRegistry.Util.Analytics).ShowCounts()
do $SYSTEM.OBJ.DisplayError(sc)
```

Inspect recent warmer runs in the Management Portal SQL page while using the
`DISEASEREGISTRY` namespace:

```sql
SELECT TOP 20 %ID AS RunId, CubeName, Mode, Outcome,
       TotalQueries, SucceededQueries, FailedQueries,
       EnumerationErrors, ElapsedSeconds, StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmRun
ORDER BY %ID DESC
```

The final demo runs should include successful `DirectCube` entries for both
cubes. `QueuedCube` entries with `Skipped` are expected when Post-Build and
Post-Synchronize hooks queue workers for the same cube at nearly the same time.

After exercising dashboards and pivots, inspect the real frequency source:

```sql
SELECT CubeName, QueryKey, ExecutionCount, LastExecutedAt
FROM DHA_BI_CubeCacheWarmer_Model.QueryUsage
ORDER BY ExecutionCount DESC, LastExecutedAt DESC, QueryKey
```

Run `WarmCube()` again and inspect `CacheWarmQuery` ordered by `PriorityOrder`.
Rows with `SourceType='QueryFrequency'` must come first with non-increasing
`QueryFrequency`; remaining dashboard and pivot candidates follow as fallback.

See [operations.md](operations.md) for complete monitoring queries and outcome
interpretation.

## Exercise incremental synchronization

Generate deterministic inserts, updates, and deletes:

```objectscript
set sc=##class(DiseaseRegistry.Util.Analytics).MakeChanges(10,6,2,3)
do $SYSTEM.OBJ.DisplayError(sc)
```

Synchronize the cubes and run direct warming afterward:

```objectscript
set sc=##class(DiseaseRegistry.Util.Analytics).SynchronizeAll(1)
do $SYSTEM.OBJ.DisplayError(sc)
```

`SynchronizeAll()` prints the patient and diagnosis fact counts updated by the
synchronizations. Cube Manager hooks can also queue background warming as part
of this process.

## View and adjust cube schedules

In the Management Portal, open **Analytics > Admin > Cube Manager**. The active
registry contains enabled groups for both cubes and schedules updates every five
minutes.

If you change Cube Manager configuration, export the generated
`DiseaseRegistry.CubeRegistry` class back into `src/` so the change survives a
fresh installation.

## Stop, restart, or reset

Stop containers while preserving IRIS and Web Gateway data:

```bash
./bin/stop
```

Restart with:

```bash
./bin/start
```

Delete the containers and both named volumes for a completely fresh install:

```bash
docker compose down -v
```

The last command permanently deletes the local IRIS database, configuration,
demo data, cache history, and Web Gateway state. The deleted volume contents are
not recoverable through Docker.
