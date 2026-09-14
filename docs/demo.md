# Install and run the demo

This guide builds a disposable local IRIS Community Edition container that
contains the standalone cache-warmer package, the demo application, its two
built cubes, saved pivots, a dashboard, and a first set of warmed queries.

The environment is for local development only. It uses known credentials and
unencrypted HTTP.

## What the demo contains

| Component | Name |
| --- | --- |
| Namespace | `USER`, with Analytics enabled |
| Patient source class | `Demo.Model.Patient` |
| Diagnosis source class | `Demo.Model.Diagnosis` |
| Patient cube | `DemoPatients` |
| Diagnosis cube | `DemoDiagnoses` |
| Patient pivot | `Cube Cache Warmer Demo/Patients by Status.pivot` |
| Diagnosis pivot | `Cube Cache Warmer Demo/Diagnoses by Group.pivot` |
| Dashboard | `Cube Cache Warmer Demo/Patient Overview.dashboard` |

Both source classes use DSTIME, allowing changes to be synchronized into the
cubes without rebuilding every fact.

## Prerequisites

- Docker Desktop, or Docker Engine with the Compose plugin
- Git
- Network access to Docker Hub for the `intersystemsdc/iris-community` image
- Optional: Visual Studio Code with the extensions recommended by the repository

Every command in this guide is the same in PowerShell, Command Prompt, WSL, and
bash.

## Build and start

```bash
git clone https://github.com/josaliba/deepsee-cube-cache-warmer.git
cd deepsee-cube-cache-warmer
docker compose up -d --build --wait
```

The `intersystemsdc/iris-community:latest-em` image includes IRIS Community
Edition with its license, the InterSystems Package Manager, and a web server,
so no registry login or license key is needed.

While the image builds, `iris.script` runs once inside it and:

1. Enables Analytics for the `USER` namespace.
2. Loads `dc.bi.CubeCacheWarmer` from the root `module.xml` with IPM, whose
   Activate hook installs the dashboard-open and query-frequency audit hooks.
3. Imports and compiles the demo application.
4. Activates `Demo.CubeRegistry` and schedules its Cube Manager updater tasks.
5. Creates 50 deterministic patients and 500 diagnoses, builds both cubes,
   saves two pivots and the dashboard, and warms their queries.

The command returns when IRIS reports healthy. Nothing else has to be run.

To change the image tag or the published host ports, copy `.env.example` to
`.env` and edit the copy:

| Setting | Default |
| --- | --- |
| `IRIS_IMAGE` | `intersystemsdc/iris-community:latest-em` |
| `IRIS_WEB_PORT` | `52773` |
| `IRIS_SUPERSERVER_PORT` | `1972` |

## Open the development environment

- Management Portal: <http://localhost:52773/csp/sys/UtilHome.csp>
- Analytics user portal: <http://localhost:52773/csp/user/_DeepSee.UserPortal.Home.zen>
- Namespace: `USER`
- Username: `_SYSTEM`
- Password: `SYS`

Open an ObjectScript terminal in the demo namespace:

```bash
docker compose exec iris iris session IRIS -U USER
```

## Recreate the demo content

The demo content already exists after the build. To reset and recreate it, run
this in the ObjectScript terminal:

```objectscript
set sc=##class(Demo.Util.Analytics).SetupDemo(50,500,1,1)
do $SYSTEM.OBJ.DisplayError(sc)
```

The arguments are:

1. Number of patients.
2. Number of diagnoses.
3. Reset existing demo Patient and Diagnosis extents first.
4. Warm saved queries after creating the BI content.

Do not use `pReset=1` after replacing the demo model with real registry data.

Expected final output includes:

```text
Warmed 3 saved queries.
Source rows: 50 patients; 500 diagnoses.
```

The dashboard patient-status widget has two opening defaults:

- `@DemoDefaultStatus`, resolved to `Active` in the demo context.
- Emirate set to `Dubai`.

The warmer executes both the saved base pivot and the default-filter variant.

## Verify the installation

Run the package and application tests:

```bash
docker compose exec iris iris session IRIS -U USER "##class(Demo.Util.Tests).RunAll()"
```

Both suites should report `All PASSED`, followed by `All test suites passed.`

From the ObjectScript terminal, verify source counts:

```objectscript
set sc=##class(Demo.Util.Analytics).ShowCounts()
do $SYSTEM.OBJ.DisplayError(sc)
```

Inspect recent warmer runs in the Management Portal SQL page while using the
`USER` namespace:

```sql
SELECT TOP 20 %ID AS RunId, CubeName, Mode, Outcome,
       TotalQueries, SucceededQueries, FailedQueries,
       EnumerationErrors, ElapsedSeconds, StatusText
FROM dc_bi_CubeCacheWarmer_Model.CacheWarmRun
ORDER BY %ID DESC
```

The final demo runs should include successful `DirectCube` entries for both
cubes. `QueuedCube` entries with `Skipped` are expected when Post-Build and
Post-Synchronize hooks queue workers for the same cube at nearly the same time.

After exercising dashboards and pivots, inspect the real frequency source:

```sql
SELECT CubeName, QueryKey, ExecutionCount, LastExecutedAt
FROM dc_bi_CubeCacheWarmer_Model.QueryUsage
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
set sc=##class(Demo.Util.Analytics).MakeChanges(10,6,2,3)
do $SYSTEM.OBJ.DisplayError(sc)
```

Synchronize the cubes and run direct warming afterward:

```objectscript
set sc=##class(Demo.Util.Analytics).SynchronizeAll(1)
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
`Demo.CubeRegistry` class so the change survives a fresh
installation. The checked-in class deliberately uses the legacy
`%DeepSee.CubeManager.RegistryDefinitionSuper` format required by IRIS 2025.1.
Newer IRIS releases may upgrade the compiled class to `%DeepSee.CubeSchedule`;
do not replace the checked-in source with that upgraded format while IRIS 2025.1
support is required. Port the schedule changes into the legacy source and rerun
the compatibility tests instead.

## Stop, restart, or reset

Stop the container and keep its state:

```bash
docker compose stop
```

Start it again with `docker compose start`, or with `docker compose up -d` to
recreate it after a configuration change.

Remove the container:

```bash
docker compose down
```

The demo keeps no Docker volume, so `down` discards cube data, warm history,
and any changes made inside the container. The next `docker compose up -d`
starts again from the image, which already contains the freshly built demo.

Rebuild on the newest community image, for example after the Community Edition
license inside a cached image has expired:

```bash
docker compose build --pull
docker compose up -d --wait
```
