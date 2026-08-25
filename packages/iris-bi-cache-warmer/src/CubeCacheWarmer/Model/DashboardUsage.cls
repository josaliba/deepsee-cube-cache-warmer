/// Aggregate dashboard-open statistics used to prioritize cache warming.
/// No user identifiers, URL parameters, filter values, or query text are stored.
Class CubeCacheWarmer.Model.DashboardUsage Extends (%Persistent, %JSON.Adaptor)
{

Property DashboardName As %String(MAXLEN = 512) [ Required ];

Property OpenCount As %Integer [ InitialExpression = 0, Required ];

Property FirstOpenedAt As %TimeStamp [ Required ];

Property LastOpenedAt As %TimeStamp [ Required ];

Index DashboardNameKey On DashboardName [ IdKey ];

Index PopularityIndex On (OpenCount, LastOpenedAt);

Storage Default
{
<Data name="DashboardUsageDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>OpenCount</Value>
</Value>
<Value name="3">
<Value>FirstOpenedAt</Value>
</Value>
<Value name="4">
<Value>LastOpenedAt</Value>
</Value>
</Data>
<DataLocation>^CubeCacheWarmer.DashboardUsageD</DataLocation>
<DefaultData>DashboardUsageDefaultData</DefaultData>
<IdLocation>^CubeCacheWarmer.DashboardUsageD</IdLocation>
<IndexLocation>^CubeCacheWarmer.DashboardUsageI</IndexLocation>
<StreamLocation>^CubeCacheWarmer.DashboardUsageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
