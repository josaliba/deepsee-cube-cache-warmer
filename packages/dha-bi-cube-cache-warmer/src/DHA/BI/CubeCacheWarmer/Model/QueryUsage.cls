/// Persistent execution frequency for a normalized IRIS BI query.
Class DHA.BI.CubeCacheWarmer.Model.QueryUsage Extends (%Persistent, %JSON.Adaptor)
{

/// IRIS BI's normalized query key. This is also the record ID.
Property QueryKey As %String(MAXLEN = 128) [ Required ];

Property CubeName As %String(MAXLEN = 128);

/// Most recently observed MDX for this query key. Required to replay the query.
Property MDX As %String(MAXLEN = 65535);

Property ExecutionCount As %Integer [ InitialExpression = 0 ];

Property FirstExecutedAt As %TimeStamp;

Property LastExecutedAt As %TimeStamp;

Index QueryKeyIndex On QueryKey [ IdKey, Unique ];

Index CubeFrequencyIndex On (CubeName, ExecutionCount);

Storage Default
{
<Data name="QueryUsageDefaultData">
<Value name="1"><Value>%%CLASSNAME</Value></Value>
<Value name="2"><Value>CubeName</Value></Value>
<Value name="3"><Value>MDX</Value></Value>
<Value name="4"><Value>ExecutionCount</Value></Value>
<Value name="5"><Value>FirstExecutedAt</Value></Value>
<Value name="6"><Value>LastExecutedAt</Value></Value>
</Data>
<DataLocation>^DHABICCW.QueryUsageD</DataLocation>
<DefaultData>QueryUsageDefaultData</DefaultData>
<IdLocation>^DHABICCW.QueryUsageD</IdLocation>
<IndexLocation>^DHABICCW.QueryUsageI</IndexLocation>
<StreamLocation>^DHABICCW.QueryUsageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
