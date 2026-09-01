# dha.bi.CubeCacheWarmer

Self-contained cache-warming package for InterSystems IRIS Business
Intelligence. The package has no dependency on application-specific classes,
cube names, namespace names, Docker, or Cube Manager registry classes.

It provides:

- queued post-build and post-synchronization warming;
- duplicate-job coalescing and cube-availability waiting;
- automatic native `^DeepSee.QueryLog` frequency tracking through
  `^DeepSee.AuditQueryCode`;
- true query-frequency-ordered execution, with dashboards and pivots as fallback;
- dashboard default-filter support;
- persistent run and per-query statistics; and
- history retention utilities.

## Requirements

- InterSystems IRIS or IRIS for Health 2021.1 or later;
- an Analytics-enabled namespace; and
- a user that can compile the package and update its persistent tables.

## Package contents

```text
src/dha/bi/CubeCacheWarmer/
├── CacheWarmer.cls
├── DashboardUsage.cls
├── Installer.cls
├── QueryUsage.cls
└── Model/
    ├── CacheWarmQuery.cls
    ├── CacheWarmRun.cls
    ├── DashboardUsage.cls
    └── QueryUsage.cls
```

The entire `dha-bi-cube-cache-warmer` directory can be copied into another
repository or archived for distribution.

### Upgrading from the uppercase package name

IRIS class names are case-insensitive but retain their canonical case. An
existing `DHA.BI.CubeCacheWarmer` installation must therefore have its old
class and extent definitions removed before `dha.bi.CubeCacheWarmer` is loaded.
The stored `^DHABICCW` data is preserved. Follow the package-case migration in
[the deployment guide](../../docs/deployment.md#upgrade-from-dhabi-to-dhabi)
before using either installation method below.

## Install with InterSystems Package Manager

With an IPM client installed, run this from the target Analytics namespace:

```objectscript
zpm "load /path/to/dha-bi-cube-cache-warmer"
```

The module installs both the dashboard-access and query-execution audit hooks.
Existing commands in `^DeepSee.AuditCode` and `^DeepSee.AuditQueryCode` are
preserved and run after the cache-warmer recorders.

## Install from the `.cls` sources

```objectscript
set sc=$SYSTEM.OBJ.LoadDir("/path/to/dha-bi-cube-cache-warmer/src","ck",,1)
do $SYSTEM.OBJ.DisplayError(sc)
set sc=##class(dha.bi.CubeCacheWarmer.Installer).Install()
do $SYSTEM.OBJ.DisplayError(sc)
```

## Configure Cube Manager

Use the following as both the cube's Post-Build Code and Post-Synchronize Code,
substituting its logical cube name:

```objectscript
do ##class(dha.bi.CubeCacheWarmer.CacheWarmer).QueueCube("MyCube")
```

The call starts a background process. It does not wait for all MDX queries to
finish in the Cube Manager task.

## Direct use

Warm a cube synchronously:

```objectscript
set sc=##class(dha.bi.CubeCacheWarmer.CacheWarmer).WarmCube("MyCube",0,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

Warm one saved pivot:

```objectscript
set sc=##class(dha.bi.CubeCacheWarmer.CacheWarmer).WarmPivot("Folder/My Pivot.pivot",.parameters,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
```

## Statistics

```sql
SELECT TOP 20 %ID, CubeName, Mode, Outcome, StartedAt, FinishedAt,
       TotalQueries, SucceededQueries, FailedQueries, ElapsedSeconds, StatusText
FROM dha_bi_CubeCacheWarmer_Model.CacheWarmRun
ORDER BY %ID DESC
```

```sql
SELECT QueryName, SourceType, DashboardName, WidgetName, DefaultFilterCount,
       DashboardOpenCount, QueryFrequency, PriorityOrder, CubeName, QueryKey,
       RowCount, ColumnCount, ElapsedSeconds, Success, StatusText
FROM dha_bi_CubeCacheWarmer_Model.CacheWarmQuery
WHERE Run = :runId
```

```sql
SELECT DashboardName, OpenCount, FirstOpenedAt, LastOpenedAt
FROM dha_bi_CubeCacheWarmer_Model.DashboardUsage
ORDER BY OpenCount DESC, LastOpenedAt DESC
```

Inspect the true query-frequency order used by the next warm run:

```sql
SELECT CubeName, QueryKey, ExecutionCount, FirstExecutedAt, LastExecutedAt
FROM dha_bi_CubeCacheWarmer_Model.QueryUsage
ORDER BY ExecutionCount DESC, LastExecutedAt DESC, QueryKey
```

To seed the frequency table once from existing native query-log history:

```objectscript
set sc=##class(dha.bi.CubeCacheWarmer.QueryUsage).ImportQueryLog(1,.imported)
do $SYSTEM.OBJ.DisplayError(sc)
write imported," historical executions imported",!
```

`pReset=1` replaces the package's collected frequency data. Do not run this
repeatedly without resetting, because each import intentionally counts every
entry currently present in `^DeepSee.QueryLog`.

Delete completed warmer history older than 30 days:

```objectscript
set sc=##class(dha.bi.CubeCacheWarmer.CacheWarmer).PurgeHistory(30,.deleted)
```

## Uninstall

An IPM uninstall automatically removes both cache-warmer audit hooks before
removing the package:

```objectscript
zpm "uninstall dha.bi.CubeCacheWarmer"
```

For a source-based installation, remove both hooks before deleting the classes:

```objectscript
set sc=##class(dha.bi.CubeCacheWarmer.Installer).Uninstall()
```

This removes only the cache-warmer commands. It does not delete persistent usage
or execution history.

## Operational notes

- Query counts begin when the query-audit hook is installed. A one-time
  `ImportQueryLog()` can seed existing history. Every distinct normalized query
  is ordered by real execution count, then recency; saved dashboard queries and
  remaining pivots run afterwards when they were not already covered.
- The warmer marks its process while replaying MDX, so its own executions never
  increase `ExecutionCount` and cannot create a frequency feedback loop.
- Query-frequency tracking persists the resolved MDX required for replay. Treat
  this table as potentially sensitive when filter members contain business data.
- Dashboard usage records contain dashboard name, count, and timestamps only.
  Usernames, MDX, filter values, URL parameters, and query parameters are not
  stored.
- A zero-wait usage lock avoids delaying dashboard requests. A simultaneous
  access can therefore be omitted from the aggregate count.
- Runtime `@setting` defaults resolve in the background worker's user and
  security context.
- URL filters, interactive selections, and per-user overrides cannot be
  predicted automatically.
- Review and add the license required by your organization before external
  redistribution.
