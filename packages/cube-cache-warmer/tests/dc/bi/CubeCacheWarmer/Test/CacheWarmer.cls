Class dc.bi.CubeCacheWarmer.Test.CacheWarmer Extends %UnitTest.TestCase
{

Method TestRejectsMissingCubeName()
{
  Set sc = ##class(dc.bi.CubeCacheWarmer.CacheWarmer).QueueCube("")
  Do $$$AssertStatusNotOK(sc)
}

Method TestDashboardDefaultFilterComposition()
{
  Kill filters
  Set filters("[Status].[H1].[Status]") = "&[Active]"
  Set filters("[Region].[H1].[Region]") = "{&[One],&[Two]}"
  Set baseMDX = "SELECT {[Measures].[%Count]} ON 0 FROM [ExampleCube]"

  Set sc = ##class(dc.bi.CubeCacheWarmer.CacheWarmer).ApplyDefaultFilters(baseMDX,.filters,.filteredMDX,.filterCount)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(filterCount,2)
  Do $$$AssertTrue(filteredMDX[" %FILTER NONEMPTYCROSSJOIN(")
  Do $$$AssertTrue(filteredMDX["[Status].[H1].[Status].&[Active]")
  Do $$$AssertTrue(filteredMDX["%OR({[Region].[H1].[Region].&[One],[Region].[H1].[Region].&[Two]})")
}

Method TestDashboardUsageAuditHook()
{
  Set dashboardName = "Cube Cache Warmer/Test Usage.dashboard"
  If ##class(dc.bi.CubeCacheWarmer.Model.DashboardUsage).%ExistsId(dashboardName) {
    Set cleanupSC = ##class(dc.bi.CubeCacheWarmer.Model.DashboardUsage).%DeleteId(dashboardName)
    Do $$$AssertStatusOK(cleanupSC)
  }

  Set sc = ##class(dc.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("dc.bi.CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))

  Set sc = ##class(%DeepSee.Utils).%RunServerAuditCode(dashboardName)
  Do $$$AssertStatusOK(sc)
  Set sc = ##class(%DeepSee.Utils).%RunServerAuditCode(dashboardName)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(##class(dc.bi.CubeCacheWarmer.DashboardUsage).GetOpenCount(dashboardName),2)

  Set usage = ##class(dc.bi.CubeCacheWarmer.Model.DashboardUsage).%OpenId(dashboardName,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertTrue($IsObject(usage))
  Do $$$AssertNotEquals(usage.FirstOpenedAt,"")
  Do $$$AssertNotEquals(usage.LastOpenedAt,"")

  Set cleanupSC = ##class(dc.bi.CubeCacheWarmer.Model.DashboardUsage).%DeleteId(dashboardName)
  Do $$$AssertStatusOK(cleanupSC)
}

Method TestInstallerPreservesExistingAuditCommand()
{
  Set savedAuditCode = $Get(^DeepSee.AuditCode)
  Set priorCommand = "set tCubeCacheWarmerPriorAudit=1"
  Set ^DeepSee.AuditCode = priorCommand

  Set sc = ##class(dc.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("dc.bi.CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))
  Do $$$AssertTrue(^DeepSee.AuditCode[priorCommand)

  Set laterCommand = "set tCubeCacheWarmerLaterAudit=1"
  Set ^DeepSee.AuditCode = laterCommand_" "_^DeepSee.AuditCode
  Set sc = ##class(dc.bi.CubeCacheWarmer.Installer).Uninstall()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(^DeepSee.AuditCode,laterCommand_" "_priorCommand)

  If savedAuditCode="" {
    Kill ^DeepSee.AuditCode
  } Else {
    Set ^DeepSee.AuditCode = savedAuditCode
  }
}

Method TestQueryFrequencyAuditHook()
{
  Set mdx = "SELECT {[Measures].[%Count]} ON 0 FROM [DiseaseRegistryPatients]"
  Set logUser = "CCWUnitTest"
  Kill ^DeepSee.QueryLog(logUser),^dc.bi.CCW.QueryLogCheckpoint(logUser)
  Kill variables
  Set result = ##class(%DeepSee.ResultSet).%New()
  Set sc = result.%PrepareMDX(mdx,.variables,.resolved)
  Do $$$AssertStatusOK(sc)
  Set queryKey = result.%GetQueryKey()

  If ##class(dc.bi.CubeCacheWarmer.Model.QueryUsage).%ExistsId(queryKey) {
    Set cleanupSC = ##class(dc.bi.CubeCacheWarmer.Model.QueryUsage).%DeleteId(queryKey)
    Do $$$AssertStatusOK(cleanupSC)
  }

  Set sc = ##class(dc.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[$Parameter("dc.bi.CubeCacheWarmer.QueryUsage","AUDITCOMMAND"))

  Set ^DeepSee.QueryLog(logUser,1) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Set ^DeepSee.QueryLog(logUser,2) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Set usage = ##class(dc.bi.CubeCacheWarmer.Model.QueryUsage).%OpenId(queryKey,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertEquals(usage.ExecutionCount,2)

  Set ^||dc.bi.CCW.CacheWarmer("active") = 1
  Set ^DeepSee.QueryLog(logUser,3) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Kill ^||dc.bi.CCW.CacheWarmer("active")
  Set usage = ##class(dc.bi.CubeCacheWarmer.Model.QueryUsage).%OpenId(queryKey,,.openSC)
  Do $$$AssertEquals(usage.ExecutionCount,2)

  Set cleanupSC = ##class(dc.bi.CubeCacheWarmer.Model.QueryUsage).%DeleteId(queryKey)
  Do $$$AssertStatusOK(cleanupSC)
  Kill ^DeepSee.QueryLog(logUser),^dc.bi.CCW.QueryLogCheckpoint(logUser)
}

Method TestInstallerPreservesExistingQueryAuditCommand()
{
  Set savedAuditCode = $Get(^DeepSee.AuditQueryCode)
  Set priorCommand = "set tCubeCacheWarmerPriorQueryAudit=1"
  Set ^DeepSee.AuditQueryCode = priorCommand

  Set sc = ##class(dc.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[$Parameter("dc.bi.CubeCacheWarmer.QueryUsage","AUDITCOMMAND"))
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[priorCommand)

  Set laterCommand = "set tCubeCacheWarmerLaterQueryAudit=1"
  Set ^DeepSee.AuditQueryCode = laterCommand_" "_^DeepSee.AuditQueryCode
  Set sc = ##class(dc.bi.CubeCacheWarmer.QueryUsage).Uninstall()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(^DeepSee.AuditQueryCode,laterCommand_" "_priorCommand)

  If savedAuditCode="" {
    Kill ^DeepSee.AuditQueryCode
  } Else {
    Set ^DeepSee.AuditQueryCode = savedAuditCode
  }
}

Method TestStatsArePersistent()
{
  Kill parameters,stats
  Set sc = ##class(dc.bi.CubeCacheWarmer.CacheWarmer).WarmMDX("",.parameters,0,.stats)
  Do $$$AssertStatusNotOK(sc)
  Set runId = $Get(stats("runId"),0)
  Do $$$AssertNotEquals(runId,0)

  Set run = ##class(dc.bi.CubeCacheWarmer.Model.CacheWarmRun).%OpenId(runId,,.openSC)
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

  Set deleteSC = ##class(dc.bi.CubeCacheWarmer.Model.CacheWarmRun).%DeleteId(runId)
  Do $$$AssertStatusOK(deleteSC)
}

}
