Include %occStatus

/// Package lifecycle entry points.
Class DHA.BI.CubeCacheWarmer.Installer Extends %RegisteredObject
{

ClassMethod Install() As %Status
{
  Set tSC = ##class(DHA.BI.CubeCacheWarmer.DashboardUsage).Install()
  If $$$ISERR(tSC) Quit tSC
  Quit ##class(DHA.BI.CubeCacheWarmer.QueryUsage).Install()
}

ClassMethod Uninstall() As %Status
{
  Set tSC = ##class(DHA.BI.CubeCacheWarmer.QueryUsage).Uninstall()
  If $$$ISERR(tSC) Quit tSC
  Quit ##class(DHA.BI.CubeCacheWarmer.DashboardUsage).Uninstall()
}

}
