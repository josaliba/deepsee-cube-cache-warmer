# DHA Disease Registry

Local development scaffold for a disease registry on licensed InterSystems IRIS for Health. Docker Compose starts IRIS for Health and a matching Web Gateway, creates the interoperability-enabled `DISEASEREGISTRY` namespace and database, and imports the standalone cache-warmer package followed by the application classes under `src/`. Interoperability enablement supplies the mappings and portal registration required for Analytics.

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
- Reusable cache-warmer code and tests live under
  `packages/dha-bi-cube-cache-warmer/` rather than the application source tree.
- The container imports the cache-warmer package and `src/` each time it starts.
- With the ObjectScript extension connected, saving a `.cls` file compiles it directly into `DISEASEREGISTRY`.
- Run the smoke test with `./bin/test`.

Useful commands:

```bash
./bin/start       # Build and start IRIS
./bin/logs        # Follow IRIS logs
./bin/terminal    # Open an ObjectScript shell in DISEASEREGISTRY
./bin/test        # Import and run tests
./bin/package-cache-warmer  # Build a distributable package archive
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

The setup also creates `Patient Overview.dashboard`. Its patient-status widget
opens with two filters: the runtime setting `@DiseaseRegistryDefaultStatus`
(which resolves to Active) and the static default Emirate=Dubai.

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

The application-neutral implementation is isolated in
[`packages/dha-bi-cube-cache-warmer`](packages/dha-bi-cube-cache-warmer/README.md). That
directory contains the `.cls` sources, tests, documentation, installer, and IPM
`module.xml`; it can be copied into another repository without the Disease
Registry demo. Run `./bin/package-cache-warmer` to create a versioned archive
under the ignored `dist/` directory.

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
do ##class(DHA.BI.CubeCacheWarmer.CacheWarmer).QueueCube("DiseaseRegistryPatients")
```

```objectscript
do ##class(DHA.BI.CubeCacheWarmer.CacheWarmer).QueueCube("DiseaseRegistryDiagnoses")
```

The warmer runs as a background job, waits until the cube is queryable, and
coalesces duplicate workers for the same cube. It first discovers saved
dashboards in automatic usage order and warms each dashboard's saved base pivots
and default-filter variants before moving to the next dashboard. It then warms
matching saved pivots that are not referenced by any dashboard. For each widget it
combines the widget's saved filter state and applicable `applyFilter` or
`setFilter` control defaults into the same filtered MDX shape used when the
dashboard opens. Static values and `@` runtime settings are supported; runtime
settings are evaluated in the worker's user/security context. Keeping the query
workload in a separate process prevents slow MDX queries from extending the Cube
Manager task. Summary outcomes are written to
`DeepSeeTasks_DISEASEREGISTRY.log` with source label `DHABICCW`.

Bootstrap installs IRIS BI's documented [`^DeepSee.AuditCode` dashboard-access
hook](https://docs.intersystems.com/irisforhealthlatest/csp/docbook/DocBook.UI.Page.cls?KEY=D2IMP_ch_dev).
Each dashboard open increments an aggregate row in
`DHA_BI_CubeCacheWarmer_Model.DashboardUsage`. The hook stores only the dashboard name,
open count, and first/last timestamps; it does not store users, URLs, filter
values, parameters, or query text. If another dashboard audit command is already
configured, installation prepends the usage recorder and retains that command.

Warming order is determined without a hand-maintained priority list:

1. Higher recorded dashboard open count.
2. IRIS BI's built-in dashboard `lastAccessed` timestamp when counts are tied or
   no usage row exists.
3. Dashboard name for a deterministic final tie-breaker.

Saved pivots inherit the earliest priority of any dashboard widget that uses
them. Pivots not referenced by a dashboard still run, after prioritized pivots.
The access hook is intentionally small and uses a zero-wait lock: if two opens
for the same dashboard collide, one usage increment may be skipped rather than
delaying the dashboard.

Inspect the automatically collected rankings with SQL:

```sql
SELECT DashboardName, OpenCount, FirstOpenedAt, LastOpenedAt
FROM DHA_BI_CubeCacheWarmer_Model.DashboardUsage
ORDER BY OpenCount DESC, LastOpenedAt DESC
```

Dashboard URL filters, interactive selections, and per-user saved dashboard
overrides are not predictable and are not warmed automatically. Add explicit
warming profiles for high-value combinations that differ from the saved opening
defaults.

Every queued, cube, pivot, and direct-MDX warming invocation also writes
persistent history to `DHA_BI_CubeCacheWarmer_Model.CacheWarmRun`, with one child row
per query in `DHA_BI_CubeCacheWarmer_Model.CacheWarmQuery`. The history contains query
names, source type, dashboard/widget attribution, default-filter count,
generated query keys, row and column counts, timings, and status. MDX text,
parameter values, and filter values are deliberately not stored. Synchronous
warmer methods also return the persistent run ID in `stats("runId")`; cube runs
return the number of dashboard-attributed base queries in
`stats("dashboardBaseQueries")` and filtered dashboard queries in
`stats("dashboardDefaults")`.

Inspect recent runs with SQL:

```sql
SELECT TOP 20 %ID, CubeName, Mode, Outcome, StartedAt, FinishedAt,
       TotalQueries, SucceededQueries, FailedQueries, ElapsedSeconds, StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmRun
ORDER BY %ID DESC
```

Inspect the queries belonging to a run by substituting its ID:

```sql
SELECT QueryName, SourceType, DashboardName, WidgetName, DefaultFilterCount,
       DashboardOpenCount, PriorityOrder, CubeName, QueryKey,
       RowCount, ColumnCount, ElapsedSeconds,
       Success, StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmQuery
WHERE Run = 2
```

History is not deleted automatically. To retain the most recent 30 days:

```objectscript
set sc=##class(DHA.BI.CubeCacheWarmer.CacheWarmer).PurgeHistory(30,.deleted)
do $SYSTEM.OBJ.DisplayError(sc)
write !,"Deleted runs: ",deleted,!
```

To execute an important MDX query that is not saved as a pivot:

```objectscript
set mdx="SELECT {[Measures].[%Count]} ON 0, [Disease].[Disease Group].Members ON 1 FROM [DiseaseRegistryDiagnoses]"
set sc=##class(DHA.BI.CubeCacheWarmer.CacheWarmer).WarmMDX(mdx,.parameters,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

Cache warming consumes CPU and I/O, so production deployments should warm only
high-value dashboard queries and parameter combinations.

## Persistence and code injection

IRIS instance data and the application database live in the Docker named volume `disease-registry-iris-data`; Web Gateway state uses `disease-registry-webgateway-data`. The license is mounted read-only and excluded from Git. The `packages/`, `src/`, and `tests/` directories are mounted read-only into the running container. The image also contains a snapshot of those directories, so it remains runnable without the development bind mounts if Compose is adjusted later.

The bootstrap flow is:

1. A one-shot initializer makes the named volume writable by the IRIS container user (UID `51773`).
2. IRIS starts using durable `%SYS` at `/durable/config`.
3. `iris-main --after` executes `docker/bootstrap.sh`.
4. `docker/App.Installer.cls` creates the database and namespace when absent.
5. The installer imports `packages/dha-bi-cube-cache-warmer/src/`, installs its BI
   audit hook, and then imports the Disease Registry classes under `src/`.

Before starting, `bin/start` also verifies that the configured SuperServer and Web Gateway host ports are not already occupied by another process.

## Configuration

Defaults can be overridden by copying `.env.example` to `.env`. Keep `IRIS_IMAGE` and `WEBGATEWAY_IMAGE` on matching release tags, and pin both to an explicit version before using this outside local development.

This scaffold uses licensed IRIS for Health with development-oriented authentication and HTTP-only Web Gateway settings. Keeping predefined administrator passwords at `SYS` is intentionally insecure and suitable only for an isolated developer workstation. Change all default credentials and review licensing, TLS, auditing, data retention, backup, and healthcare privacy requirements before storing real patient data or deploying elsewhere.
