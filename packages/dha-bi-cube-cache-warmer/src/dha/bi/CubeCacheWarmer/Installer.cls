Include %occStatus

/// Package lifecycle entry points.
Class dha.bi.CubeCacheWarmer.Installer Extends %RegisteredObject
{

ClassMethod Install() As %Status
{
  Set tSC = ##class(dha.bi.CubeCacheWarmer.DashboardUsage).Install()
  If $$$ISERR(tSC) Quit tSC
  Quit ##class(dha.bi.CubeCacheWarmer.QueryUsage).Install()
}

ClassMethod Uninstall() As %Status
{
  Set tSC = ##class(dha.bi.CubeCacheWarmer.QueryUsage).Uninstall()
  If $$$ISERR(tSC) Quit tSC
  Quit ##class(dha.bi.CubeCacheWarmer.DashboardUsage).Uninstall()
}

}
