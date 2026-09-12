Include %occStatus

Class App.Installer
{

XData Setup
{
<Manifest>
  <Default Name="SourceDir" Value="/workspace/src"/>
  <Default Name="CacheWarmerModuleDir" Value="/workspace/"/>
  <Default Name="Namespace" Value="CCWDEMO"/>
  <Default Name="DatabaseDir" Value="/durable/databases/CCWDEMO"/>
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

  If '##class(%SYS.Namespace).Exists("CCWDEMO") {
    Set sc = ..Setup()
    If $SYSTEM.Status.IsError(sc) Quit sc
  } ElseIf '##class(%Library.EnsembleMgr).IsEnsembleNamespace("CCWDEMO") {
    // Upgrade volumes created by a bootstrap that used Ensemble="0".
    Set sc = ##class(%Library.EnsembleMgr).EnableNamespace("CCWDEMO", 1)
    If $SYSTEM.Status.IsError(sc) Quit sc
  }

  // The image build installs IPM into IRISSYS. A durable volume created from an
  // older image predates that, so install IPM at runtime when it is missing.
  Set sc = ..EnsureIPM()
  If $SYSTEM.Status.IsError(sc) Quit sc
  Set sc = ..EnableIPMInNamespace("CCWDEMO")
  If $SYSTEM.Status.IsError(sc) Quit sc

  Set previousNamespace = $Namespace
  Set $Namespace = "CCWDEMO"
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
    Set sc = ##class(%DeepSee.CubeManager.Utils).SetActiveRegistry("Demo.CubeRegistry", 1)
  }
  If '$SYSTEM.Status.IsError(sc) {
    Set sc = ##class(%DeepSee.CubeManager.Utils).ScheduleUpdaterTasks()
  }
  Set $Namespace = previousNamespace

  Quit sc
}

/// Install InterSystems Package Manager (IPM) from the community registry when
/// it is not already present and enable the community registry. Must run in %SYS.
ClassMethod EnsureIPM() As %Status
{
  If ##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main") Quit $$$OK
  Set sc = ..InstallIPM()
  If $SYSTEM.Status.IsError(sc) Quit sc
  // IPM 0.9+ installs into the current namespace only and has no registry
  // configured. "enable -community" restores the familiar behaviour: the
  // community registry plus %IPM mapped into the namespaces that exist now.
  Write "Enabling the IPM community registry...",!
  Do $CLASSMETHOD("%IPM.Main", "Shell", "enable -community")
  Quit $$$OK
}

/// Map %IPM classes, routines, and repositories into a namespace that was
/// created after IPM was installed. Idempotent. Must run in %SYS.
ClassMethod EnableIPMInNamespace(pNamespace As %String) As %Status
{
  Set ipmDatabase = ##class(%SYS.Namespace).GetPackageDest("%SYS", "%IPM")
  If ##class(%SYS.Namespace).GetPackageDest(pNamespace, "%IPM") = ipmDatabase Quit $$$OK
  Write "Mapping IPM into namespace ",pNamespace,"...",!
  Do $CLASSMETHOD("%IPM.Main", "Shell", "enable -map -repos -namespaces "_pNamespace)
  If ##class(%SYS.Namespace).GetPackageDest(pNamespace, "%IPM") '= ipmDatabase {
    Quit $$$ERROR($$$GeneralError, "IPM is not mapped into namespace "_pNamespace_" after 'enable -map'")
  }
  Quit $$$OK
}

ClassMethod InstallIPM() As %Status [ Private ]
{
  Write "Installing InterSystems Package Manager (IPM)...",!
  Set request = ##class(%Net.HttpRequest).%New()
  Set request.Server = "pm.community.intersystems.com"
  Set request.Https = 1
  Set request.SSLConfiguration = "ISC.FeatureTracker.SSL.Config"
  Set sc = request.Get("/packages/zpm/latest/installer")
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
  If '##class(%Dictionary.CompiledClass).%ExistsId("dc.bi.CubeCacheWarmer.CacheWarmer") {
    Quit $$$ERROR($$$GeneralError, "IPM load finished but dc.bi.CubeCacheWarmer.CacheWarmer is not compiled")
  }
  Quit $$$OK
}

}
