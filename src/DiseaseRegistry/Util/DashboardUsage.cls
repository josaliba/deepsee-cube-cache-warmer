Include %occStatus

/// Records dashboard opens through IRIS BI's documented ^DeepSee.AuditCode hook.
/// The hook performs one short, contention-safe update and never interrupts a
/// dashboard request if usage tracking encounters an error.
Class DiseaseRegistry.Util.DashboardUsage Extends %RegisteredObject
{

Parameter AUDITCOMMAND = "do ##class(DiseaseRegistry.Util.DashboardUsage).Record(%dsDashboard)";

/// Install the dashboard-access hook in the current namespace. If another BI
/// dashboard audit command already exists, it is retained and runs afterwards.
ClassMethod Install(Output pChanged As %Boolean = 0) As %Status
{
  Set pChanged = 0
  Set tCommand = ..#AUDITCOMMAND
  Set tCurrent = $Get(^DeepSee.AuditCode)
  If tCurrent[tCommand Quit $$$OK

  Set ^DeepSee.AuditCode = tCommand_$Select(tCurrent="":"",1:" "_tCurrent)
  Set pChanged = 1
  Quit $$$OK
}

/// Called by ^DeepSee.AuditCode with the documented %dsDashboard variable.
/// Deliberately has no return value because the BI audit hook invokes it with DO.
ClassMethod Record(pDashboard As %String)
{
  Set tDashboard = $ZSTRIP(pDashboard,"<>W")
  Quit:tDashboard=""

  Set tLockKey = $ZCONVERT(tDashboard,"U")
  Lock +^DiseaseRegistry.DashboardUsageLock(tLockKey):0
  Quit:'$TEST

  Try {
    Set tSC = $$$OK
    Set tNow = ..CurrentTimestamp()
    If ##class(DiseaseRegistry.Model.DashboardUsage).%ExistsId(tDashboard) {
      Set tUsage = ##class(DiseaseRegistry.Model.DashboardUsage).%OpenId(tDashboard,,.tSC)
      If $$$ISERR(tSC) Quit
    } Else {
      Set tUsage = ##class(DiseaseRegistry.Model.DashboardUsage).%New()
      Set tUsage.DashboardName = tDashboard
      Set tUsage.OpenCount = 0
      Set tUsage.FirstOpenedAt = tNow
    }
    Set tUsage.OpenCount = tUsage.OpenCount+1
    Set tUsage.LastOpenedAt = tNow
    Set tSC = tUsage.%Save()
  } Catch ex {
    // Usage tracking must never make a dashboard request fail.
  }

  Lock -^DiseaseRegistry.DashboardUsageLock(tLockKey)
  Quit
}

ClassMethod GetOpenCount(pDashboard As %String) As %Integer
{
  If '##class(DiseaseRegistry.Model.DashboardUsage).%ExistsId(pDashboard) Quit 0
  Set tUsage = ##class(DiseaseRegistry.Model.DashboardUsage).%OpenId(pDashboard,,.tSC)
  If $$$ISERR(tSC) Quit 0
  If '$IsObject(tUsage) Quit 0
  Quit tUsage.OpenCount
}

ClassMethod CurrentTimestamp() As %TimeStamp [ Private ]
{
  Quit $ZDATETIME($ZTIMESTAMP,3,1,6)
}

}
