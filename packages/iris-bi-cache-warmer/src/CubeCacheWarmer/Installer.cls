Include %occStatus

/// Package lifecycle entry points.
Class CubeCacheWarmer.Installer Extends %RegisteredObject
{

ClassMethod Install() As %Status
{
  Quit ##class(CubeCacheWarmer.DashboardUsage).Install()
}

ClassMethod Uninstall() As %Status
{
  Quit ##class(CubeCacheWarmer.DashboardUsage).Uninstall()
}

}
