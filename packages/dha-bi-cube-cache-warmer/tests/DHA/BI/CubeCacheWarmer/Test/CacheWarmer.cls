Class DHA.BI.CubeCacheWarmer.Test.CacheWarmer Extends %UnitTest.TestCase
{

Method TestRejectsMissingCubeName()
{
  Set sc = ##class(DHA.BI.CubeCacheWarmer.CacheWarmer).QueueCube("")
  Do $$$AssertStatusNotOK(sc)
}

Method TestDashboardDefaultFilterComposition()
{
  Kill filters
  Set filters("[Status].[H1].[Status]") = "&[Active]"
  Set filters("[Region].[H1].[Region]") = "{&[One],&[Two]}"
  Set baseMDX = "SELECT {[Measures].[%Count]} ON 0 FROM [ExampleCube]"

  Set sc = ##class(DHA.BI.CubeCacheWarmer.CacheWarmer).ApplyDefaultFilters(baseMDX,.filters,.filteredMDX,.filterCount)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(filterCount,2)
  Do $$$AssertTrue(filteredMDX[" %FILTER NONEMPTYCROSSJOIN(")
  Do $$$AssertTrue(filteredMDX["[Status].[H1].[Status].&[Active]")
  Do $$$AssertTrue(filteredMDX["%OR({[Region].[H1].[Region].&[One],[Region].[H1].[Region].&[Two]})")
}

Method TestDashboardUsageAuditHook()
{
  Set dashboardName = "DHA BI Cube Cache Warmer/Test Usage.dashboard"
  If ##class(DHA.BI.CubeCacheWarmer.Model.DashboardUsage).%ExistsId(dashboardName) {
    Set cleanupSC = ##class(DHA.BI.CubeCacheWarmer.Model.DashboardUsage).%DeleteId(dashboardName)
    Do $$$AssertStatusOK(cleanupSC)
  }

  Set sc = ##class(DHA.BI.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("DHA.BI.CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))

  Set sc = ##class(%DeepSee.Utils).%RunServerAuditCode(dashboardName)
  Do $$$AssertStatusOK(sc)
  Set sc = ##class(%DeepSee.Utils).%RunServerAuditCode(dashboardName)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(##class(DHA.BI.CubeCacheWarmer.DashboardUsage).GetOpenCount(dashboardName),2)

  Set usage = ##class(DHA.BI.CubeCacheWarmer.Model.DashboardUsage).%OpenId(dashboardName,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertTrue($IsObject(usage))
  Do $$$AssertNotEquals(usage.FirstOpenedAt,"")
  Do $$$AssertNotEquals(usage.LastOpenedAt,"")

  Set cleanupSC = ##class(DHA.BI.CubeCacheWarmer.Model.DashboardUsage).%DeleteId(dashboardName)
  Do $$$AssertStatusOK(cleanupSC)
}

Method TestInstallerPreservesExistingAuditCommand()
{
  Set savedAuditCode = $Get(^DeepSee.AuditCode)
  Set priorCommand = "set tDHABICubeCacheWarmerPriorAudit=1"
  Set ^DeepSee.AuditCode = priorCommand

  Set sc = ##class(DHA.BI.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditCode[$Parameter("DHA.BI.CubeCacheWarmer.DashboardUsage","AUDITCOMMAND"))
  Do $$$AssertTrue(^DeepSee.AuditCode[priorCommand)

  Set laterCommand = "set tDHABICubeCacheWarmerLaterAudit=1"
  Set ^DeepSee.AuditCode = laterCommand_" "_^DeepSee.AuditCode
  Set sc = ##class(DHA.BI.CubeCacheWarmer.Installer).Uninstall()
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

  If ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%ExistsId(queryKey) {
    Set cleanupSC = ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%DeleteId(queryKey)
    Do $$$AssertStatusOK(cleanupSC)
  }

  Set sc = ##class(DHA.BI.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[$Parameter("DHA.BI.CubeCacheWarmer.QueryUsage","AUDITCOMMAND"))

  Set ^DeepSee.QueryLog(logUser,1) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Set ^DeepSee.QueryLog(logUser,2) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Set usage = ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%OpenId(queryKey,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertEquals(usage.ExecutionCount,2)

  Set ^||DHABICCW.CacheWarmer("active") = 1
  Set ^DeepSee.QueryLog(logUser,3) = mdx
  Xecute ^DeepSee.AuditQueryCode
  Kill ^||DHABICCW.CacheWarmer("active")
  Set usage = ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%OpenId(queryKey,,.openSC)
  Do $$$AssertEquals(usage.ExecutionCount,2)

  Set cleanupSC = ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%DeleteId(queryKey)
  Do $$$AssertStatusOK(cleanupSC)
  Kill ^DeepSee.QueryLog(logUser),^DHABICCW.QueryLogCheckpoint(logUser)
}

Method TestInstallerPreservesExistingQueryAuditCommand()
{
  Set savedAuditCode = $Get(^DeepSee.AuditQueryCode)
  Set priorCommand = "set tDHABICubeCacheWarmerPriorQueryAudit=1"
  Set ^DeepSee.AuditQueryCode = priorCommand

  Set sc = ##class(DHA.BI.CubeCacheWarmer.Installer).Install()
  Do $$$AssertStatusOK(sc)
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[$Parameter("DHA.BI.CubeCacheWarmer.QueryUsage","AUDITCOMMAND"))
  Do $$$AssertTrue(^DeepSee.AuditQueryCode[priorCommand)

  Set laterCommand = "set tDHABICubeCacheWarmerLaterQueryAudit=1"
  Set ^DeepSee.AuditQueryCode = laterCommand_" "_^DeepSee.AuditQueryCode
  Set sc = ##class(DHA.BI.CubeCacheWarmer.QueryUsage).Uninstall()
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
  Set sc = ##class(DHA.BI.CubeCacheWarmer.CacheWarmer).WarmMDX("",.parameters,0,.stats)
  Do $$$AssertStatusNotOK(sc)
  Set runId = $Get(stats("runId"),0)
  Do $$$AssertNotEquals(runId,0)

  Set run = ##class(DHA.BI.CubeCacheWarmer.Model.CacheWarmRun).%OpenId(runId,,.openSC)
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

  Set deleteSC = ##class(DHA.BI.CubeCacheWarmer.Model.CacheWarmRun).%DeleteId(runId)
  Do $$$AssertStatusOK(deleteSC)
}

}
