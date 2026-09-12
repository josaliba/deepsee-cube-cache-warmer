Include %occStatus

Class App.Installer
{

XData Setup
{
<Manifest>
  <Default Name="SourceDir" Value="/workspace/src"/>
  <Default Name="CacheWarmerModuleDir" Value="/workspace/"/>
  <Default Name="Namespace" Value="DISEASEREGISTRY"/>
  <Default Name="DatabaseDir" Value="/durable/databases/DISEASEREGISTRY"/>
  <Namespace Name="${Namespace}" Code="${Namespace}" Data="${Namespace}" Create="yes" Ensemble="1">
    <Configuration>
      <Database Name="${Namespace}" Dir="${DatabaseDir}" Create="yes" Resource="%DB_${Namespace}"/>
    </Configuration>
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

  // The image build installs IPM into IRISSYS. A durable volume created from an
  // older image predates that, so install IPM at runtime when it is missing.
  Set sc = ..EnsureIPM()
  If $SYSTEM.Status.IsError(sc) Quit sc

  Set previousNamespace = $Namespace
  Set $Namespace = "DISEASEREGISTRY"
  Set sc = ..MigrateCacheWarmerPackageCase()
  If $SYSTEM.Status.IsError(sc) {
    Set $Namespace = previousNamespace
    Quit sc
  }
  // Load the cache warmer through its module.xml with IPM, exactly as an end
  // user would, so the demo exercises the published module definition. The
  // module's Activate hook installs both audit commands.
  Set sc = ..LoadCacheWarmerModule("/workspace/")
  If '$SYSTEM.Status.IsError(sc) {
    // Restrict recursive imports to ObjectScript classes. This prevents host
    // metadata such as macOS .DS_Store files from making bootstrap fail.
    Set sc = $SYSTEM.OBJ.Import("/workspace/src", "ck/recurse=1/extensions=cls")
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(%DeepSee.CubeManager.Utils).SetActiveRegistry("DiseaseRegistry.CubeRegistry", 1)
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(%DeepSee.CubeManager.Utils).ScheduleUpdaterTasks()
  }
  Set $Namespace = previousNamespace

  Quit sc
}

/// Install InterSystems Package Manager (IPM) from the community registry when
/// it is not already present. Must run in %SYS.
ClassMethod EnsureIPM() As %Status
{
  If ##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main") Quit $$$OK

  Write "Installing InterSystems Package Manager (IPM)...",!
  Set request = ##class(%Net.HttpRequest).%New()
  Set request.Server = "pm.community.intersystems.com"
  Set request.Https = 1
  Set request.SSLConfiguration = "ISC.FeatureTracker.SSL.Config"
  Set sc = request.Get("/packages/ipm/latest/installer")
  If $SYSTEM.Status.IsError(sc) Quit sc
  If request.HttpResponse.StatusCode '= 200 {
    Quit $$$ERROR($$$GeneralError, "IPM installer download failed with HTTP status "_request.HttpResponse.StatusCode)
  }
  // Compiling the installer class runs its projection, which installs IPM.
  Set sc = $SYSTEM.OBJ.LoadStream(request.HttpResponse.Data, "ck")
  If $SYSTEM.Status.IsError(sc) Quit sc
  If '##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main") {
    Quit $$$ERROR($$$GeneralError, "IPM installer completed but %IPM.Main is not available")
  }
  Quit $$$OK
}

/// Load (or reload) the cache-warmer module from its module.xml directory into
/// the current namespace with IPM. IPM classes are resolved at runtime so this
/// class still compiles on an instance without IPM.
ClassMethod LoadCacheWarmerModule(pModuleDirectory As %String) As %Status
{
  If '##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Utils.Module") {
    Quit $$$ERROR($$$GeneralError, "IPM is not installed; cannot load module from "_pModuleDirectory)
  }
  Set params("Verbose") = 1
  Set sc = $CLASSMETHOD("%IPM.Utils.Module", "LoadNewModule", pModuleDirectory, .params)
  If $SYSTEM.Status.IsError(sc) Quit sc
  If '##class(%Dictionary.CompiledClass).%ExistsId("dha.bi.CubeCacheWarmer.CacheWarmer") {
    Quit $$$ERROR($$$GeneralError, "IPM load finished but dha.bi.CubeCacheWarmer.CacheWarmer is not compiled")
  }
  Quit $$$OK
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
