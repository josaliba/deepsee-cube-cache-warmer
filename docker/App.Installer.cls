Class App.Installer
{

XData Setup
{
<Manifest>
  <Default Name="SourceDir" Value="/workspace/src"/>
  <Default Name="Namespace" Value="DISEASEREGISTRY"/>
  <Default Name="DatabaseDir" Value="/durable/databases/DISEASEREGISTRY"/>
  <Namespace Name="${Namespace}" Code="${Namespace}" Data="${Namespace}" Create="yes" Ensemble="0">
    <Configuration>
      <Database Name="${Namespace}" Dir="${DatabaseDir}" Create="yes" Resource="%DB_${Namespace}"/>
    </Configuration>
    <Import File="${SourceDir}" Flags="ck" Recurse="1"/>
  </Namespace>
</Manifest>
}

ClassMethod Setup(ByRef pVars, pLogLevel As %Integer = 3, pInstaller As %Installer.Installer, pLogger As %Installer.AbstractLogger) As %Status [ CodeMode = objectgenerator, Internal ]
{
  Quit ##class(%Installer.Manifest).%Generate(%compiledclass, %code, "Setup")
}

}

