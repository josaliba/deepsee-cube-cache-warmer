Include %occStatus

Class App.Installer
{

XData Setup
{
<Manifest>
  <Default Name="SourceDir" Value="/workspace/src"/>
  <Default Name="CacheWarmerSourceDir" Value="/workspace/packages/dha-bi-cube-cache-warmer/src"/>
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
  Set sc = ..MigrateCacheWarmerPackageCase()
  If $SYSTEM.Status.IsError(sc) {
    Set $Namespace = previousNamespace
    Quit sc
  }
  Set sc = $SYSTEM.OBJ.LoadDir("/workspace/packages/dha-bi-cube-cache-warmer/src", "ck", , 1)
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = $SYSTEM.OBJ.LoadDir("/workspace/src", "ck", , 1)
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(%DeepSee.CubeManager.Utils).SetActiveRegistry("DiseaseRegistry.CubeRegistry", 1)
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(%DeepSee.CubeManager.Utils).ScheduleUpdaterTasks()
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(dha.bi.CubeCacheWarmer.Installer).Install()
  }
  Set $Namespace = previousNamespace

  Quit sc
}

/// IRIS class names are case-insensitive but retain canonical case. Remove only
/// the old uppercase definitions and extent registrations before importing the
/// lowercase package. Persistent ^DHABICCW data is deliberately preserved.
ClassMethod MigrateCacheWarmerPackageCase() As %Status
{
  Set definition = ##class(%Dictionary.ClassDefinition).%OpenId("DHA.BI.CubeCacheWarmer.CacheWarmer",,.openSC)
  If $SYSTEM.Status.IsError(openSC) Quit $$$OK
  If '$IsObject(definition) Quit $$$OK
  If definition.Name'="DHA.BI.CubeCacheWarmer.CacheWarmer" Quit $$$OK

  Set sc = ##class(DHA.BI.CubeCacheWarmer.Installer).Uninstall()
  If $SYSTEM.Status.IsError(sc) Quit sc
  Set sc = $SYSTEM.OBJ.DeletePackage("DHA.BI.CubeCacheWarmer")
  If $SYSTEM.Status.IsError(sc) Quit sc

  For className = "DHA.BI.CubeCacheWarmer.Model.CacheWarmQuery","DHA.BI.CubeCacheWarmer.Model.CacheWarmRun","DHA.BI.CubeCacheWarmer.Model.DashboardUsage","DHA.BI.CubeCacheWarmer.Model.QueryUsage" {
    Set sc = ##class(%ExtentMgr.Util).DeleteExtentDefinitionIfExists(className)
    If $SYSTEM.Status.IsError(sc) Quit
  }
  Quit sc
}

}
