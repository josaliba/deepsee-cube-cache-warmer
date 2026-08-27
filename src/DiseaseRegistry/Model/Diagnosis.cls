Class DiseaseRegistry.Model.Diagnosis Extends (%Persistent, %JSON.Adaptor)
{

/// Track every source-row change for incremental synchronization of the
/// DiseaseRegistryDiagnoses cube.
Parameter DSTIME = "AUTO";

Parameter DSINTERVAL = 5;

Property Patient As DiseaseRegistry.Model.Patient [ Required ];

Property DiseaseCode As %String(MAXLEN = 20) [ Required ];

Property DiseaseName As %String(MAXLEN = 160) [ Required ];

Property DiseaseGroup As %String(MAXLEN = 80) [ Required ];

Property DiagnosisDate As %Date [ Required ];

Property DiagnosisYear As %Integer [ Required ];

Property Facility As %String(MAXLEN = 120) [ Required ];

Property DiagnosisStatus As %String(VALUELIST = ",Suspected,Confirmed,Resolved") [ InitialExpression = "Confirmed" ];

Property Severity As %String(VALUELIST = ",Mild,Moderate,Severe") [ InitialExpression = "Mild" ];

Property Notifiable As %Boolean [ InitialExpression = 0 ];

Index PatientIndex On Patient;

Index DiseaseCodeIndex On DiseaseCode;

Index DiagnosisDateIndex On DiagnosisDate;

}
