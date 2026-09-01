# Deploy the standalone package

The deployable unit is `packages/dha-bi-cube-cache-warmer`. It has no dependency
on the Disease Registry demo, Docker, application cube names, namespace names,
or the demo's Cube Manager registry.

## Requirements

- InterSystems IRIS or IRIS for Health 2021.1 or later.
- A namespace enabled for IRIS Business Intelligence/Analytics.
- Saved pivots or dashboards for the logical cubes to warm.
- An installation identity allowed to import and compile classes, create the
  package's persistent tables, and update `^DeepSee.AuditCode` and
  `^DeepSee.AuditQueryCode`.
- A runtime identity allowed to query the cubes and execute the saved MDX.

Install the package separately into every namespace where it will be used. Its
classes, persistent history, dashboard/query usage, both audit hooks, and locks are
namespace-scoped.

## Build the artifact

From the repository root:

```bash
./bin/package-cache-warmer
```

The script reads the version from `module.xml` and writes:

```text
dist/dha-bi-cube-cache-warmer-<version>.tar.gz
```

The archive contains the standalone package directory, including:

```text
README.md
module.xml
src/dha/bi/CubeCacheWarmer/
tests/dha/bi/CubeCacheWarmer/Test/
```

Generated archives are ignored by Git. Publish them through the organization's
approved artifact mechanism rather than committing binaries to the repository.

Before a release, update the `<Version>` in `module.xml`, run the tests, build
the archive, inspect its contents, and tag the corresponding commit according to
the team's release policy.

## Install with InterSystems Package Manager

Extract or copy the package directory to a path visible from the target IRIS
instance. In an ObjectScript terminal connected to the target Analytics
namespace:

```objectscript
zpm "load /path/to/dha-bi-cube-cache-warmer"
```

The IPM module:

1. Imports the `dha.bi.CubeCacheWarmer` package.
2. Compiles its persistent models.
3. Calls `dha.bi.CubeCacheWarmer.Installer.Install()`.
4. Prepends the dashboard-usage recorder to `^DeepSee.AuditCode` if absent.
5. Prepends the query-frequency recorder to `^DeepSee.AuditQueryCode` if absent.

An existing audit command is preserved and runs after the recorder.

## Install from source classes

When IPM is unavailable, import the source directory and invoke the installer:

```objectscript
set sc=$SYSTEM.OBJ.LoadDir("/path/to/dha-bi-cube-cache-warmer/src","ck",,1)
do $SYSTEM.OBJ.DisplayError(sc)
quit:$SYSTEM.Status.IsError(sc)

set sc=##class(dha.bi.CubeCacheWarmer.Installer).Install()
do $SYSTEM.OBJ.DisplayError(sc)
```

The installation is idempotent: reinstalling does not duplicate the audit
command.

## Configure Cube Manager hooks

For each logical cube, set both Post-Build Code and Post-Synchronize Code:

```objectscript
do ##class(dha.bi.CubeCacheWarmer.CacheWarmer).QueueCube("MyLogicalCube")
```

Using both hooks covers full builds and incremental synchronization. A build can
cause both hooks to run close together. The per-cube lock coalesces those
workers, leaving one successful or active run and one harmless `Skipped` run.

The logical cube name must be the name accepted by `%DeepSee.Utils` and used by
saved pivots, not the generated fact-table class name.

If Cube Manager configuration is maintained through a generated registry class,
export and deploy that class with the application so the hooks survive database
recreation.

## Verify a deployment

Confirm that the classes exist:

```objectscript
write ##class(dha.bi.CubeCacheWarmer.CacheWarmer).%ClassName(1),!
```

Confirm that both audit hooks are installed:

```objectscript
write $get(^DeepSee.AuditCode),!
write $get(^DeepSee.AuditQueryCode),!
```

It should contain:

```objectscript
do ##class(dha.bi.CubeCacheWarmer.DashboardUsage).Record(%dsDashboard)
do ##class(dha.bi.CubeCacheWarmer.QueryUsage).RecordAudit()
```

Warm one cube synchronously during validation:

```objectscript
set sc=##class(dha.bi.CubeCacheWarmer.CacheWarmer).WarmCube("MyLogicalCube",0,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

Then verify the run and child queries:

```sql
SELECT TOP 5 %ID AS RunId, CubeName, Mode, Outcome,
       TotalQueries, SucceededQueries, FailedQueries,
       EnumerationErrors, ElapsedSeconds, StatusText
FROM dha_bi_CubeCacheWarmer_Model.CacheWarmRun
ORDER BY %ID DESC
```

A valid deployment should produce query rows with `Success=1` and populated
`QueryKey` values. `TotalQueries=0` is valid when the cube has no matching saved
pivots or dashboards.

For an established namespace, optionally seed historical counts once from the
native query log before the first production warm run:

```objectscript
set sc=##class(dha.bi.CubeCacheWarmer.QueryUsage).ImportQueryLog(1,.imported)
do $SYSTEM.OBJ.DisplayError(sc)
write imported," executions imported",!
```

Then verify the ranking source:

```sql
SELECT CubeName, QueryKey, ExecutionCount, FirstExecutedAt, LastExecutedAt
FROM dha_bi_CubeCacheWarmer_Model.QueryUsage
ORDER BY ExecutionCount DESC, LastExecutedAt DESC, QueryKey
```

The query audit hook maintains this table after installation and excludes the
warmer's own executions. The model stores resolved MDX for replay, so restrict
its SQL permissions and retention according to local data policy.

## Runtime permissions and identity

The background worker is started from the Cube Manager hook. Ensure that its
runtime context can:

- resolve the cube and subject areas;
- open saved dashboards and pivots;
- execute their MDX;
- read runtime `@setting` values used by dashboard defaults; and
- write the package's history and usage globals.

Runtime dashboard settings are evaluated in the worker's user/security context.
If results depend on user-specific settings or row-level authorization, validate
the intended worker identity and cache behavior before enabling automatic
warming.

## Production configuration guidance

- Start with high-value saved dashboards and pivots rather than warming every
  theoretical parameter combination.
- Schedule cube updates and warming outside known peak periods where possible.
- Measure elapsed time, CPU, I/O, and cache benefit before expanding workload.
- Keep `pStopOnError=0` for resilient broad warming unless an application
  requires fail-fast behavior.
- Retain enough history to diagnose regressions, then purge it on a schedule.
- Monitor stale `Running`, `Failure`, and `PartialFailure` outcomes.
- Review `StatusText` and BI task logs for operational data before deciding on
  retention and access controls.
- Use TLS, least-privilege service identities, backups, auditing, and the
  organization's normal change-management process.

## Upgrade

### Upgrade from `DHA.BI` to `dha.bi`

IRIS treats class names as case-insensitive while retaining the canonical case
of the installed definition. Loading `dha.bi.CubeCacheWarmer` over an existing
`DHA.BI.CubeCacheWarmer` definition therefore produces error `#5092` unless the
old definitions are removed first.

Back up the namespace database, then run the following in that Analytics
namespace before loading version 1.2.0 or later:

```objectscript
set sc=##class(DHA.BI.CubeCacheWarmer.Installer).Uninstall()
do $SYSTEM.OBJ.DisplayError(sc)
quit:$SYSTEM.Status.IsError(sc)

set sc=$SYSTEM.OBJ.DeletePackage("DHA.BI.CubeCacheWarmer")
do $SYSTEM.OBJ.DisplayError(sc)
quit:$SYSTEM.Status.IsError(sc)

for className="DHA.BI.CubeCacheWarmer.Model.CacheWarmQuery","DHA.BI.CubeCacheWarmer.Model.CacheWarmRun","DHA.BI.CubeCacheWarmer.Model.DashboardUsage","DHA.BI.CubeCacheWarmer.Model.QueryUsage" {
    set sc=##class(%ExtentMgr.Util).DeleteExtentDefinitionIfExists(className)
    do $SYSTEM.OBJ.DisplayError(sc)
    quit:$SYSTEM.Status.IsError(sc)
}
```

Do not use the `/deleteextent` qualifier or the `e` deletion flag. The commands
above delete definitions and extent registrations only; the persistent
`^DHABICCW` globals remain intact and are registered to the lowercase model
classes when they compile. Then load the package normally and call
`dha.bi.CubeCacheWarmer.Installer.Install()`.

The Docker demo performs this case migration automatically during bootstrap.

For an IPM installation, deploy the updated directory or artifact and load it in
the same namespace:

```objectscript
zpm "load /path/to/dha-bi-cube-cache-warmer"
```

For a source installation, import the new `src` directory with compile flags and
call `Installer.Install()` again. The installer preserves existing dashboard
and query audit commands and does not duplicate its own commands.

Before upgrading production:

1. Review class and storage changes.
2. Back up the target database according to local policy.
3. Test against the deployed IRIS version.
4. Validate a direct cube run.
5. Confirm Cube Manager hooks and dashboard/query auditing afterward.

## Uninstall

IPM invokes the package cleanup hook automatically:

```objectscript
zpm "uninstall dha.bi.CubeCacheWarmer"
```

For a source installation, remove both audit hooks before deleting classes:

```objectscript
set sc=##class(dha.bi.CubeCacheWarmer.Installer).Uninstall()
do $SYSTEM.OBJ.DisplayError(sc)
```

Also remove the `QueueCube()` calls from Cube Manager Post-Build and
Post-Synchronize configuration before deleting the package classes.

Uninstall removes only the cache-warmer commands from `^DeepSee.AuditCode` and
`^DeepSee.AuditQueryCode`; it preserves unrelated audit commands. Persistent
usage and run history are not automatically deleted. Retain or remove those
records according to the organization's data-retention policy before removing
their model classes.

## Redistribution

No external redistribution license is included. Confirm the organization's
license requirements and the target IRIS licensing terms before publishing the
package or its archive outside the intended environment.
