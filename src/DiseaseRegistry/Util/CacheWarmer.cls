Include %occStatus

/// Warms IRIS Business Intelligence caches after a cube build or synchronization.
/// Saved pivots for the physical cube and its subject areas are executed through
/// the standard cache-enabled %DeepSee.ResultSet API.
Class DiseaseRegistry.Util.CacheWarmer Extends %RegisteredObject
{

/// Queue warming in a background process. Use this from Cube Manager Post-Build
/// and Post-Synchronize Code so warming occurs after the final cache purge.
ClassMethod QueueCube(pCubeName As %String, pWaitSeconds As %Integer = 600, pVerbose As %Boolean = 0, pStopOnError As %Boolean = 0, Output pJobId As %Integer = 0) As %Status
{
  Set pJobId = 0
  If pCubeName = "" Quit $$$ERROR($$$GeneralError,"A cube name is required")
  If pWaitSeconds < 0 Quit $$$ERROR($$$GeneralError,"pWaitSeconds cannot be negative")

  Job ##class(DiseaseRegistry.Util.CacheWarmer).WarmWhenAvailable(pCubeName,pWaitSeconds,pVerbose,pStopOnError)
  Set pJobId = $ZCHILD
  If 'pJobId Quit $$$ERROR($$$GeneralError,"Unable to start a cache warming job for "_pCubeName)
  If pVerbose Write !,"Queued cache warming for [",pCubeName,"] as job ",pJobId,!
  Quit $$$OK
}

/// Coalesce duplicate workers, wait for the cube query lock, and warm saved pivots.
ClassMethod WarmWhenAvailable(pCubeName As %String, pWaitSeconds As %Integer = 600, pVerbose As %Boolean = 0, pStopOnError As %Boolean = 0) As %Status
{
  Set tKey = $ZCONVERT(pCubeName,"U")
  Lock +^DiseaseRegistry.CacheWarmer("cube",tKey):0 Else  Quit $$$OK

  Set tSC = $$$OK
  Try {
    Set tSC = ..WaitUntilAvailable(pCubeName,pWaitSeconds,pVerbose,.tReason)
    If $$$ISOK(tSC) Set tSC = ..WarmCube(pCubeName,pStopOnError,pVerbose,.tStats)
  } Catch ex {
    Set tSC = ex.AsStatus()
  }

  Lock -^DiseaseRegistry.CacheWarmer("cube",tKey)
  If $$$ISERR(tSC) {
    Do ..Log("Cache warming failed for "_pCubeName_": "_$System.Status.GetErrorText(tSC))
  } Else {
    Do ..Log("Cache warming completed for "_pCubeName_": "_$Get(tStats("succeeded"),0)_" succeeded, "_$Get(tStats("failed"),0)_" failed")
  }
  Quit tSC
}

ClassMethod WaitUntilAvailable(pCubeName As %String, pWaitSeconds As %Integer = 600, pVerbose As %Boolean = 0, Output pReason As %String = "") As %Status
{
  Set tSC = $$$OK
  Set pReason = ""
  Set tClass = ##class(%DeepSee.Utils).%GetCubeClass(pCubeName,.tSC)
  If $$$ISERR(tSC) Quit tSC

  Set tReady = 0
  For tElapsed = 0:1:pWaitSeconds {
    Set tReady = ##class(%DeepSee.Utils).%IsCubeAvailable(pCubeName,.pReason)
    Quit:tReady
    If pVerbose,((tElapsed=0)||'(tElapsed#30)) Write !,"Waiting for [",pCubeName,"]: ",pReason,!
    If tElapsed < pWaitSeconds Hang 1
  }
  If 'tReady Quit $$$ERROR($$$GeneralError,"Cube "_pCubeName_" was not available after "_pWaitSeconds_" seconds: "_pReason)
  Quit $$$OK
}

/// Warm all saved pivots based on pCubeName. For a physical cube, pivots using
/// subject areas based on it are included. pStats contains totals and query details.
ClassMethod WarmCube(pCubeName As %String, pStopOnError As %Boolean = 0, pVerbose As %Boolean = 1, Output pStats = "") As %Status
{
  Kill pStats
  Set pStats("cube") = pCubeName
  Set pStats("total") = 0
  Set pStats("succeeded") = 0
  Set pStats("failed") = 0
  Set pStats("enumerationErrors") = 0
  Set pStats("started") = $ZTIMESTAMP
  Set tStart = $ZH
  Set tSC = $$$OK
  Set tOverallSC = $$$OK
  Set tCursorOpen = 0
  Set tStopped = 0

  Try {
    Set tClass = ##class(%DeepSee.Utils).%GetCubeClass(pCubeName,.tSC)
    If $$$ISERR(tSC) Quit
    Set tTarget = $ZCONVERT(pCubeName,"U")
    Set tTargetIsSubjectArea = (##class(%DeepSee.Utils).%GetBaseCube(pCubeName)'="")

    &sql(DECLARE DiseaseRegistryWarmPivots CURSOR FOR SELECT %ID FROM %DeepSee_Dashboard.Pivot)
    &sql(OPEN DiseaseRegistryWarmPivots)
    If SQLCODE < 0 {
      Set tSC = $$$ERROR($$$GeneralError,"Unable to enumerate saved pivots. SQLCODE="_SQLCODE_" "_$Get(%msg))
      Quit
    }
    Set tCursorOpen = 1

    For {
      &sql(FETCH DiseaseRegistryWarmPivots INTO :tPivotId)
      Quit:SQLCODE'=0

      Set tOpenSC = $$$OK
      Set tPivot = ##class(%DeepSee.Dashboard.Pivot).%OpenId(tPivotId,,.tOpenSC)
      If $$$ISERR(tOpenSC) {
        Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
        Do ..Log("Unable to inspect saved pivot ID "_tPivotId_": "_$System.Status.GetErrorText(tOpenSC))
        Continue
      }

      Set tPivotCube = tPivot.cubeName
      Continue:tPivotCube=""
      Set tPivotCubeKey = $ZCONVERT(tPivotCube,"U")
      Set tPivotBase = ##class(%DeepSee.Utils).%GetBaseCube(tPivotCube)
      If tPivotBase = "" Set tPivotBase = tPivotCube
      Set tMatches = $Select(tTargetIsSubjectArea:tPivotCubeKey=tTarget,1:$ZCONVERT(tPivotBase,"U")=tTarget)
      Continue:'tMatches

      Set tPivotName = tPivot.fullName
      Set pStats("total") = pStats("total")+1
      Kill tParameters,tQueryStats
      Set tMDX = tPivot.%GetBaseMDX()
      Set tQuerySC = ..WarmMDX(tMDX,.tParameters,pVerbose,.tQueryStats)
      Merge pStats("queries",tPivotName) = tQueryStats
      Set pStats("queries",tPivotName,"status") = tQuerySC

      If $$$ISERR(tQuerySC) {
        Set pStats("failed") = pStats("failed")+1
        Set tOverallSC = $System.Status.AppendStatus(tOverallSC,tQuerySC)
        Do ..Log("Cache warming failed for "_tPivotName_": "_$System.Status.GetErrorText(tQuerySC))
        If pStopOnError Set tStopped=1 Quit
      } Else {
        Set pStats("succeeded") = pStats("succeeded")+1
      }
    }

    If ('tStopped),(SQLCODE < 0) {
      Set tSC = $$$ERROR($$$GeneralError,"Error while enumerating saved pivots. SQLCODE="_SQLCODE_" "_$Get(%msg))
      Quit
    }
    Set tSC = tOverallSC
  } Catch ex {
    Set tSC = ex.AsStatus()
  }

  If tCursorOpen {
    &sql(CLOSE DiseaseRegistryWarmPivots)
  }
  Set pStats("finished") = $ZTIMESTAMP
  Set pStats("elapsedTime") = $ZH-tStart
  If pVerbose Write !,"Cache warming for [",pCubeName,"]: ",pStats("succeeded")," succeeded, ",pStats("failed")," failed",!
  Quit tSC
}

ClassMethod WarmPivot(pPivotName As %String, ByRef pParameters, pVerbose As %Boolean = 1, Output pStats = "") As %Status
{
  Set tPivot = ##class(%DeepSee.UserLibrary.Utils).%OpenFolderItem(pPivotName,.tSC)
  If $$$ISERR(tSC) Quit tSC
  If '$IsObject(tPivot) Quit $$$ERROR($$$GeneralError,"Saved pivot not found: "_pPivotName)
  If 'tPivot.%IsA("%DeepSee.Dashboard.Pivot") Quit $$$ERROR($$$GeneralError,"Not a saved pivot: "_pPivotName)
  Set tMDX = tPivot.%GetBaseMDX()
  Set tSC = ..WarmMDX(tMDX,.pParameters,pVerbose,.pStats)
  Set pStats("pivot") = tPivot.fullName
  Quit tSC
}

/// Execute arbitrary MDX synchronously. Result caching is enabled by default.
ClassMethod WarmMDX(pMDX As %String, ByRef pParameters, pVerbose As %Boolean = 1, Output pStats = "") As %Status
{
  Kill pStats
  If pMDX = "" Quit $$$ERROR($$$GeneralError,"An MDX query is required")
  Set tStart = $ZH
  Set tResult = ##class(%DeepSee.ResultSet).%ExecuteDirect(pMDX,.pParameters,.tSC)
  If $$$ISERR(tSC) Quit tSC
  If '$IsObject(tResult) Quit $$$ERROR($$$GeneralError,"The query did not return a result set")

  Set pStats("cube") = tResult.%GetCubeName()
  Set pStats("queryKey") = tResult.%GetQueryKey()
  Set pStats("rows") = tResult.%GetRowCount()
  Set pStats("columns") = tResult.%GetColumnCount()
  Set pStats("elapsedTime") = $ZH-tStart
  If pVerbose Write !,"Warmed ",pStats("queryKey")," on [",pStats("cube"),"] in ",pStats("elapsedTime")," seconds",!
  Set tResult = ""
  Quit $$$OK
}

ClassMethod Log(pMessage As %String) As %Status [ Private ]
{
  Quit ##class(%DeepSee.Utils).%WriteToLog("DiseaseReg",pMessage)
}

}
