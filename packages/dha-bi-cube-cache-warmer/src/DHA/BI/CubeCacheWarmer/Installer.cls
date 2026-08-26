Include %occStatus

/// Package lifecycle entry points.
Class DHA.BI.CubeCacheWarmer.Installer Extends %RegisteredObject
{

ClassMethod Install() As %Status
{
  Quit ##class(DHA.BI.CubeCacheWarmer.DashboardUsage).Install()
}

ClassMethod Uninstall() As %Status
{
  Quit ##class(DHA.BI.CubeCacheWarmer.DashboardUsage).Uninstall()
}

}
