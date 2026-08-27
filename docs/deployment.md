# Deploy the standalone package

The deployable unit is `packages/dha-bi-cube-cache-warmer`. It has no dependency
on the Disease Registry demo, Docker, application cube names, namespace names,
or the demo's Cube Manager registry.

## Requirements

- InterSystems IRIS or IRIS for Health 2021.1 or later.
- A namespace enabled for IRIS Business Intelligence/Analytics.
- Saved pivots or dashboards for the logical cubes to warm.
- An installation identity allowed to import and compile classes, create the
  package's persistent tables, and update `^DeepSee.AuditCode`.
- A runtime identity allowed to query the cubes and execute the saved MDX.

Install the package separately into every namespace where it will be used. Its
classes, persistent history, dashboard usage, audit hook, and locks are
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
src/DHA/BI/CubeCacheWarmer/
tests/DHA/BI/CubeCacheWarmer/Test/
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

1. Imports the `DHA.BI.CubeCacheWarmer` package.
2. Compiles its persistent models.
3. Calls `DHA.BI.CubeCacheWarmer.Installer.Install()`.
4. Prepends the dashboard-usage recorder to `^DeepSee.AuditCode` if absent.

An existing audit command is preserved and runs after the recorder.

## Install from source classes

When IPM is unavailable, import the source directory and invoke the installer:

```objectscript
set sc=$SYSTEM.OBJ.LoadDir("/path/to/dha-bi-cube-cache-warmer/src","ck",,1)
do $SYSTEM.OBJ.DisplayError(sc)
quit:$SYSTEM.Status.IsError(sc)

set sc=##class(DHA.BI.CubeCacheWarmer.Installer).Install()
do $SYSTEM.OBJ.DisplayError(sc)
```

The installation is idempotent: reinstalling does not duplicate the audit
command.

## Configure Cube Manager hooks

For each logical cube, set both Post-Build Code and Post-Synchronize Code:

```objectscript
do ##class(DHA.BI.CubeCacheWarmer.CacheWarmer).QueueCube("MyLogicalCube")
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
write ##class(DHA.BI.CubeCacheWarmer.CacheWarmer).%ClassName(1),!
```

Confirm that the audit hook is installed:

```objectscript
write $get(^DeepSee.AuditCode),!
```

It should contain:

```objectscript
do ##class(DHA.BI.CubeCacheWarmer.DashboardUsage).Record(%dsDashboard)
```

Warm one cube synchronously during validation:

```objectscript
set sc=##class(DHA.BI.CubeCacheWarmer.CacheWarmer).WarmCube("MyLogicalCube",0,1,.stats)
do $SYSTEM.OBJ.DisplayError(sc)
zwrite stats
```

Then verify the run and child queries:

```sql
SELECT TOP 5 %ID AS RunId, CubeName, Mode, Outcome,
       TotalQueries, SucceededQueries, FailedQueries,
       EnumerationErrors, ElapsedSeconds, StatusText
FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmRun
ORDER BY %ID DESC
```

A valid deployment should produce query rows with `Success=1` and populated
`QueryKey` values. `TotalQueries=0` is valid when the cube has no matching saved
pivots or dashboards.

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

For an IPM installation, deploy the updated directory or artifact and load it in
the same namespace:

```objectscript
zpm "load /path/to/dha-bi-cube-cache-warmer"
```

For a source installation, import the new `src` directory with compile flags and
call `Installer.Install()` again. The installer leaves an existing audit hook in
place and does not duplicate it.

Before upgrading production:

1. Review class and storage changes.
2. Back up the target database according to local policy.
3. Test against the deployed IRIS version.
4. Validate a direct cube run.
5. Confirm Cube Manager hooks and dashboard auditing afterward.

## Uninstall

IPM invokes the package cleanup hook automatically:

```objectscript
zpm "uninstall DHA.BI.CubeCacheWarmer"
```

For a source installation, remove the audit hook before deleting classes:

```objectscript
set sc=##class(DHA.BI.CubeCacheWarmer.Installer).Uninstall()
do $SYSTEM.OBJ.DisplayError(sc)
```

Also remove the `QueueCube()` calls from Cube Manager Post-Build and
Post-Synchronize configuration before deleting the package classes.

Uninstall removes only the cache-warmer command from `^DeepSee.AuditCode`; it
preserves unrelated audit commands. Persistent usage and run history are not
automatically deleted. Retain or remove those records according to the
organization's data-retention policy before removing their model classes.

## Redistribution

No external redistribution license is included. Confirm the organization's
license requirements and the target IRIS licensing terms before publishing the
package or its archive outside the intended environment.
