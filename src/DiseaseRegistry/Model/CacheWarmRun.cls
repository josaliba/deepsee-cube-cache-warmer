/// Persistent audit record for one cache-warmer invocation.
Class DiseaseRegistry.Model.CacheWarmRun Extends (%Persistent, %JSON.Adaptor)
{

Property CubeName As %String(MAXLEN = 128);

/// QueuedCube, DirectCube, DirectPivot, or DirectMDX.
Property Mode As %String(MAXLEN = 32) [ Required ];

Property Outcome As %String(VALUELIST = ",Running,Success,PartialFailure,Failure,Skipped") [ InitialExpression = "Running", Required ];

Property StartedAt As %TimeStamp [ Required ];

Property FinishedAt As %TimeStamp;

/// Worker process identifier. Stored as a string because $JOB can include a node name.
Property ProcessId As %String(MAXLEN = 128);

Property TotalQueries As %Integer [ InitialExpression = 0 ];

Property SucceededQueries As %Integer [ InitialExpression = 0 ];

Property FailedQueries As %Integer [ InitialExpression = 0 ];

Property EnumerationErrors As %Integer [ InitialExpression = 0 ];

Property ElapsedSeconds As %Double [ InitialExpression = 0 ];

Property StatusText As %String(MAXLEN = 4096);

Relationship Queries As DiseaseRegistry.Model.CacheWarmQuery [ Cardinality = children, Inverse = Run ];

Index CubeStartedIndex On (CubeName, StartedAt);

Index StartedAtIndex On StartedAt;

Storage Default
{
<Data name="CacheWarmRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>CubeName</Value>
</Value>
<Value name="3">
<Value>Mode</Value>
</Value>
<Value name="4">
<Value>Outcome</Value>
</Value>
<Value name="5">
<Value>StartedAt</Value>
</Value>
<Value name="6">
<Value>FinishedAt</Value>
</Value>
<Value name="7">
<Value>ProcessId</Value>
</Value>
<Value name="8">
<Value>TotalQueries</Value>
</Value>
<Value name="9">
<Value>SucceededQueries</Value>
</Value>
<Value name="10">
<Value>FailedQueries</Value>
</Value>
<Value name="11">
<Value>EnumerationErrors</Value>
</Value>
<Value name="12">
<Value>ElapsedSeconds</Value>
</Value>
<Value name="13">
<Value>StatusText</Value>
</Value>
</Data>
<DataLocation>^DiseaseRegist971A.CacheWarmRunD</DataLocation>
<DefaultData>CacheWarmRunDefaultData</DefaultData>
<IdLocation>^DiseaseRegist971A.CacheWarmRunD</IdLocation>
<IndexLocation>^DiseaseRegist971A.CacheWarmRunI</IndexLocation>
<StreamLocation>^DiseaseRegist971A.CacheWarmRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
