Include %occStatus

/// Counts real IRIS BI query executions through ^DeepSee.AuditQueryCode.
/// Cache-warmer executions are marked process-locally and are never counted.
Class DHA.BI.CubeCacheWarmer.QueryUsage Extends %RegisteredObject
{

Parameter AUDITCOMMAND = "do ##class(DHA.BI.CubeCacheWarmer.QueryUsage).RecordAudit()";

Parameter LEGACYAUDITCOMMAND = "do ##class(DHA.BI.CubeCacheWarmer.QueryUsage).Record(%dsQuery)";

Parameter LEGACYAUDITCOMMAND2 = "do ##class(DHA.BI.CubeCacheWarmer.QueryUsage).RecordQuery(pQuery,$get(%dsQuery))";

ClassMethod Install(Output pChanged As %Boolean = 0) As %Status
{
  Set pChanged = 0
  Set tRemoveSC = ..RemoveCommand(..#LEGACYAUDITCOMMAND,.tLegacyChanged)
  If $$$ISERR(tRemoveSC) Quit tRemoveSC
  Set tRemoveSC = ..RemoveCommand(..#LEGACYAUDITCOMMAND2,.tLegacy2Changed)
  If $$$ISERR(tRemoveSC) Quit tRemoveSC
  Set pChanged = tLegacyChanged||tLegacy2Changed
  Set tCommand = ..#AUDITCOMMAND
  Set tCurrent = $Get(^DeepSee.AuditQueryCode)
  If tCurrent[tCommand {
    Do ..InitializeQueryLogCheckpoints()
    Quit $$$OK
  }
  Set ^DeepSee.AuditQueryCode = tCommand_$Select(tCurrent="":"",1:" "_tCurrent)
  Do ..InitializeQueryLogCheckpoints()
  Set pChanged = 1
  Quit $$$OK
}

ClassMethod Uninstall(Output pChanged As %Boolean = 0) As %Status
{
  Set tSC = ..RemoveCommand(..#AUDITCOMMAND,.tCurrentChanged)
  If $$$ISERR(tSC) Quit tSC
  Set tSC = ..RemoveCommand(..#LEGACYAUDITCOMMAND,.tLegacyChanged)
  If $$$ISERR(tSC) Quit tSC
  Set tSC = ..RemoveCommand(..#LEGACYAUDITCOMMAND2,.tLegacy2Changed)
  Set pChanged = tCurrentChanged||tLegacyChanged||tLegacy2Changed
  Quit tSC
}

ClassMethod RemoveCommand(pCommand As %String, Output pChanged As %Boolean = 0) As %Status [ Private ]
{
  Set pChanged = 0
  Set tCurrent = $Get(^DeepSee.AuditQueryCode)
  Set tEndPosition = $Find(tCurrent,pCommand)
  If 'tEndPosition Quit $$$OK

  Set tStartPosition = tEndPosition-$Length(pCommand)
  Set tBefore = $ZSTRIP($Extract(tCurrent,1,tStartPosition-1),"<>W")
  Set tAfter = $ZSTRIP($Extract(tCurrent,tEndPosition,*),"<>W")
  Set tRemaining = tBefore_$Select((tBefore="")||(tAfter=""):"",1:" ")_tAfter
  If tRemaining="" Kill ^DeepSee.AuditQueryCode
  If tRemaining'="" Set ^DeepSee.AuditQueryCode = tRemaining
  Set pChanged = 1
  Quit $$$OK
}

/// Public convenience entry point for importing or explicitly recording MDX.
ClassMethod Record(pMDX As %String)
{
  Quit:$Get(^||DHABICCW.CacheWarmer("active"))>0
  Do ..RecordInternal(pMDX)
}

/// Called after every IRIS BI query. QueryLog is the source of truth because
/// some supported IRIS versions do not define %dsQuery for direct API calls.
ClassMethod RecordAudit()
{
  Do ..CaptureNewQueryLogEntries($Get(^||DHABICCW.CacheWarmer("active"))<1)
}

/// Import the current contents of ^DeepSee.QueryLog once when historical
/// frequency is required. pReset=1 replaces previously collected usage.
ClassMethod ImportQueryLog(pReset As %Boolean = 0, Output pImported As %Integer = 0) As %Status
{
  Set pImported = 0
  If pReset {
    Set tSC = ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%DeleteExtent()
    If $$$ISERR(tSC) Quit tSC
  }

  Set tUser = ""
  For {
    Set tUser = $Order(^DeepSee.QueryLog(tUser))
    Quit:tUser=""
    Set tSequence = ""
    For {
      Set tSequence = $Order(^DeepSee.QueryLog(tUser,tSequence))
      Quit:tSequence=""
      Set tMDX = $Get(^DeepSee.QueryLog(tUser,tSequence))
      Continue:tMDX=""
      If ..RecordInternal(tMDX) Set pImported = pImported+1
    }
    Set ^DHABICCW.QueryLogCheckpoint(tUser) = $Order(^DeepSee.QueryLog(tUser,""),-1)
  }
  Quit $$$OK
}

/// Return one when the query was counted and zero when it could not be parsed.
ClassMethod RecordInternal(pMDX As %String) As %Boolean [ Private ]
{
  Set pMDX = $ZSTRIP(pMDX,"<>W")
  Quit:pMDX="" 0

  Set tRecorded = 0, tResolvedMDX = ""
  Try {
    Kill tVariables
    Set tResult = ##class(%DeepSee.ResultSet).%New()
    Set tSC = tResult.%PrepareMDX(pMDX,.tVariables,.tResolvedMDX)
    If $$$ISOK(tSC) {
      Set tQueryKey = tResult.%GetQueryKey()
      Set tCubeName = tResult.%GetCubeName()
      If tQueryKey'="" {
        Set tRecorded = ..RecordKnownQuery(tQueryKey,tCubeName,$Select(tResolvedMDX'="":tResolvedMDX,1:pMDX))
      }
    }
  } Catch ex {
    Set tRecorded = 0
  }
  Quit tRecorded
}

ClassMethod RecordKnownQuery(pQueryKey As %String, pCubeName As %String, pMDX As %String = "") As %Boolean [ Private ]
{
  Set tRecorded = 0, tLockHeld = 0
  Try {
    // The lock is intentionally blocking and very short. Unlike dashboard-open
    // telemetry, query frequency must not silently lose simultaneous executions.
    Lock +^DHABICCW.QueryUsageLock(pQueryKey)
    Set tLockHeld = 1
    Set tNow = ..CurrentTimestamp()
    If ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%ExistsId(pQueryKey) {
      Set tUsage = ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%OpenId(pQueryKey,,.tOpenSC)
    } Else {
      Set tOpenSC = $$$OK
      Set tUsage = ##class(DHA.BI.CubeCacheWarmer.Model.QueryUsage).%New()
      Set tUsage.QueryKey = pQueryKey
      Set tUsage.ExecutionCount = 0
      Set tUsage.FirstExecutedAt = tNow
    }
    If $$$ISOK(tOpenSC),$IsObject(tUsage) {
      Set tUsage.CubeName = pCubeName
      If pMDX'="" Set tUsage.MDX = $Extract(pMDX,1,65535)
      Set tUsage.ExecutionCount = tUsage.ExecutionCount+1
      Set tUsage.LastExecutedAt = tNow
      Set tSC = tUsage.%Save()
      Set tRecorded = $$$ISOK(tSC)
    }
  } Catch ex {
    Set tRecorded = 0
  }
  If tLockHeld Lock -^DHABICCW.QueryUsageLock(pQueryKey)
  Quit tRecorded
}

/// Claim and process every native log entry added since the previous audit.
/// A warmer audit advances the checkpoint without counting its replay.
ClassMethod CaptureNewQueryLogEntries(pCount As %Boolean) [ Private ]
{
  Lock +^DHABICCW.QueryLogCaptureLock
  Try {
    Set tUser = ""
    For {
      Set tUser = $Order(^DeepSee.QueryLog(tUser))
      Quit:tUser=""
      Set tCheckpoint = $Get(^DHABICCW.QueryLogCheckpoint(tUser))
      Set tLast = $Order(^DeepSee.QueryLog(tUser,""),-1)
      If (tCheckpoint'=""),(tLast<tCheckpoint) Set tCheckpoint = ""
      Set tSequence = tCheckpoint
      For {
        Set tSequence = $Order(^DeepSee.QueryLog(tUser,tSequence))
        Quit:tSequence=""
        If pCount Do ..RecordInternal($Get(^DeepSee.QueryLog(tUser,tSequence)))
        Set ^DHABICCW.QueryLogCheckpoint(tUser) = tSequence
      }
    }
  } Catch ex {
    // Query auditing must never make the user's query fail.
  }
  Lock -^DHABICCW.QueryLogCaptureLock
}

/// Start live counting after the existing native history. Historical data is
/// imported only through the explicit ImportQueryLog() operation.
ClassMethod InitializeQueryLogCheckpoints() [ Private ]
{
  Quit:$Data(^DHABICCW.QueryLogCheckpoint)
  Set tUser = ""
  For {
    Set tUser = $Order(^DeepSee.QueryLog(tUser))
    Quit:tUser=""
    Set ^DHABICCW.QueryLogCheckpoint(tUser) = $Order(^DeepSee.QueryLog(tUser,""),-1)
  }
}

ClassMethod CurrentTimestamp() As %TimeStamp [ Private ]
{
  Quit $ZDATETIME($ZTIMESTAMP,3,1,6)
}

}
