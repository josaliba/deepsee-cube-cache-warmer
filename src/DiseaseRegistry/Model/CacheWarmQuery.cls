/// Persistent per-query statistics belonging to a cache-warming run.
Class DiseaseRegistry.Model.CacheWarmQuery Extends (%Persistent, %JSON.Adaptor)
{

Relationship Run As DiseaseRegistry.Model.CacheWarmRun [ Cardinality = parent, Inverse = Queries, Required ];

/// Saved pivot name, or "Ad hoc MDX" for a direct MDX invocation.
Property QueryName As %String(MAXLEN = 512);

/// BasePivot, DashboardBase, DashboardDefault, Pivot, or AdHocMDX.
Property SourceType As %String(MAXLEN = 32);

/// Dashboard and widget attribution for a DashboardDefault query.
Property DashboardName As %String(MAXLEN = 512);

Property WidgetName As %String(MAXLEN = 255);

/// Number of default filters applied. Filter values are not persisted.
Property DefaultFilterCount As %Integer [ InitialExpression = 0 ];

/// Dashboard-open count observed when this query was prioritized.
Property DashboardOpenCount As %Integer [ InitialExpression = 0 ];

/// Dashboard popularity rank used for this query; zero means unranked.
Property PriorityOrder As %Integer [ InitialExpression = 0 ];

Property CubeName As %String(MAXLEN = 128);

Property QueryKey As %String(MAXLEN = 128);

Property RowCount As %Integer;

Property ColumnCount As %Integer;

Property ElapsedSeconds As %Double [ InitialExpression = 0 ];

Property Success As %Boolean [ InitialExpression = 0 ];

Property StatusText As %String(MAXLEN = 4096);

Index RunIndex On Run;

Storage Default
{
<Data name="CacheWarmQueryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>QueryName</Value>
</Value>
<Value name="3">
<Value>CubeName</Value>
</Value>
<Value name="4">
<Value>QueryKey</Value>
</Value>
<Value name="5">
<Value>RowCount</Value>
</Value>
<Value name="6">
<Value>ColumnCount</Value>
</Value>
<Value name="7">
<Value>ElapsedSeconds</Value>
</Value>
<Value name="8">
<Value>Success</Value>
</Value>
<Value name="9">
<Value>StatusText</Value>
</Value>
<Value name="10">
<Value>SourceType</Value>
</Value>
<Value name="11">
<Value>DashboardName</Value>
</Value>
<Value name="12">
<Value>WidgetName</Value>
</Value>
<Value name="13">
<Value>DefaultFilterCount</Value>
</Value>
<Value name="14">
<Value>DashboardOpenCount</Value>
</Value>
<Value name="15">
<Value>PriorityOrder</Value>
</Value>
</Data>
<DataLocation>{%%PARENT}("Queries")</DataLocation>
<DefaultData>CacheWarmQueryDefaultData</DefaultData>
<IdLocation>^DiseaseRegist971A.CacheWarmRunC("Queries")</IdLocation>
<IndexLocation>^DiseaseRegi971A.CacheWarmQueryI</IndexLocation>
<StreamLocation>^DiseaseRegi971A.CacheWarmQueryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
