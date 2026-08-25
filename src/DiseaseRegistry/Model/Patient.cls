Class DiseaseRegistry.Model.Patient Extends (%Persistent, %JSON.Adaptor)
{

/// Medical record number in the source clinical system.
Property MRN As %String(MAXLEN = 64) [ Required ];

Property FullName As %String(MAXLEN = 200) [ Required ];

Property DateOfBirth As %Date;

Property RegistryStatus As %String(VALUELIST = ",Active,Inactive,Resolved") [ InitialExpression = "Active" ];

Index MRNUnique On MRN [ Unique ];

}

