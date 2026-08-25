Class DiseaseRegistry.Model.Patient Extends (%Persistent, %JSON.Adaptor)
{

/// Track inserts, updates, and deletes for incremental BI cube synchronization.
Parameter DSTIME = "AUTO";

Parameter DSINTERVAL = 5;

/// Medical record number in the source clinical system.
Property MRN As %String(MAXLEN = 64) [ Required ];

Property FullName As %String(MAXLEN = 200) [ Required ];

Property DateOfBirth As %Date;

Property RegistryStatus As %String(VALUELIST = ",Active,Inactive,Resolved") [ InitialExpression = "Active" ];

Property Gender As %String(VALUELIST = ",Female,Male,Other,Unknown") [ InitialExpression = "Unknown" ];

Property Emirate As %String(MAXLEN = 40);

Property RegistrationYear As %Integer;

Index MRNUnique On MRN [ Unique ];

}
