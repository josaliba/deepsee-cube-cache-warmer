Include %occStatus

/// Warms IRIS Business Intelligence caches after a cube build or synchronization.
/// Saved pivots and their dashboard default-filter variants are executed through
/// the standard cache-enabled %DeepSee.ResultSet API.
Class DHA.BI.CubeCacheWarmer.CacheWarmer Extends %RegisteredObject
{

/// Queue warming in a background process. Use this from Cube Manager Post-Build
/// and Post-Synchronize Code to keep query work outside Cube Manager's process.
ClassMethod QueueCube(pCubeName As %String, pWaitSeconds As %Integer = 600, pVerbose As %Boolean = 0, pStopOnError As %Boolean = 0, Output pJobId As %Integer = 0) As %Status
{
  Set pJobId = 0
  If pCubeName = "" Quit $$$ERROR($$$GeneralError,"A cube name is required")
  If pWaitSeconds < 0 Quit $$$ERROR($$$GeneralError,"pWaitSeconds cannot be negative")

  Job ##class(DHA.BI.CubeCacheWarmer.CacheWarmer).WarmWhenAvailable(pCubeName,pWaitSeconds,pVerbose,pStopOnError)
  Set pJobId = $ZCHILD
  If 'pJobId Quit $$$ERROR($$$GeneralError,"Unable to start a cache warming job for "_pCubeName)
  If pVerbose Write !,"Queued cache warming for [",pCubeName,"] as job ",pJobId,!
  Quit $$$OK
}

/// Coalesce duplicate workers, wait for the cube query lock, and warm saved pivots.
ClassMethod WarmWhenAvailable(pCubeName As %String, pWaitSeconds As %Integer = 600, pVerbose As %Boolean = 0, pStopOnError As %Boolean = 0) As %Status
{
  Set tRunId = 0
  Set tHistorySC = ..StartRun(pCubeName,"QueuedCube",.tRunId)
  Do ..LogStatusError("Unable to start cache-warming history: ",tHistorySC)

  Set tKey = $ZCONVERT(pCubeName,"U")
  Lock +^DHABICCW.CacheWarmerLock("cube",tKey):0
  If '$TEST {
    Do ..FinishEmptyRun(pCubeName,tRunId,0,$$$OK,"Skipped","Another worker was already warming this cube",.tStats)
    Quit $$$OK
  }

  Set tSC = $$$OK
  Set tRunFinished = 0
  Set tStart = $ZH
  Try {
    Set tSC = ..WaitUntilAvailable(pCubeName,pWaitSeconds,pVerbose,.tReason)
    If $$$ISOK(tSC) {
      Set tSC = ..WarmCube(pCubeName,pStopOnError,pVerbose,.tStats,tRunId,"QueuedCube")
      Set tRunFinished = 1
    }
  } Catch ex {
    Set tSC = ex.AsStatus()
  }

  If 'tRunFinished Do ..FinishEmptyRun(pCubeName,tRunId,$ZH-tStart,tSC,"","",.tStats)

  Lock -^DHABICCW.CacheWarmerLock("cube",tKey)
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
ClassMethod WarmCube(pCubeName As %String, pStopOnError As %Boolean = 0, pVerbose As %Boolean = 1, Output pStats = "", pRunId As %Integer = 0, pMode As %String = "DirectCube") As %Status
{
  Do ..InitializeStats(pCubeName,.pStats)
  If 'pRunId Do ..StartRunBestEffort(pCubeName,pMode,.pRunId)
  Set pStats("runId") = $Select(pRunId>0:pRunId,1:0)
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

    // Execute observed queries in true user-frequency order before any fallback
    // dashboard or pivot candidates. The audit recorder excludes these replays.
    Kill tWarmedPivots,tWarmedQueryKeys
    Set tPopularSC = ..WarmPopularQueries(pCubeName,tTarget,tTargetIsSubjectArea,pStopOnError,pVerbose,pRunId,.pStats,.tPopularStopped,.tWarmedQueryKeys)
    If $$$ISERR(tPopularSC) Set tOverallSC = $System.Status.AppendStatus(tOverallSC,tPopularSC)
    If tPopularStopped Set tStopped = 1
    If tStopped {
      Set tSC = tOverallSC
      Quit
    }

    // Dashboard and saved-pivot discovery remains as the zero-frequency fallback.
    Set tDashboardSC = ..WarmDashboardQueries(pCubeName,tTarget,tTargetIsSubjectArea,pStopOnError,pVerbose,pRunId,.pStats,.tDashboardStopped,.tWarmedPivots,.tWarmedQueryKeys)
    If $$$ISERR(tDashboardSC) Set tOverallSC = $System.Status.AppendStatus(tOverallSC,tDashboardSC)
    If tDashboardStopped Set tStopped = 1
    If tStopped {
      Set tSC = tOverallSC
      Quit
    }

    &sql(DECLARE DHABICubeCacheWarmerPivots CURSOR FOR SELECT %ID FROM %DeepSee_Dashboard.Pivot)
    &sql(OPEN DHABICubeCacheWarmerPivots)
    If SQLCODE < 0 {
      Set tSC = $$$ERROR($$$GeneralError,"Unable to enumerate saved pivots. SQLCODE="_SQLCODE_" "_$Get(%msg))
      Quit
    }
    Set tCursorOpen = 1

    For {
      &sql(FETCH DHABICubeCacheWarmerPivots INTO :tPivotId)
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
      Set tPivotKey = $ZCONVERT(tPivotName,"U")
      Continue:$Data(tWarmedPivots(tPivotKey))
      Set tPivots(1000000,tPivotName,tPivotId) = 0
    }

    If SQLCODE < 0 {
      Set tSC = $$$ERROR($$$GeneralError,"Error while enumerating saved pivots. SQLCODE="_SQLCODE_" "_$Get(%msg))
      Quit
    }

    If tCursorOpen {
      &sql(CLOSE DHABICubeCacheWarmerPivots)
      Set tCursorOpen = 0
    }

    Set tPriorityOrder = ""
    For {
      Set tPriorityOrder = $Order(tPivots(tPriorityOrder))
      Quit:tPriorityOrder=""
      Quit:tStopped
      Set tPivotName = ""
      For {
        Set tPivotName = $Order(tPivots(tPriorityOrder,tPivotName))
        Quit:tPivotName=""
        Quit:tStopped
        Set tPivotId = ""
        For {
          Set tPivotId = $Order(tPivots(tPriorityOrder,tPivotName,tPivotId))
          Quit:tPivotId=""
          Quit:tStopped

          Set tOpenSC = $$$OK
          Set tPivot = ##class(%DeepSee.Dashboard.Pivot).%OpenId(tPivotId,,.tOpenSC)
          If $$$ISERR(tOpenSC) {
            Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
            Do ..Log("Unable to reopen saved pivot ID "_tPivotId_": "_$System.Status.GetErrorText(tOpenSC))
            Continue
          }

          Set tDashboardOpenCount = tPivots(tPriorityOrder,tPivotName,tPivotId)
          If tPriorityOrder<1000000 Set pStats("prioritizedPivots") = pStats("prioritizedPivots")+1
          Kill tParameters,tQueryStats
          Set tMDX = tPivot.%GetBaseMDX()
          Set tIdentitySC = ..GetQueryIdentity(tMDX,.tCandidateKey,.tCandidateCube)
          If $$$ISOK(tIdentitySC),$Data(tWarmedQueryKeys(tCandidateKey)) Continue
          Set tQuerySC = ..WarmMDX(tMDX,.tParameters,pVerbose,.tQueryStats,pRunId,tPivotName,"BasePivot","","",0,tDashboardOpenCount,pStats("total")+1)
          If $Get(tQueryStats("queryKey"))'="" Set tWarmedQueryKeys(tQueryStats("queryKey")) = ""
          Do ..RecordQueryResult(tPivotName,.tQueryStats,tQuerySC,.pStats,.tOverallSC)

          If $$$ISERR(tQuerySC) {
            Do ..Log("Cache warming failed for "_tPivotName_": "_$System.Status.GetErrorText(tQuerySC))
            If pStopOnError Set tStopped = 1
          }
        }
      }
    }
    Set tSC = tOverallSC
  } Catch ex {
    Set tSC = ex.AsStatus()
  }

  If tCursorOpen {
    &sql(CLOSE DHABICubeCacheWarmerPivots)
  }
  Set pStats("finished") = ..CurrentTimestamp()
  Set pStats("elapsedTime") = $ZH-tStart
  If pRunId>0 {
    Set tHistorySC = ..FinishRun(pRunId,.pStats,tSC)
    Do ..LogStatusError("Unable to finish cache-warming history: ",tHistorySC)
  }
  If pVerbose Write !,"Cache warming for [",pCubeName,"]: ",pStats("succeeded")," succeeded, ",pStats("failed")," failed",!
  Quit tSC
}

ClassMethod WarmPivot(pPivotName As %String, ByRef pParameters, pVerbose As %Boolean = 1, Output pStats = "") As %Status
{
  Do ..InitializeStats("",.pStats)
  Set tStart = $ZH
  Set tQuerySaved = 0
  Do ..StartRunBestEffort("","DirectPivot",.tRunId)
  Set pStats("runId") = $Select(tRunId>0:tRunId,1:0)
  Set tSC = $$$OK

  Try {
    Set tPivot = ##class(%DeepSee.UserLibrary.Utils).%OpenFolderItem(pPivotName,.tSC)
    If $$$ISERR(tSC) Quit
    If '$IsObject(tPivot) {
      Set tSC = $$$ERROR($$$GeneralError,"Saved pivot not found: "_pPivotName)
      Quit
    }
    If 'tPivot.%IsA("%DeepSee.Dashboard.Pivot") {
      Set tSC = $$$ERROR($$$GeneralError,"Not a saved pivot: "_pPivotName)
      Quit
    }
    Set pStats("cube") = tPivot.cubeName
    Set tMDX = tPivot.%GetBaseMDX()
    Set tSC = ..WarmMDX(tMDX,.pParameters,pVerbose,.pStats,tRunId,tPivot.fullName,"Pivot")
    Set tQuerySaved = 1
    Set pStats("pivot") = tPivot.fullName
  } Catch ex {
    Set tSC = ex.AsStatus()
  }

  Do ..FinishSingleQueryStats(tStart,tSC,.pStats)
  If (tRunId>0),('tQuerySaved) {
    Set tHistorySC = ..SaveQuery(tRunId,pPivotName,.pStats,tSC,"Pivot")
    Do ..LogStatusError("Unable to save cache-warming query history: ",tHistorySC)
  }
  If tRunId>0 {
    Set tHistorySC = ..FinishRun(tRunId,.pStats,tSC)
    Do ..LogStatusError("Unable to finish cache-warming history: ",tHistorySC)
  }
  Quit tSC
}

/// Append one combined %FILTER clause using the same default-value forms accepted
/// by dashboard filter controls. pFilters is keyed by canonical level specification.
ClassMethod ApplyDefaultFilters(pMDX As %String, ByRef pFilters, Output pFilteredMDX As %String, Output pFilterCount As %Integer = 0) As %Status
{
  Set pFilteredMDX = pMDX
  Set pFilterCount = 0
  If pMDX = "" Quit $$$ERROR($$$GeneralError,"An MDX query is required")

  Set tFilterName = ""
  For {
    Set tFilterName = $Order(pFilters(tFilterName))
    Quit:tFilterName=""
    Set tFilterValue = $Get(pFilters(tFilterName))
    Continue:tFilterValue=""
    Set tSC = ..BuildFilterTerm(tFilterName,tFilterValue,.tTerm)
    If $$$ISERR(tSC) Quit
    Set tTerms($Increment(pFilterCount)) = tTerm
  }
  If $$$ISERR($Get(tSC,$$$OK)) Quit tSC
  If pFilterCount = 0 Quit $$$OK

  Set tClause = tTerms(pFilterCount)
  For i = pFilterCount-1:-1:1 Set tClause = "NONEMPTYCROSSJOIN("_tTerms(i)_","_tClause_")"
  Set pFilteredMDX = pMDX_" %FILTER "_tClause
  Quit $$$OK
}

/// Execute arbitrary MDX synchronously. Result caching is enabled by default.
ClassMethod WarmMDX(pMDX As %String, ByRef pParameters, pVerbose As %Boolean = 1, Output pStats = "", pRunId As %Integer = 0, pQueryName As %String = "Ad hoc MDX", pSourceType As %String = "AdHocMDX", pDashboardName As %String = "", pWidgetName As %String = "", pDefaultFilterCount As %Integer = 0, pDashboardOpenCount As %Integer = 0, pPriorityOrder As %Integer = 0, pQueryFrequency As %Integer = 0) As %Status
{
  Do ..InitializeStats("",.pStats)
  Set tOwnRun = (pRunId=0)
  If tOwnRun Do ..StartRunBestEffort("","DirectMDX",.pRunId)
  Set pStats("runId") = $Select(pRunId>0:pRunId,1:0)
  Set tStart = $ZH
  Set tSC = $$$OK
  Set tResult = ""
  Set tAuditSuppressed = 0

  Try {
    If pMDX = "" {
      Set tSC = $$$ERROR($$$GeneralError,"An MDX query is required")
      Quit
    }
    Set ^||DHABICCW.CacheWarmer("active") = $Get(^||DHABICCW.CacheWarmer("active"))+1
    Set tAuditSuppressed = 1
    Set tResult = ##class(%DeepSee.ResultSet).%ExecuteDirect(pMDX,.pParameters,.tSC)
    Set ^||DHABICCW.CacheWarmer("active") = ^||DHABICCW.CacheWarmer("active")-1
    If ^||DHABICCW.CacheWarmer("active")<1 Kill ^||DHABICCW.CacheWarmer("active")
    Set tAuditSuppressed = 0
    If $$$ISERR(tSC) Quit
    If '$IsObject(tResult) {
      Set tSC = $$$ERROR($$$GeneralError,"The query did not return a result set")
      Quit
    }

    Set pStats("cube") = tResult.%GetCubeName()
    Set pStats("queryKey") = tResult.%GetQueryKey()
    Set pStats("rows") = tResult.%GetRowCount()
    Set pStats("columns") = tResult.%GetColumnCount()
  } Catch ex {
    If tAuditSuppressed,$Get(^||DHABICCW.CacheWarmer("active"))>0 {
      Set ^||DHABICCW.CacheWarmer("active") = ^||DHABICCW.CacheWarmer("active")-1
      If ^||DHABICCW.CacheWarmer("active")<1 Kill ^||DHABICCW.CacheWarmer("active")
    }
    Set tSC = ex.AsStatus()
  }

  Do ..FinishSingleQueryStats(tStart,tSC,.pStats)
  If (pRunId>0),(pStats("cube")'="") {
    Set tHistorySC = ..UpdateRunCube(pRunId,pStats("cube"))
    Do ..LogStatusError("Unable to update cache-warming history: ",tHistorySC)
  }
  If pRunId>0 {
    Set tHistorySC = ..SaveQuery(pRunId,pQueryName,.pStats,tSC,pSourceType,pDashboardName,pWidgetName,pDefaultFilterCount,pDashboardOpenCount,pPriorityOrder,pQueryFrequency)
    Do ..LogStatusError("Unable to save cache-warming query history: ",tHistorySC)
  }
  If (tOwnRun),(pRunId>0) {
    Set tHistorySC = ..FinishRun(pRunId,.pStats,tSC)
    Do ..LogStatusError("Unable to finish cache-warming history: ",tHistorySC)
  }
  If pVerbose,$$$ISOK(tSC) Write !,"Warmed ",pStats("queryKey")," on [",pStats("cube"),"] in ",pStats("elapsedTime")," seconds",!
  Set tResult = ""
  Quit tSC
}

/// Execute previously observed user queries in descending execution-frequency
/// order. Recency and query key provide deterministic tie breakers.
ClassMethod WarmPopularQueries(pCubeName As %String, pTarget As %String, pTargetIsSubjectArea As %Boolean, pStopOnError As %Boolean, pVerbose As %Boolean, pRunId As %Integer, ByRef pStats, Output pStopped As %Boolean, Output pWarmedQueryKeys) As %Status [ Private ]
{
  Set pStopped = 0
  Kill pWarmedQueryKeys
  Set tOverallSC = $$$OK
  Set tFrequencyRank = 0

  &sql(DECLARE DHABICubeCacheWarmerFrequency CURSOR FOR
    SELECT QueryKey, CubeName, MDX, ExecutionCount
    FROM DHA_BI_CubeCacheWarmer_Model.QueryUsage
    WHERE ExecutionCount > 0
    ORDER BY ExecutionCount DESC, LastExecutedAt DESC, QueryKey)
  &sql(OPEN DHABICubeCacheWarmerFrequency)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to enumerate query frequency. SQLCODE="_SQLCODE_" "_$Get(%msg))

  For {
    &sql(FETCH DHABICubeCacheWarmerFrequency INTO :tQueryKey,:tQueryCube,:tMDX,:tFrequency)
    Quit:SQLCODE'=0
    Set tQueryBase = ##class(%DeepSee.Utils).%GetBaseCube(tQueryCube)
    If tQueryBase = "" Set tQueryBase = tQueryCube
    Set tMatches = $Select(pTargetIsSubjectArea:$ZCONVERT(tQueryCube,"U")=pTarget,1:$ZCONVERT(tQueryBase,"U")=pTarget)
    Continue:'tMatches
    Continue:tMDX=""
    Continue:$Data(pWarmedQueryKeys(tQueryKey))

    Set tFrequencyRank = tFrequencyRank+1
    Kill tParameters,tQueryStats
    Set tQueryName = "Frequency #"_tFrequencyRank_" ["_tQueryKey_"]"
    Set tQuerySC = ..WarmMDX(tMDX,.tParameters,pVerbose,.tQueryStats,pRunId,tQueryName,"QueryFrequency","","",0,0,tFrequencyRank,tFrequency)
    If $Get(tQueryStats("queryKey"))'="" Set pWarmedQueryKeys(tQueryStats("queryKey")) = ""
    Do ..RecordQueryResult(tQueryName,.tQueryStats,tQuerySC,.pStats,.tOverallSC)
    Set pStats("frequencyQueries") = pStats("frequencyQueries")+1

    If $$$ISERR(tQuerySC) {
      Do ..Log("Frequency-ordered warming failed for "_tQueryKey_": "_$System.Status.GetErrorText(tQuerySC))
      If pStopOnError Set pStopped = 1
    }
    Quit:pStopped
  }

  Set tFetchCode = SQLCODE
  &sql(CLOSE DHABICubeCacheWarmerFrequency)
  If ('pStopped),(tFetchCode<0) Quit $$$ERROR($$$GeneralError,"Error while enumerating query frequency. SQLCODE="_tFetchCode_" "_$Get(%msg))
  Quit tOverallSC
}

/// Prepare without executing so duplicate candidates can be recognized before
/// they are added to the cache or to execution history.
ClassMethod GetQueryIdentity(pMDX As %String, Output pQueryKey As %String, Output pCubeName As %String) As %Status [ Private ]
{
  Set pQueryKey = "", pCubeName = ""
  Kill tVariables
  Set tResult = ##class(%DeepSee.ResultSet).%New()
  Set tSC = tResult.%PrepareMDX(pMDX,.tVariables,.tResolvedMDX)
  If $$$ISERR(tSC) Quit tSC
  Set pQueryKey = tResult.%GetQueryKey()
  Set pCubeName = tResult.%GetCubeName()
  Quit $$$OK
}

/// Warm each dashboard's saved base pivots and default-filter variants.
/// Dashboards are ordered by recorded opens, then by IRIS BI's last-accessed
/// timestamp. pWarmedPivots prevents repeated base queries when dashboards share
/// a saved pivot and lets the caller run unreferenced pivots afterwards.
ClassMethod WarmDashboardQueries(pCubeName As %String, pTarget As %String, pTargetIsSubjectArea As %Boolean, pStopOnError As %Boolean, pVerbose As %Boolean, pRunId As %Integer, ByRef pStats, Output pStopped As %Boolean, Output pWarmedPivots, ByRef pWarmedQueryKeys) As %Status [ Private ]
{
  Set pStopped = 0
  Kill pWarmedPivots
  Set tOverallSC = $$$OK
  Set tDashboardRank = 0

  &sql(DECLARE DHABICubeCacheWarmerDashboards CURSOR FOR
    SELECT d.%ID, COALESCE(u.OpenCount,0)
    FROM %DeepSee_Dashboard.Definition d
    LEFT JOIN DHA_BI_CubeCacheWarmer_Model.DashboardUsage u ON u.DashboardName = d.fullName
    ORDER BY COALESCE(u.OpenCount,0) DESC, d.lastAccessed DESC, d.fullName)
  &sql(OPEN DHABICubeCacheWarmerDashboards)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to enumerate dashboards. SQLCODE="_SQLCODE_" "_$Get(%msg))

  For {
    &sql(FETCH DHABICubeCacheWarmerDashboards INTO :tDashboardId,:tDashboardOpenCount)
    Quit:SQLCODE'=0
    Set tDashboardRank = tDashboardRank+1
    If tDashboardOpenCount>0 Set pStats("priorityDashboards") = pStats("priorityDashboards")+1

    Set tOpenSC = $$$OK
    Set tDashboard = ##class(%DeepSee.Dashboard.Definition).%OpenId(tDashboardId,,.tOpenSC)
    If $$$ISERR(tOpenSC) {
      Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
      Do ..Log("Unable to inspect dashboard ID "_tDashboardId_": "_$System.Status.GetErrorText(tOpenSC))
      Continue
    }

    Kill tWidgetName,tWidgetIndex,tWidgetSource,tFilterSet
    Set tWidgetCount = tDashboard.widgets.Count()
    For tWidgetIndexNumber = 1:1:tWidgetCount {
      Set tWidget = tDashboard.widgets.GetAt(tWidgetIndexNumber)
      Set tName = tWidget.name
      If tName = "" Set tName = "$widget"_tWidgetIndexNumber
      Set tWidgetName(tWidgetIndexNumber) = tName
      Set tWidgetIndex($ZCONVERT(tName,"U"),tWidgetIndexNumber) = ""
      Set tWidgetSource(tWidgetIndexNumber) = tWidget.dataSource

      Set tFilterName = ""
      For {
        Set tFilterValue = tWidget.filterState.GetNext(.tFilterName)
        Quit:tFilterName=""
        If tFilterValue'="" Set tFilterSet(tWidgetIndexNumber,tFilterName) = tFilterValue
      }
    }

    // Dashboard controls are stored on widgets. Their target determines which
    // widget receives the initial filter value.
    For tOwnerIndex = 1:1:tWidgetCount {
      Set tOwnerWidget = tDashboard.widgets.GetAt(tOwnerIndex)
      For tControlIndex = 1:1:tOwnerWidget.controls.Count() {
        Set tControl = tOwnerWidget.controls.GetAt(tControlIndex)
        Set tAction = $ZCONVERT(tControl.action,"U")
        Continue:(tAction'="")&&(tAction'="APPLYFILTER")&&(tAction'="SETFILTER")
        Set tFilterName = tControl.targetProperty
        Continue:tFilterName=""

        Set tResolveSC = ..ResolveDefaultFilterValue(tControl.value,.tFilterValue)
        If $$$ISERR(tResolveSC) {
          Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
          Do ..Log("Unable to resolve dashboard default for "_tDashboard.fullName_" / "_tFilterName_": "_$System.Status.GetErrorText(tResolveSC))
          Continue
        }
        Continue:tFilterValue=""

        Set tTargetList = tControl.target
        If tTargetList = "" {
          Set tFilterSet(tOwnerIndex,tFilterName) = tFilterValue
        } ElseIf tTargetList = "*" {
          For tTargetIndex = 1:1:tWidgetCount Set tFilterSet(tTargetIndex,tFilterName) = tFilterValue
        } Else {
          For tTargetPiece = 1:1:$Length(tTargetList,",") {
            Set tTargetName = $ZSTRIP($Piece(tTargetList,",",tTargetPiece),"<>W")
            If tTargetName = "" Set tTargetName = tWidgetName(tOwnerIndex)
            Set tTargetIndex = ""
            For {
              Set tTargetIndex = $Order(tWidgetIndex($ZCONVERT(tTargetName,"U"),tTargetIndex))
              Quit:tTargetIndex=""
              Set tFilterSet(tTargetIndex,tFilterName) = tFilterValue
            }
          }
        }
      }
    }

    For tWidgetIndexNumber = 1:1:tWidgetCount {
      Quit:pStopped
      Set tDataSource = tWidgetSource(tWidgetIndexNumber)
      Set tExtension = $ZCONVERT($Piece(tDataSource,".",$Length(tDataSource,".")),"L")
      Continue:tExtension'="pivot"

      Set tPivotSC = $$$OK
      Set tPivot = ##class(%DeepSee.UserLibrary.Utils).%OpenFolderItem(tDataSource,.tPivotSC)
      If $$$ISERR(tPivotSC) {
        Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
        Do ..Log("Unable to inspect "_tDashboard.fullName_" / "_tWidgetName(tWidgetIndexNumber)_": "_$System.Status.GetErrorText(tPivotSC))
        Continue
      }
      If '$IsObject(tPivot) {
        Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
        Do ..Log("Unable to inspect "_tDashboard.fullName_" / "_tWidgetName(tWidgetIndexNumber)_": dashboard pivot not found: "_tDataSource)
        Continue
      }
      If 'tPivot.%IsA("%DeepSee.Dashboard.Pivot") {
        Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
        Do ..Log("Unable to inspect "_tDashboard.fullName_" / "_tWidgetName(tWidgetIndexNumber)_": data source is not a pivot: "_tDataSource)
        Continue
      }

      Set tPivotCube = tPivot.cubeName
      Set tPivotBase = ##class(%DeepSee.Utils).%GetBaseCube(tPivotCube)
      If tPivotBase = "" Set tPivotBase = tPivotCube
      Set tMatches = $Select(pTargetIsSubjectArea:$ZCONVERT(tPivotCube,"U")=pTarget,1:$ZCONVERT(tPivotBase,"U")=pTarget)
      Continue:'tMatches

      Set tPivotKey = $ZCONVERT(tPivot.fullName,"U")
      If '$Data(pWarmedPivots(tPivotKey)) {
        Set pWarmedPivots(tPivotKey) = ""
        Set tBaseMDX = tPivot.%GetBaseMDX()
        Set tIdentitySC = ..GetQueryIdentity(tBaseMDX,.tCandidateKey,.tCandidateCube)
        If $$$ISERR(tIdentitySC)||'$Data(pWarmedQueryKeys(tCandidateKey)) {
          Set pStats("dashboardBaseQueries") = pStats("dashboardBaseQueries")+1
          Set pStats("prioritizedPivots") = pStats("prioritizedPivots")+1
          Kill tParameters,tQueryStats
          Set tBaseQuerySC = ..WarmMDX(tBaseMDX,.tParameters,pVerbose,.tQueryStats,pRunId,tPivot.fullName,"DashboardBase",tDashboard.fullName,tWidgetName(tWidgetIndexNumber),0,tDashboardOpenCount,pStats("total")+1)
          If $Get(tQueryStats("queryKey"))'="" Set pWarmedQueryKeys(tQueryStats("queryKey")) = ""
          Do ..RecordQueryResult(tPivot.fullName,.tQueryStats,tBaseQuerySC,.pStats,.tOverallSC)

          If $$$ISERR(tBaseQuerySC) {
            Do ..Log("Dashboard base-pivot warming failed for "_tPivot.fullName_": "_$System.Status.GetErrorText(tBaseQuerySC))
            If pStopOnError Set pStopped = 1
          }
        }
      }
      Quit:pStopped
      Continue:'$Data(tFilterSet(tWidgetIndexNumber))

      Kill tAvailableFilters,tVisited,tAllowedFilters,tApplicableFilters
      Set tFilterSC = ##class(%DeepSee.Dashboard.Utils).%GetFiltersForDataSource(tDataSource,.tAvailableFilters,.tVisited)
      If $$$ISERR(tFilterSC) {
        Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
        Do ..Log("Unable to inspect filters for "_tDataSource_": "_$System.Status.GetErrorText(tFilterSC))
        Continue
      }
      Set tAvailableIndex = ""
      For {
        Set tAvailableIndex = $Order(tAvailableFilters(tAvailableIndex))
        Quit:tAvailableIndex=""
        Set tCanonicalFilter = $ListGet(tAvailableFilters(tAvailableIndex),2)
        If tCanonicalFilter'="" Set tAllowedFilters($ZCONVERT(tCanonicalFilter,"U")) = tCanonicalFilter
      }

      Set tFilterName = ""
      For {
        Set tFilterName = $Order(tFilterSet(tWidgetIndexNumber,tFilterName))
        Quit:tFilterName=""
        Set tCanonicalFilter = $Get(tAllowedFilters($ZCONVERT(tFilterName,"U")))
        Continue:tCanonicalFilter=""
        Set tApplicableFilters(tCanonicalFilter) = tFilterSet(tWidgetIndexNumber,tFilterName)
      }
      Continue:'$Data(tApplicableFilters)

      Set tFilterSC = ..ApplyDefaultFilters(tPivot.%GetBaseMDX(),.tApplicableFilters,.tFilteredMDX,.tDefaultFilterCount)
      If $$$ISERR(tFilterSC) {
        Set pStats("enumerationErrors") = pStats("enumerationErrors")+1
        Do ..Log("Unable to construct dashboard defaults for "_tDashboard.fullName_" / "_tWidgetName(tWidgetIndexNumber)_": "_$System.Status.GetErrorText(tFilterSC))
        Continue
      }
      Continue:tDefaultFilterCount=0

      Set tQueryName = "Dashboard "_tDashboard.fullName_" / "_tWidgetName(tWidgetIndexNumber)_" [defaults]"
      Set tIdentitySC = ..GetQueryIdentity(tFilteredMDX,.tCandidateKey,.tCandidateCube)
      Continue:$$$ISOK(tIdentitySC)&&$Data(pWarmedQueryKeys(tCandidateKey))
      Set pStats("dashboardDefaults") = pStats("dashboardDefaults")+1
      Kill tParameters,tQueryStats
      Set tQuerySC = ..WarmMDX(tFilteredMDX,.tParameters,pVerbose,.tQueryStats,pRunId,tQueryName,"DashboardDefault",tDashboard.fullName,tWidgetName(tWidgetIndexNumber),tDefaultFilterCount,tDashboardOpenCount,pStats("total")+1)
      If $Get(tQueryStats("queryKey"))'="" Set pWarmedQueryKeys(tQueryStats("queryKey")) = ""
      Do ..RecordQueryResult(tQueryName,.tQueryStats,tQuerySC,.pStats,.tOverallSC)

      If $$$ISERR(tQuerySC) {
        Do ..Log("Dashboard-default warming failed for "_tQueryName_": "_$System.Status.GetErrorText(tQuerySC))
        If pStopOnError Set pStopped = 1
      }
    }
    Quit:pStopped
  }

  Set tFetchCode = SQLCODE
  &sql(CLOSE DHABICubeCacheWarmerDashboards)
  If ('pStopped),(tFetchCode<0) Quit $$$ERROR($$$GeneralError,"Error while enumerating dashboards. SQLCODE="_tFetchCode_" "_$Get(%msg))
  Quit tOverallSC
}

ClassMethod ResolveDefaultFilterValue(pValue As %String, Output pResolved As %String) As %Status [ Private ]
{
  Set pResolved = pValue
  If $Extract(pValue,1) = "@" {
    Set pResolved = ##class(%DeepSee.UserPortal.Utils).%GetUserSetting($Extract(pValue,2,*),.tSC)
    Quit tSC
  }
  Quit $$$OK
}

ClassMethod BuildFilterTerm(pLevel As %String, pValue As %String, Output pTerm As %String) As %Status [ Private ]
{
  Set pTerm = ""
  Set tLevel = $ZSTRIP(pLevel,"<>W")
  Set tValue = $ZSTRIP(pValue,"<>W")
  If tLevel = "" Quit $$$ERROR($$$GeneralError,"A dashboard filter level is required")
  If tValue = "" Quit $$$ERROR($$$GeneralError,"A dashboard filter value is required")

  Set tIsNot = 0
  If ($ZCONVERT($Extract(tValue,1,4),"U")="%NOT"),(($Extract(tValue,5)=" ")||($Extract(tValue,5)="{")) {
    Set tIsNot = 1
    If $Extract(tValue,5) = "{" {
      Set tValue = $Extract(tValue,5,*)
    } Else {
      Set tValue = $ZSTRIP($Extract(tValue,6,*),"<>W")
    }
  }

  If $Extract(tValue,1,2) = "&[" {
    If tIsNot {
      Set pTerm = tLevel_"."_tValue_".%NOT"
    } ElseIf tValue["]:&[" {
      Set pTerm = "%OR("_tLevel_"."_tValue_")"
    } Else {
      Set pTerm = tLevel_"."_tValue
    }
    Quit $$$OK
  }

  If $Extract(tValue,1) = "{" {
    If $Extract(tValue,*)'="}" Quit $$$ERROR($$$GeneralError,"Invalid dashboard filter set: "_tValue)
    Set tBody = $Extract(tValue,2,*-1)
    If tBody = "" Quit $$$ERROR($$$GeneralError,"Dashboard filter set cannot be empty")
    Set tItemCount = $Length(tBody,"],&[")
    Set tSet = ""
    For i = 1:1:tItemCount {
      Set tItem = $Piece(tBody,"],&[",i)
      If $Extract(tItem,1)'="&" Set tItem = "&["_tItem
      If i'=tItemCount Set tItem = tItem_"]"
      Set tQualified = tLevel_"."_tItem
      If tIsNot Set tQualified = tQualified_".%NOT"
      Set tSet = tSet_$Select(tSet="":"",1:",")_tQualified
    }
    Set pTerm = $Select(tIsNot:"("_tSet_")",1:"%OR({"_tSet_"})")
    Quit $$$OK
  }

  Set tEscapedValue = $Replace(tValue,"]","]]")
  Set pTerm = tLevel_".&["_tEscapedValue_"]"
  If tIsNot Set pTerm = pTerm_".%NOT"
  Quit $$$OK
}

/// Delete completed cache-warming history older than pDaysToKeep.
ClassMethod PurgeHistory(pDaysToKeep As %Integer = 30, Output pDeleted As %Integer = 0) As %Status
{
  Set pDeleted = 0
  If pDaysToKeep < 0 Quit $$$ERROR($$$GeneralError,"pDaysToKeep cannot be negative")

  Set tNowH = $ZTIMESTAMP
  Set tCutoffH = ($Piece(tNowH,",",1)-pDaysToKeep)_","_$Piece(tNowH,",",2)
  Set tCutoff = $ZDATETIME(tCutoffH,3,1,6)
  Set tSC = $$$OK

  &sql(DECLARE DHABICubeCacheWarmerOldRuns CURSOR FOR
    SELECT %ID FROM DHA_BI_CubeCacheWarmer_Model.CacheWarmRun
    WHERE StartedAt < :tCutoff AND Outcome <> 'Running')
  &sql(OPEN DHABICubeCacheWarmerOldRuns)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to enumerate cache-warming history. SQLCODE="_SQLCODE_" "_$Get(%msg))

  For {
    &sql(FETCH DHABICubeCacheWarmerOldRuns INTO :tRunId)
    Quit:SQLCODE'=0
    Set tSC = ##class(DHA.BI.CubeCacheWarmer.Model.CacheWarmRun).%DeleteId(tRunId)
    Quit:$$$ISERR(tSC)
    Set pDeleted = pDeleted+1
  }
  Set tFetchCode = SQLCODE
  &sql(CLOSE DHABICubeCacheWarmerOldRuns)
  If $$$ISERR(tSC) Quit tSC
  If tFetchCode < 0 Quit $$$ERROR($$$GeneralError,"Unable to fetch cache-warming history. SQLCODE="_tFetchCode_" "_$Get(%msg))
  Quit $$$OK
}

ClassMethod FinishSingleQueryStats(pStart As %Double, pSC As %Status, ByRef pStats) [ Private ]
{
  Set pStats("elapsedTime") = $ZH-pStart
  Set pStats("finished") = ..CurrentTimestamp()
  Set pStats("total") = 1
  Set pStats("succeeded") = $Select($$$ISOK(pSC):1,1:0)
  Set pStats("failed") = $Select($$$ISERR(pSC):1,1:0)
}

ClassMethod RecordQueryResult(pQueryName As %String, ByRef pQueryStats, pQuerySC As %Status, ByRef pStats, ByRef pOverallSC) [ Private ]
{
  Set pStats("total") = pStats("total")+1
  Merge pStats("queries",pQueryName) = pQueryStats
  Set pStats("queries",pQueryName,"status") = pQuerySC
  If $$$ISERR(pQuerySC) {
    Set pStats("failed") = pStats("failed")+1
    Set pOverallSC = $System.Status.AppendStatus(pOverallSC,pQuerySC)
  } Else {
    Set pStats("succeeded") = pStats("succeeded")+1
  }
}

ClassMethod InitializeStats(pCubeName As %String, Output pStats) [ Private ]
{
  Kill pStats
  Set pStats("cube") = pCubeName
  Set pStats("total") = 0, pStats("succeeded") = 0, pStats("failed") = 0
  Set pStats("enumerationErrors") = 0, pStats("dashboardDefaults") = 0, pStats("dashboardBaseQueries") = 0
  Set pStats("priorityDashboards") = 0, pStats("prioritizedPivots") = 0
  Set pStats("frequencyQueries") = 0
  Set pStats("started") = ..CurrentTimestamp()
  Set pStats("elapsedTime") = 0
}

ClassMethod StartRunBestEffort(pCubeName As %String, pMode As %String, Output pRunId As %Integer) [ Private ]
{
  Set tSC = ..StartRun(pCubeName,pMode,.pRunId)
  If $$$ISERR(tSC) {
    Do ..Log("Unable to start cache-warming history: "_$System.Status.GetErrorText(tSC))
    Set pRunId = -1
  }
}

ClassMethod FinishEmptyRun(pCubeName As %String, pRunId As %Integer, pElapsedSeconds As %Double, pSC As %Status, pOutcome As %String, pStatusText As %String, Output pStats) [ Private ]
{
  Do ..InitializeStats(pCubeName,.pStats)
  Set pStats("finished") = ..CurrentTimestamp()
  Set pStats("elapsedTime") = pElapsedSeconds
  Set pStats("runId") = pRunId
  If pRunId>0 {
    Set tHistorySC = ..FinishRun(pRunId,.pStats,pSC,pOutcome,pStatusText)
    Do ..LogStatusError("Unable to finish cache-warming history: ",tHistorySC)
  }
}

ClassMethod StartRun(pCubeName As %String, pMode As %String, Output pRunId As %Integer) As %Status [ Private ]
{
  Set pRunId = 0
  Set tRun = ##class(DHA.BI.CubeCacheWarmer.Model.CacheWarmRun).%New()
  Set tRun.CubeName = $Extract(pCubeName,1,128)
  Set tRun.Mode = $Extract(pMode,1,32)
  Set tRun.Outcome = "Running"
  Set tRun.StartedAt = ..CurrentTimestamp()
  Set tRun.ProcessId = $Extract($JOB,1,128)
  Set tSC = tRun.%Save()
  If $$$ISOK(tSC) Set pRunId = tRun.%Id()
  Quit tSC
}

ClassMethod UpdateRunCube(pRunId As %Integer, pCubeName As %String) As %Status [ Private ]
{
  If pRunId < 1 Quit $$$OK
  Set tRun = ##class(DHA.BI.CubeCacheWarmer.Model.CacheWarmRun).%OpenId(pRunId,,.tSC)
  If $$$ISERR(tSC) Quit tSC
  If '$IsObject(tRun) Quit $$$ERROR($$$GeneralError,"Cache-warming run not found: "_pRunId)
  Set tRun.CubeName = $Extract(pCubeName,1,128)
  Quit tRun.%Save()
}

ClassMethod SaveQuery(pRunId As %Integer, pQueryName As %String, ByRef pStats, pSC As %Status, pSourceType As %String = "AdHocMDX", pDashboardName As %String = "", pWidgetName As %String = "", pDefaultFilterCount As %Integer = 0, pDashboardOpenCount As %Integer = 0, pPriorityOrder As %Integer = 0, pQueryFrequency As %Integer = 0) As %Status [ Private ]
{
  If pRunId < 1 Quit $$$OK
  Set tRun = ##class(DHA.BI.CubeCacheWarmer.Model.CacheWarmRun).%OpenId(pRunId,,.tOpenSC)
  If $$$ISERR(tOpenSC) Quit tOpenSC
  If '$IsObject(tRun) Quit $$$ERROR($$$GeneralError,"Cache-warming run not found: "_pRunId)

  Set tQuery = ##class(DHA.BI.CubeCacheWarmer.Model.CacheWarmQuery).%New()
  Set tQuery.Run = tRun
  Set tQuery.QueryName = $Extract(pQueryName,1,512)
  Set tQuery.SourceType = $Extract(pSourceType,1,32)
  Set tQuery.DashboardName = $Extract(pDashboardName,1,512)
  Set tQuery.WidgetName = $Extract(pWidgetName,1,255)
  Set tQuery.DefaultFilterCount = pDefaultFilterCount
  Set tQuery.DashboardOpenCount = pDashboardOpenCount
  Set tQuery.PriorityOrder = pPriorityOrder
  Set tQuery.QueryFrequency = pQueryFrequency
  Set tQuery.CubeName = $Extract($Get(pStats("cube")),1,128)
  Set tQuery.QueryKey = $Extract($Get(pStats("queryKey")),1,128)
  Set tQuery.RowCount = $Get(pStats("rows"),0)
  Set tQuery.ColumnCount = $Get(pStats("columns"),0)
  Set tQuery.ElapsedSeconds = $Get(pStats("elapsedTime"),0)
  Set tQuery.Success = $$$ISOK(pSC)
  Set tQuery.StatusText = $Extract($Select($$$ISOK(pSC):"OK",1:$System.Status.GetErrorText(pSC)),1,4096)
  Quit tQuery.%Save()
}

ClassMethod FinishRun(pRunId As %Integer, ByRef pStats, pSC As %Status, pOutcome As %String = "", pStatusText As %String = "") As %Status [ Private ]
{
  If pRunId < 1 Quit $$$OK
  Set tRun = ##class(DHA.BI.CubeCacheWarmer.Model.CacheWarmRun).%OpenId(pRunId,,.tOpenSC)
  If $$$ISERR(tOpenSC) Quit tOpenSC
  If '$IsObject(tRun) Quit $$$ERROR($$$GeneralError,"Cache-warming run not found: "_pRunId)

  If $Get(pStats("cube"))'="" Set tRun.CubeName = $Extract(pStats("cube"),1,128)
  Set tRun.FinishedAt = ..CurrentTimestamp()
  Set tRun.TotalQueries = $Get(pStats("total"),0)
  Set tRun.SucceededQueries = $Get(pStats("succeeded"),0)
  Set tRun.FailedQueries = $Get(pStats("failed"),0)
  Set tRun.EnumerationErrors = $Get(pStats("enumerationErrors"),0)
  Set tRun.ElapsedSeconds = $Get(pStats("elapsedTime"),0)
  If pOutcome = "" {
    Set pOutcome = $Select($$$ISOK(pSC)&&(tRun.EnumerationErrors=0):"Success",tRun.SucceededQueries>0:"PartialFailure",1:"Failure")
  }
  Set tRun.Outcome = pOutcome
  If pStatusText = "" Set pStatusText = $Select(tRun.EnumerationErrors>0:"Completed with "_tRun.EnumerationErrors_" enumeration or configuration error(s)",$$$ISOK(pSC):"OK",1:$System.Status.GetErrorText(pSC))
  Set tRun.StatusText = $Extract(pStatusText,1,4096)
  Quit tRun.%Save()
}

ClassMethod CurrentTimestamp() As %TimeStamp [ Private ]
{
  Quit $ZDATETIME($ZTIMESTAMP,3,1,6)
}

ClassMethod LogStatusError(pPrefix As %String, pSC As %Status) [ Private ]
{
  If $$$ISERR(pSC) Do ..Log(pPrefix_$System.Status.GetErrorText(pSC))
}

ClassMethod Log(pMessage As %String) As %Status [ Private ]
{
  Quit ##class(%DeepSee.Utils).%WriteToLog("DHABICCW",pMessage)
}

}
