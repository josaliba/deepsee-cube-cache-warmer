Class App.Installer
{

XData Setup
{
<Manifest>
  <Default Name="SourceDir" Value="/workspace/src"/>
  <Default Name="CacheWarmerSourceDir" Value="/workspace/packages/iris-bi-cache-warmer/src"/>
  <Default Name="Namespace" Value="DISEASEREGISTRY"/>
  <Default Name="DatabaseDir" Value="/durable/databases/DISEASEREGISTRY"/>
  <Namespace Name="${Namespace}" Code="${Namespace}" Data="${Namespace}" Create="yes" Ensemble="1">
    <Configuration>
      <Database Name="${Namespace}" Dir="${DatabaseDir}" Create="yes" Resource="%DB_${Namespace}"/>
    </Configuration>
    <Import File="${CacheWarmerSourceDir}" Flags="ck" Recurse="1"/>
    <Import File="${SourceDir}" Flags="ck" Recurse="1"/>
  </Namespace>
</Manifest>
}

ClassMethod Setup(ByRef pVars, pLogLevel As %Integer = 3, pInstaller As %Installer.Installer, pLogger As %Installer.AbstractLogger) As %Status [ CodeMode = objectgenerator, Internal ]
{
  Quit ##class(%Installer.Manifest).%Generate(%compiledclass, %code, "Setup")
}

/// Create the application namespace once, then import current source on every start.
ClassMethod Bootstrap() As %Status
{
  Set sc = ##class(Security.Users).UnExpireUserPasswords("_SYSTEM,SuperUser", .updatedUsers)
  If $SYSTEM.Status.IsError(sc) Quit sc

  If '##class(%SYS.Namespace).Exists("DISEASEREGISTRY") {
    Set sc = ..Setup()
    If $SYSTEM.Status.IsError(sc) Quit sc
  } ElseIf '##class(%Library.EnsembleMgr).IsEnsembleNamespace("DISEASEREGISTRY") {
    // Upgrade volumes created by a bootstrap that used Ensemble="0".
    Set sc = ##class(%Library.EnsembleMgr).EnableNamespace("DISEASEREGISTRY", 1)
    If $SYSTEM.Status.IsError(sc) Quit sc
  }

  Set previousNamespace = $Namespace
  Set $Namespace = "DISEASEREGISTRY"
  Set sc = $SYSTEM.OBJ.LoadDir("/workspace/packages/iris-bi-cache-warmer/src", "ck", , 1)
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = $SYSTEM.OBJ.LoadDir("/workspace/src", "ck", , 1)
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ..RemoveLegacyDashboardUsageHook()
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(%DeepSee.CubeManager.Utils).SetActiveRegistry("DiseaseRegistry.CubeRegistry", 1)
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(%DeepSee.CubeManager.Utils).ScheduleUpdaterTasks()
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(CubeCacheWarmer.Installer).Install()
  }
  Set $Namespace = previousNamespace

  Quit sc
}

/// One-time upgrade from the pre-package Disease Registry class name. Any
/// unrelated dashboard audit command is preserved.
ClassMethod RemoveLegacyDashboardUsageHook() As %Status
{
  Set legacyCommand = "do ##class(DiseaseRegistry.Util.DashboardUsage).Record(%dsDashboard)"
  Set currentCommand = $Get(^DeepSee.AuditCode)
  Set endPosition = $Find(currentCommand,legacyCommand)
  If 'endPosition Quit 1

  Set startPosition = endPosition-$Length(legacyCommand)
  Set beforeCommand = $ZSTRIP($Extract(currentCommand,1,startPosition-1),"<>W")
  Set afterCommand = $ZSTRIP($Extract(currentCommand,endPosition,*),"<>W")
  Set currentCommand = beforeCommand_$Select((beforeCommand="")||(afterCommand=""):"",1:" ")_afterCommand
  If currentCommand="" {
    Kill ^DeepSee.AuditCode
  } Else {
    Set ^DeepSee.AuditCode = currentCommand
  }
  Quit 1
}

}
