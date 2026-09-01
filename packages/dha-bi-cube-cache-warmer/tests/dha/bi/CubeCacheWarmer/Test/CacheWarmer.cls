Class dha.bi.CubeCacheWarmer.Test.CacheWarmer Extends %UnitTest.TestCase
{

Method TestRejectsMissingCubeName()
{
  Set sc = ##class(dha.bi.CubeCacheWarmer.CacheWarmer).QueueCube("")
  Do $$$AssertStatusNotOK(sc)
}

Method TestDashboardDefaultFilterComposition()
{
  Kill filters
  Set filters("[Status].[H1].[Status]") = "&[Active]"
  Set filters("[Region].[H1].[Region]") = "{&[One],&[Two]}"
  Set baseMDX = "SELECT {[Measures].[%Count]} ON 0 FROM [ExampleCube]"

  Set sc = ##class(dha.bi.CubeCacheWarmer.CacheWarmer).ApplyDefaultFilters(baseMDX,.filters,.filteredMDX,.filterCount)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(filterCount,2)
  Do $$$AssertTrue(filteredMDX[" %FILTER NONEMPTYCROSSJOIN(")
  Do $$$AssertTrue(filteredMDX["[Status].[H1].[Status].&[Active]")
  Do $$$AssertTrue(filteredMDX["%OR({[Region].[H1].[Region].&[One],[Region].[H1].[Region].&[Two]})")
}

Method TestDashboardUsageAuditHook()
{
  Set dashboardName = "DHA BI Cube Cache Warmer/Test Usage.dashboard"
  If ##class(dha.bi.CubeCacheWarmer.Model.DashboardUsage).%ExistsId(dashboardName) {
    Set cleanupSC = ##class(dha.bi.CubeCacheWarmer.Model.DashboardUsage).%DeleteId(dashboardName)
    Do $$$AssertStatusOK(cleanupSC)
  }

  Set sc = ##class(dha.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("dha.bi.CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))

  Set sc = ##class(%DeepSee.Utils).%RunServerAuditCode(dashboardName)
  Do $$$AssertStatusOK(sc)
  Set sc = ##class(%DeepSee.Utils).%RunServerAuditCode(dashboardName)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(##class(dha.bi.CubeCacheWarmer.DashboardUsage).GetOpenCount(dashboardName),2)

  Set usage = ##class(dha.bi.CubeCacheWarmer.Model.DashboardUsage).%OpenId(dashboardName,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertTrue($IsObject(usage))
  Do $$$AssertNotEquals(usage.FirstOpenedAt,"")
  Do $$$AssertNotEquals(usage.LastOpenedAt,"")

  Set cleanupSC = ##class(dha.bi.CubeCacheWarmer.Model.DashboardUsage).%DeleteId(dashboardName)
  Do $$$AssertStatusOK(cleanupSC)
}

Method TestInstallerPreservesExistingAuditCommand()
{
  Set savedAuditCode = $Get(^DeepSee.AuditCode)
  Set priorCommand = "set tDHABICubeCacheWarmerPriorAudit=1"
  Set ^DeepSee.AuditCode = priorCommand

  Set sc = ##class(dha.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("dha.bi.CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))
  Do $$$AssertTrue(^DeepSee.AuditCode[priorCommand)

  Set laterCommand = "set tDHABICubeCacheWarmerLaterAudit=1"
  Set ^DeepSee.AuditCode = laterCommand_" "_^DeepSee.AuditCode
  Set sc = ##class(dha.bi.CubeCacheWarmer.Installer).Uninstall()
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
  Set logUser = "DHABICCWUnitTest"
  Kill ^DeepSee.QueryLog(logUser),^DHABICCW.QueryLogCheckpoint(logUser)
  Kill variables
  Set result = ##class(%DeepSee.ResultSet).%New()
  Set sc = result.%PrepareMDX(mdx,.variables,.resolved)
  Do $$$AssertStatusOK(sc)
  Set queryKey = result.%GetQueryKey()

  If ##class(dha.bi.CubeCacheWarmer.Model.QueryUsage).%ExistsId(queryKey) {
    Set cleanupSC = ##class(dha.bi.CubeCacheWarmer.Model.QueryUsage).%DeleteId(queryKey)
    Do $$$AssertStatusOK(cleanupSC)
  }

  Set sc = ##class(dha.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[$Parameter("dha.bi.CubeCacheWarmer.QueryUsage","AUDITCOMMAND"))

  Set ^DeepSee.QueryLog(logUser,1) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Set ^DeepSee.QueryLog(logUser,2) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Set usage = ##class(dha.bi.CubeCacheWarmer.Model.QueryUsage).%OpenId(queryKey,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertEquals(usage.ExecutionCount,2)

  Set ^||DHABICCW.CacheWarmer("active") = 1
  Set ^DeepSee.QueryLog(logUser,3) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Kill ^||DHABICCW.CacheWarmer("active")
  Set usage = ##class(dha.bi.CubeCacheWarmer.Model.QueryUsage).%OpenId(queryKey,,.openSC)
  Do $$$AssertEquals(usage.ExecutionCount,2)

  Set cleanupSC = ##class(dha.bi.CubeCacheWarmer.Model.QueryUsage).%DeleteId(queryKey)
  Do $$$AssertStatusOK(cleanupSC)
  Kill ^DeepSee.QueryLog(logUser),^DHABICCW.QueryLogCheckpoint(logUser)
}

Method TestInstallerPreservesExistingQueryAuditCommand()
{
  Set savedAuditCode = $Get(^DeepSee.AuditQueryCode)
  Set priorCommand = "set tDHABICubeCacheWarmerPriorQueryAudit=1"
  Set ^DeepSee.AuditQueryCode = priorCommand

  Set sc = ##class(dha.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[$Parameter("dha.bi.CubeCacheWarmer.QueryUsage","AUDITCOMMAND"))
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[priorCommand)

  Set laterCommand = "set tDHABICubeCacheWarmerLaterQueryAudit=1"
  Set ^DeepSee.AuditQueryCode = laterCommand_" "_^DeepSee.AuditQueryCode
  Set sc = ##class(dha.bi.CubeCacheWarmer.QueryUsage).Uninstall()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(^DeepSee.AuditQueryCode,laterCommand_" "_priorCommand)

  If savedAuditCode="" {
    Kill ^DeepSee.AuditQueryCode
  } Else {
    Set ^DeepSee.AuditQueryCode = savedAuditCode
  }
}

Method TestInstallerMigratesLegacyAuditCommands()
{
  Set savedDashboardAudit = $Get(^DeepSee.AuditCode)
  Set savedQueryAudit = $Get(^DeepSee.AuditQueryCode)
  Set legacyDashboardAudit = $Parameter("dha.bi.CubeCacheWarmer.DashboardUsage","LEGACYAUDITCOMMAND")
  Set legacyQueryAudit = $Parameter("dha.bi.CubeCacheWarmer.QueryUsage","LEGACYAUDITCOMMAND")
  Set ^DeepSee.AuditCode = legacyDashboardAudit
  Set ^DeepSee.AuditQueryCode = legacyQueryAudit

  Set sc = ##class(dha.bi.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("dha.bi.CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))
  Do $$$AssertTrue('(^DeepSee.AuditCode[legacyDashboardAudit))
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[$Parameter("dha.bi.CubeCacheWarmer.QueryUsage","AUDITCOMMAND"))
  Do $$$AssertTrue('(^DeepSee.AuditQueryCode[legacyQueryAudit))

  If savedDashboardAudit="" {
    Kill ^DeepSee.AuditCode
  } Else {
    Set ^DeepSee.AuditCode = savedDashboardAudit
  }
  If savedQueryAudit="" {
    Kill ^DeepSee.AuditQueryCode
  } Else {
    Set ^DeepSee.AuditQueryCode = savedQueryAudit
  }
}

Method TestStatsArePersistent()
{
  Kill parameters,stats
  Set sc = ##class(dha.bi.CubeCacheWarmer.CacheWarmer).WarmMDX("",.parameters,0,.stats)
  Do $$$AssertStatusNotOK(sc)
  Set runId = $Get(stats("runId"),0)
  Do $$$AssertNotEquals(runId,0)

  Set run = ##class(dha.bi.CubeCacheWarmer.Model.CacheWarmRun).%OpenId(runId,,.openSC)
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

  Set deleteSC = ##class(dha.bi.CubeCacheWarmer.Model.CacheWarmRun).%DeleteId(runId)
  Do $$$AssertStatusOK(deleteSC)
}

}
