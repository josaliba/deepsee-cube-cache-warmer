# IRIS BI Cube Cache Warmer

Self-contained cache-warming package for InterSystems IRIS Business
Intelligence. The package has no dependency on application-specific classes,
cube names, namespace names, Docker, or Cube Manager registry classes.

It provides:

- queued post-build and post-synchronization warming;
- duplicate-job coalescing and cube-availability waiting;
- automatic dashboard popularity tracking through `^DeepSee.AuditCode`;
- popularity-ordered saved dashboard and pivot execution;
- dashboard default-filter support;
- persistent run and per-query statistics; and
- history retention utilities.

## Requirements

- InterSystems IRIS or IRIS for Health 2021.1 or later;
- an Analytics-enabled namespace; and
- a user that can compile the package and update its persistent tables.

## Package contents

```text
src/CubeCacheWarmer/
├── CacheWarmer.cls
├── DashboardUsage.cls
├── Installer.cls
└── Model/
    ├── CacheWarmQuery.cls
    ├── CacheWarmRun.cls
    └── DashboardUsage.cls
```

The entire `iris-bi-cache-warmer` directory can be copied into another
repository or archived for distribution.

## Install with InterSystems Package Manager

With an IPM client installed, run this from the target Analytics namespace:

```objectscript
zpm "load /path/to/iris-bi-cache-warmer"
```

The module loads the `CubeCacheWarmer` package and installs its dashboard-access
audit hook. If another `^DeepSee.AuditCode` command already exists, it is
preserved and runs after the cache-warmer recorder.

## Install from the `.cls` sources

```objectscript
set sc=$SYSTEM.OBJ.LoadDir("/path/to/iris-bi-cache-warmer/src","ck",,1)
do $SYSTEM.OBJ.DisplayError(sc)
set sc=##class(CubeCacheWarmer.Installer).Install()
do $SYSTEM.OBJ.DisplayError(sc)
```

## Configure Cube Manager

Use the following as both the cube's Post-Build Code and Post-Synchronize Code,
substituting its logical cube name:

```objectscript
do ##class(CubeCacheWarmer.CacheWarmer).QueueCube("MyCube")
```

The call starts a background process. It does not wait for all MDX queries to
finish in the Cube Manager task.

## Direct use

Warm a cube synchronously:

```objectscript
set sc=##class(CubeCacheWarmer.CacheWarmer).WarmCube("MyCube",0,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

Warm one saved pivot:

```objectscript
set sc=##class(CubeCacheWarmer.CacheWarmer).WarmPivot("Folder/My Pivot.pivot",.parameters,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
```

## Statistics

```sql
SELECT TOP 20 %ID, CubeName, Mode, Outcome, StartedAt, FinishedAt,
       TotalQueries, SucceededQueries, FailedQueries, ElapsedSeconds, StatusText
FROM CubeCacheWarmer_Model.CacheWarmRun
ORDER BY %ID DESC
```

```sql
SELECT QueryName, SourceType, DashboardName, WidgetName, DefaultFilterCount,
       DashboardOpenCount, PriorityOrder, CubeName, QueryKey,
       RowCount, ColumnCount, ElapsedSeconds, Success, StatusText
FROM CubeCacheWarmer_Model.CacheWarmQuery
WHERE Run = :runId
```

```sql
SELECT DashboardName, OpenCount, FirstOpenedAt, LastOpenedAt
FROM CubeCacheWarmer_Model.DashboardUsage
ORDER BY OpenCount DESC, LastOpenedAt DESC
```

Delete completed warmer history older than 30 days:

```objectscript
set sc=##class(CubeCacheWarmer.CacheWarmer).PurgeHistory(30,.deleted)
```

## Uninstall

An IPM uninstall automatically removes the cache-warmer audit hook before
removing the package:

```objectscript
zpm "uninstall iris-bi-cache-warmer"
```

For a source-based installation, remove the hook before deleting the classes:

```objectscript
set sc=##class(CubeCacheWarmer.Installer).Uninstall()
```

This removes only the cache-warmer command. It does not delete persistent usage
or execution history.

## Operational notes

- Popularity counts begin when the audit hook is installed. Existing dashboard
  `lastAccessed` timestamps provide the initial fallback order.
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
