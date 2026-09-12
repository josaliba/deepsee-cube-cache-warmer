Include %occStatus

/// Package lifecycle entry points.
Class dc.bi.CubeCacheWarmer.Installer Extends %RegisteredObject
{

ClassMethod Install() As %Status
{
  Set tSC = ##class(dc.bi.CubeCacheWarmer.DashboardUsage).Install()
  If $$$ISERR(tSC) Quit tSC
  Quit ##class(dc.bi.CubeCacheWarmer.QueryUsage).Install()
}

ClassMethod Uninstall() As %Status
{
  Set tSC = ##class(dc.bi.CubeCacheWarmer.QueryUsage).Uninstall()
  If $$$ISERR(tSC) Quit tSC
  Quit ##class(dc.bi.CubeCacheWarmer.DashboardUsage).Uninstall()
}

}
