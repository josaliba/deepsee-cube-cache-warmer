# Operations, monitoring, and troubleshooting

Run SQL in the same Analytics namespace where the package is installed. For the
demo, use `DISEASEREGISTRY`.

## Run modes

| Mode | Created by |
| --- | --- |
| `QueuedCube` | Background `QueueCube()` worker |
| `DirectCube` | Direct `WarmCube()` call |
| `DirectPivot` | Direct `WarmPivot()` call |
| `DirectMDX` | Direct `WarmMDX()` call |

`Skipped` is an outcome, not a mode. It means a queued worker found another
worker already waiting for or warming the same cube.

## Inspect recent runs

```sql
SELECT TOP 20
       %ID AS RunId,
       CubeName,
       Mode,
       Outcome,
       StartedAt,
       FinishedAt,
       ProcessId,
       TotalQueries,
       SucceededQueries,
       FailedQueries,
       EnumerationErrors,
       ElapsedSeconds,
       StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmRun
ORDER BY %ID DESC
```

Healthy completed work normally has:

- `Outcome='Success'`;
- `FailedQueries=0`;
- `EnumerationErrors=0`; and
- a non-null `FinishedAt`.

A successful run with `TotalQueries=0` means no matching saved query was
available. This commonly occurs during the first demo build because demo pivots
are created after the cubes, or in a production cube that has no saved pivots.

## Inspect queries from the latest completed run

```sql
SELECT Run AS RunId,
       QueryName,
       SourceType,
       DashboardName,
       WidgetName,
       DefaultFilterCount,
       DashboardOpenCount,
       PriorityOrder,
       CubeName,
       QueryKey,
       RowCount,
       ColumnCount,
       ElapsedSeconds,
       Success,
       StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmQuery
WHERE Run = (
    SELECT MAX(%ID)
    FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmRun
    WHERE Outcome <> 'Running'
)
ORDER BY PriorityOrder, QueryName
```

Successful query rows should have `Success=1`, `StatusText='OK'`, and normally a
generated `QueryKey`. Row or column counts can legitimately be zero for an empty
result.

## Find query failures

```sql
SELECT Run AS RunId,
       QueryName,
       SourceType,
       DashboardName,
       WidgetName,
       CubeName,
       ElapsedSeconds,
       StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmQuery
WHERE Success = 0
ORDER BY Run DESC, QueryName
```

## Find failed or partially failed runs

```sql
SELECT %ID AS RunId,
       CubeName,
       Mode,
       Outcome,
       SucceededQueries,
       FailedQueries,
       EnumerationErrors,
       StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmRun
WHERE Outcome IN ('Failure','PartialFailure')
ORDER BY %ID DESC
```

`PartialFailure` means useful work succeeded but another query or discovery step
failed. `EnumerationErrors` covers problems inspecting dashboards, widgets,
pivots, or defaults even if the MDX queries that were found succeeded.

## Find stale running workers

Choose an age appropriate for the deployment's largest expected cube and
workload. This example finds runs older than one hour:

```sql
SELECT %ID AS RunId, CubeName, Mode, ProcessId, StartedAt, StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmRun
WHERE Outcome = 'Running'
  AND StartedAt < DATEADD(hour,-1,CURRENT_TIMESTAMP)
ORDER BY StartedAt
```

A stale `Running` row can indicate that an IRIS process was terminated before
history finalization. Confirm the process state and BI logs before changing
history.

## Inspect dashboard priority

```sql
SELECT DashboardName,
       OpenCount,
       FirstOpenedAt,
       LastOpenedAt
FROM DHA_BI_CubeCacheWarmer_Model.DashboardUsage
ORDER BY OpenCount DESC, LastOpenedAt DESC
```

No rows means no dashboard has been opened since the audit hook was installed.
Creating a dashboard does not increment usage. Counts are intentionally
best-effort: simultaneous opens of the same dashboard can result in one omitted
increment so user requests never wait for telemetry.

## Summarize query performance

```sql
SELECT CubeName,
       SourceType,
       COUNT(*) AS Executions,
       SUM(CASE WHEN Success=1 THEN 1 ELSE 0 END) AS Successful,
       AVG(ElapsedSeconds) AS AverageSeconds,
       MAX(ElapsedSeconds) AS MaximumSeconds
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmQuery
GROUP BY CubeName, SourceType
ORDER BY CubeName, SourceType
```

Use this to identify expensive query types and confirm whether the warming
workload remains appropriate as dashboards evolve.

## Manual operations

Queue background cube warming:

```objectscript
set sc=##class(DHA.BI.CubeCacheWarmer.CacheWarmer).QueueCube("MyCube",600,1,0,.jobId)
do $SYSTEM.OBJ.DisplayError(sc)
write !,"Job: ",jobId,!
```

Warm a cube synchronously:

```objectscript
set sc=##class(DHA.BI.CubeCacheWarmer.CacheWarmer).WarmCube("MyCube",0,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

Warm one saved pivot:

```objectscript
kill parameters
set sc=##class(DHA.BI.CubeCacheWarmer.CacheWarmer).WarmPivot("Folder/My Pivot.pivot",.parameters,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

Warm arbitrary MDX:

```objectscript
set mdx="SELECT {[Measures].[%Count]} ON 0 FROM [MyCube]"
kill parameters
set sc=##class(DHA.BI.CubeCacheWarmer.CacheWarmer).WarmMDX(mdx,.parameters,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

## Logs

The warmer writes BI task summaries with source label `DHABICCW` to the
namespace's DeepSee task log, commonly named
`DeepSeeTasks_<NAMESPACE>.log`. Query and enumeration errors include their IRIS
status text.

For the Docker demo, follow IRIS container and bootstrap output with:

```bash
./bin/logs
```

History tables should be the primary structured monitoring source; logs provide
additional diagnostic context.

## History retention

History is not deleted automatically. Delete completed runs older than 30 days:

```objectscript
set sc=##class(DHA.BI.CubeCacheWarmer.CacheWarmer).PurgeHistory(30,.deleted)
do $SYSTEM.OBJ.DisplayError(sc)
write !,"Deleted runs: ",deleted,!
```

`PurgeHistory()` does not delete rows whose outcome is still `Running`, and it
does not purge IRIS BI cached results. It deletes only the package's completed
execution history and associated child query records.

Schedule retention according to operational, audit, and storage requirements.

## Troubleshooting

### Classes do not exist after starting the demo

First-time bootstrap is asynchronous. Follow `./bin/logs` and wait for:

```text
Disease Registry bootstrap complete.
```

If bootstrap failed, inspect the status immediately before that point. Confirm
the license, image access, namespace creation, and compilation errors.

### A run is `Skipped`

Another worker already owns the per-cube lock. This is expected when Post-Build
and Post-Synchronize hooks fire close together. Verify that the paired worker
completed successfully before investigating further.

### A successful run has zero queries

Confirm that:

- saved pivots exist in the same namespace;
- their logical cube or base cube matches the requested name;
- dashboard widget data sources end in `.pivot`; and
- the demo is past its initial cube-build stage.

### Dashboard usage remains empty

Confirm `^DeepSee.AuditCode` contains the package recorder, then open the saved
dashboard through IRIS BI. Creating or editing a dashboard does not count as an
open.

### `EnumerationErrors` is nonzero

Inspect `StatusText`, failed child queries, and the `DHABICCW` log entries. Common
causes include deleted pivots, invalid widget data sources, unavailable runtime
settings, or malformed saved defaults.

### Runtime defaults differ from user behavior

Values beginning with `@` resolve in the background worker's user/security
context. Use static defaults, align the worker identity, or explicitly warm
important profiles when user-specific settings matter.

### Warming causes excessive load

Reduce the saved workload, avoid high-cardinality parameter combinations,
schedule updates outside peak periods, and use query-history timing to identify
expensive pivots. The warmer executes real MDX and therefore consumes the same
CPU and I/O resources as the corresponding user queries.
