Class CubeCacheWarmer.Test.CacheWarmer Extends %UnitTest.TestCase
{

Method TestRejectsMissingCubeName()
{
  Set sc = ##class(CubeCacheWarmer.CacheWarmer).QueueCube("")
  Do $$$AssertStatusNotOK(sc)
}

Method TestDashboardDefaultFilterComposition()
{
  Kill filters
  Set filters("[Status].[H1].[Status]") = "&[Active]"
  Set filters("[Region].[H1].[Region]") = "{&[One],&[Two]}"
  Set baseMDX = "SELECT {[Measures].[%Count]} ON 0 FROM [ExampleCube]"

  Set sc = ##class(CubeCacheWarmer.CacheWarmer).ApplyDefaultFilters(baseMDX,.filters,.filteredMDX,.filterCount)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(filterCount,2)
  Do $$$AssertTrue(filteredMDX[" %FILTER NONEMPTYCROSSJOIN(")
  Do $$$AssertTrue(filteredMDX["[Status].[H1].[Status].&[Active]")
  Do $$$AssertTrue(filteredMDX["%OR({[Region].[H1].[Region].&[One],[Region].[H1].[Region].&[Two]})")
}

Method TestDashboardUsageAuditHook()
{
  Set dashboardName = "CubeCacheWarmer/Test Usage.dashboard"
  If ##class(CubeCacheWarmer.Model.DashboardUsage).%ExistsId(dashboardName) {
    Set cleanupSC = ##class(CubeCacheWarmer.Model.DashboardUsage).%DeleteId(dashboardName)
    Do $$$AssertStatusOK(cleanupSC)
  }

  Set sc = ##class(CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))

  Set sc = ##class(%DeepSee.Utils).%RunServerAuditCode(dashboardName)
  Do $$$AssertStatusOK(sc)
  Set sc = ##class(%DeepSee.Utils).%RunServerAuditCode(dashboardName)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(##class(CubeCacheWarmer.DashboardUsage).GetOpenCount(dashboardName),2)

  Set usage = ##class(CubeCacheWarmer.Model.DashboardUsage).%OpenId(dashboardName,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertTrue($IsObject(usage))
  Do $$$AssertNotEquals(usage.FirstOpenedAt,"")
  Do $$$AssertNotEquals(usage.LastOpenedAt,"")

  Set cleanupSC = ##class(CubeCacheWarmer.Model.DashboardUsage).%DeleteId(dashboardName)
  Do $$$AssertStatusOK(cleanupSC)
}

Method TestInstallerPreservesExistingAuditCommand()
{
  Set savedAuditCode = $Get(^DeepSee.AuditCode)
  Set priorCommand = "set tCubeCacheWarmerPriorAudit=1"
  Set ^DeepSee.AuditCode = priorCommand

  Set sc = ##class(CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))
  Do $$$AssertTrue(^DeepSee.AuditCode[priorCommand)

  Set laterCommand = "set tCubeCacheWarmerLaterAudit=1"
  Set ^DeepSee.AuditCode = laterCommand_" "_^DeepSee.AuditCode
  Set sc = ##class(CubeCacheWarmer.Installer).Uninstall()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(^DeepSee.AuditCode,laterCommand_" "_priorCommand)

  If savedAuditCode="" {
    Kill ^DeepSee.AuditCode
  } Else {
    Set ^DeepSee.AuditCode = savedAuditCode
  }
}

Method TestStatsArePersistent()
{
  Kill parameters,stats
  Set sc = ##class(CubeCacheWarmer.CacheWarmer).WarmMDX("",.parameters,0,.stats)
  Do $$$AssertStatusNotOK(sc)
  Set runId = $Get(stats("runId"),0)
  Do $$$AssertNotEquals(runId,0)

  Set run = ##class(CubeCacheWarmer.Model.CacheWarmRun).%OpenId(runId,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertTrue($IsObject(run))
  Do $$$AssertEquals(run.Mode,"DirectMDX")
  Do $$$AssertEquals(run.Outcome,"Failure")
  Do $$$AssertEquals(run.TotalQueries,1)
  Do $$$AssertEquals(run.FailedQueries,1)
  Do $$$AssertEquals(run.Queries.Count(),1)
  Set query = run.Queries.GetAt(1)
  Do $$$AssertEquals(query.SourceType,"AdHocMDX")
  Do $$$AssertEquals(query.DefaultFilterCount,0)
  Do $$$AssertEquals(query.DashboardOpenCount,0)
  Do $$$AssertEquals(query.PriorityOrder,0)

  Set deleteSC = ##class(CubeCacheWarmer.Model.CacheWarmRun).%DeleteId(runId)
  Do $$$AssertStatusOK(deleteSC)
}

}
