Include %occStatus

/// Opt-in demo and operational helpers for Disease Registry BI cubes.
Class DiseaseRegistry.Util.Analytics Extends %RegisteredObject
{

/// Reset only demo model extents, generate deterministic data, build the cubes,
/// create saved pivots, and optionally warm their queries.
ClassMethod SetupDemo(pPatientCount As %Integer = 50, pDiagnosisCount As %Integer = 500, pReset As %Boolean = 1, pWarm As %Boolean = 1) As %Status
{
  If pPatientCount < 1 Quit $$$ERROR($$$GeneralError,"pPatientCount must be positive")
  If pDiagnosisCount < 1 Quit $$$ERROR($$$GeneralError,"pDiagnosisCount must be positive")

  If pReset {
    Set tSC = ..ResetDemo()
    If $$$ISERR(tSC) Quit tSC
  }

  &sql(SELECT COUNT(*) INTO :tPatients FROM DiseaseRegistry_Model.Patient)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to count patients. SQLCODE="_SQLCODE)
  If tPatients = 0 {
    Set tSC = ..SeedPatients(pPatientCount)
    If $$$ISERR(tSC) Quit tSC
  }

  &sql(SELECT COUNT(*) INTO :tDiagnoses FROM DiseaseRegistry_Model.Diagnosis)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to count diagnoses. SQLCODE="_SQLCODE)
  If tDiagnoses = 0 {
    Set tSC = ..SeedDiagnoses(pDiagnosisCount)
    If $$$ISERR(tSC) Quit tSC
  }

  Set tSC = ..BuildAll()
  If $$$ISERR(tSC) Quit tSC
  Set tSC = ..CreateDemoPivots()
  If $$$ISERR(tSC) Quit tSC
  If pWarm {
    Set tSC = ..WarmAll()
    If $$$ISERR(tSC) Quit tSC
  }
  Do ..ShowCounts()
  Quit $$$OK
}

/// Delete only DiseaseRegistry.Model.Diagnosis and Patient data.
ClassMethod ResetDemo() As %Status
{
  Set tSC = $$$OK
  Try {
    Do ##class(DiseaseRegistry.Model.Diagnosis).%KillExtent()
    Do ##class(DiseaseRegistry.Model.Patient).%KillExtent()
  } Catch ex {
    Set tSC = ex.AsStatus()
  }
  Quit tSC
}

ClassMethod SeedPatients(pCount As %Integer = 50) As %Status
{
  If pCount < 1 Quit $$$ERROR($$$GeneralError,"pCount must be positive")
  Set tSC = $$$OK
  Set tEmirates = "Dubai,Abu Dhabi,Sharjah,Ajman,Ras Al Khaimah,Fujairah,Umm Al Quwain"
  Set tStatuses = "Active,Active,Active,Inactive,Resolved"
  Set tGenders = "Female,Male,Unknown"
  Set tStartDate = $ZDATEH("1945-01-01",3)

  For i = 1:1:pCount {
    Set tPatient = ##class(DiseaseRegistry.Model.Patient).%New()
    Set tPatient.MRN = "DR"_$TR($J(i,6)," ","0")
    Set tPatient.FullName = "Demo Patient "_i
    Set tPatient.DateOfBirth = tStartDate+((i*397)#25000)
    Set tPatient.RegistryStatus = $Piece(tStatuses,",",1+((i-1)#5))
    Set tPatient.Gender = $Piece(tGenders,",",1+((i-1)#3))
    Set tPatient.Emirate = $Piece(tEmirates,",",1+((i-1)#7))
    Set tPatient.RegistrationYear = 2020+((i-1)#7)
    Set tSC = tPatient.%Save()
    If $$$ISERR(tSC) Quit
  }
  Quit tSC
}

ClassMethod SeedDiagnoses(pCount As %Integer = 500) As %Status
{
  If pCount < 1 Quit $$$ERROR($$$GeneralError,"pCount must be positive")
  Set tSC = ..CollectPatientIDs(.tPatientIDs,.tPatientCount)
  If $$$ISERR(tSC) Quit tSC
  If tPatientCount < 1 Quit $$$ERROR($$$GeneralError,"Seed patients before diagnoses")

  For i = 1:1:pCount {
    Set tSC = ..CreateDiagnosis(i,.tPatientIDs,tPatientCount)
    If $$$ISERR(tSC) Quit
  }
  Quit tSC
}

ClassMethod CollectPatientIDs(Output pPatientIDs, Output pCount As %Integer) As %Status [ Private ]
{
  Kill pPatientIDs
  Set pCount = 0
  &sql(DECLARE DiseaseRegistryPatientIDs CURSOR FOR SELECT %ID FROM DiseaseRegistry_Model.Patient ORDER BY %ID)
  &sql(OPEN DiseaseRegistryPatientIDs)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to enumerate patients. SQLCODE="_SQLCODE)
  For {
    &sql(FETCH DiseaseRegistryPatientIDs INTO :tPatientID)
    Quit:SQLCODE'=0
    Set pPatientIDs($Increment(pCount)) = tPatientID
  }
  Set tFetchCode = SQLCODE
  &sql(CLOSE DiseaseRegistryPatientIDs)
  If tFetchCode < 0 Quit $$$ERROR($$$GeneralError,"Unable to fetch patients. SQLCODE="_tFetchCode)
  Quit $$$OK
}

ClassMethod CreateDiagnosis(pSequence As %Integer, ByRef pPatientIDs, pPatientCount As %Integer) As %Status [ Private ]
{
  Set tCodes = "A15.0,B16.9,U07.1,E11.9,I10,J45.9,C50.9"
  Set tNames = "Tuberculosis,Hepatitis B,COVID-19,Type 2 Diabetes,Hypertension,Asthma,Breast Cancer"
  Set tGroups = "Communicable,Communicable,Communicable,Chronic,Chronic,Chronic,Oncology"
  Set tFacilities = "Rashid Hospital,Dubai Hospital,Latifa Hospital,Hatta Hospital"
  Set tStatuses = "Confirmed,Confirmed,Suspected,Resolved"
  Set tSeverities = "Mild,Moderate,Severe"
  Set tDisease = 1+((pSequence-1)#7)
  Set tDate = $ZDATEH("2024-01-01",3)+((pSequence*11)#1000)

  Set tPatient = ##class(DiseaseRegistry.Model.Patient).%OpenId(pPatientIDs(1+((pSequence-1)#pPatientCount)),,.tSC)
  If $$$ISERR(tSC) Quit tSC
  If '$IsObject(tPatient) Quit $$$ERROR($$$GeneralError,"Unable to open diagnosis patient")

  Set tDiagnosis = ##class(DiseaseRegistry.Model.Diagnosis).%New()
  Set tDiagnosis.Patient = tPatient
  Set tDiagnosis.DiseaseCode = $Piece(tCodes,",",tDisease)
  Set tDiagnosis.DiseaseName = $Piece(tNames,",",tDisease)
  Set tDiagnosis.DiseaseGroup = $Piece(tGroups,",",tDisease)
  Set tDiagnosis.DiagnosisDate = tDate
  Set tDiagnosis.DiagnosisYear = +$Piece($ZDATE(tDate,3),"-",1)
  Set tDiagnosis.Facility = $Piece(tFacilities,",",1+((pSequence-1)#4))
  Set tDiagnosis.DiagnosisStatus = $Piece(tStatuses,",",1+((pSequence-1)#4))
  Set tDiagnosis.Severity = $Piece(tSeverities,",",1+((pSequence-1)#3))
  Set tDiagnosis.Notifiable = (tDisease<4)
  Quit tDiagnosis.%Save()
}

/// Exercise AUTO DSTIME with patient and diagnosis updates, diagnosis deletes,
/// and diagnosis inserts. Run SynchronizeAll() afterward.
ClassMethod MakeChanges(pAdds As %Integer = 10, pUpdates As %Integer = 6, pDeletes As %Integer = 2, pPatientUpdates As %Integer = 3) As %Status
{
  If (pAdds<0)!(pUpdates<0)!(pDeletes<0)!(pPatientUpdates<0) Quit $$$ERROR($$$GeneralError,"Change counts cannot be negative")
  Set tSC = ..UpdatePatients(pPatientUpdates)
  If $$$ISERR(tSC) Quit tSC
  Set tSC = ..UpdateDiagnoses(pUpdates)
  If $$$ISERR(tSC) Quit tSC
  Set tSC = ..DeleteDiagnoses(pDeletes)
  If $$$ISERR(tSC) Quit tSC

  Set tSC = ..CollectPatientIDs(.tPatientIDs,.tPatientCount)
  If $$$ISERR(tSC) Quit tSC
  If (pAdds>0),(tPatientCount<1) Quit $$$ERROR($$$GeneralError,"No patients are available")
  &sql(SELECT COALESCE(MAX(%ID),0) INTO :tMaxID FROM DiseaseRegistry_Model.Diagnosis)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to inspect diagnoses. SQLCODE="_SQLCODE)
  For i = 1:1:pAdds {
    Set tSC = ..CreateDiagnosis(tMaxID+i,.tPatientIDs,tPatientCount)
    If $$$ISERR(tSC) Quit
  }
  If $$$ISERR($Get(tSC,$$$OK)) Quit tSC

  Write !,"Changed patients=",pPatientUpdates,", added diagnoses=",pAdds,", updated diagnoses=",pUpdates,", deleted diagnoses=",pDeletes,!
  Quit $$$OK
}

ClassMethod UpdatePatients(pCount As %Integer = 3) As %Status
{
  If pCount < 1 Quit $$$OK
  Set tSC = $$$OK, tDone = 0
  &sql(DECLARE DiseaseRegistryUpdatePatients CURSOR FOR SELECT %ID FROM DiseaseRegistry_Model.Patient ORDER BY %ID DESC)
  &sql(OPEN DiseaseRegistryUpdatePatients)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to update patients. SQLCODE="_SQLCODE)
  For {
    &sql(FETCH DiseaseRegistryUpdatePatients INTO :tID)
    Quit:SQLCODE'=0
    Set tPatient = ##class(DiseaseRegistry.Model.Patient).%OpenId(tID,,.tOpenSC)
    If $$$ISERR(tOpenSC) Set tSC=tOpenSC Quit
    Set tPatient.RegistryStatus = $Select(tPatient.RegistryStatus="Active":"Inactive",1:"Active")
    Set tSC = tPatient.%Save()
    Quit:$$$ISERR(tSC)
    Set tDone = tDone+1
    Quit:tDone>=pCount
  }
  &sql(CLOSE DiseaseRegistryUpdatePatients)
  Quit tSC
}

ClassMethod UpdateDiagnoses(pCount As %Integer = 6) As %Status
{
  If pCount < 1 Quit $$$OK
  Set tSC = $$$OK, tDone = 0
  &sql(DECLARE DiseaseRegistryUpdateDiagnoses CURSOR FOR SELECT %ID FROM DiseaseRegistry_Model.Diagnosis ORDER BY %ID DESC)
  &sql(OPEN DiseaseRegistryUpdateDiagnoses)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to update diagnoses. SQLCODE="_SQLCODE)
  For {
    &sql(FETCH DiseaseRegistryUpdateDiagnoses INTO :tID)
    Quit:SQLCODE'=0
    Set tDiagnosis = ##class(DiseaseRegistry.Model.Diagnosis).%OpenId(tID,,.tOpenSC)
    If $$$ISERR(tOpenSC) Set tSC=tOpenSC Quit
    Set tDiagnosis.Severity = $Select(tDiagnosis.Severity="Severe":"Moderate",1:"Severe")
    Set tDiagnosis.DiagnosisStatus = "Confirmed"
    Set tSC = tDiagnosis.%Save()
    Quit:$$$ISERR(tSC)
    Set tDone = tDone+1
    Quit:tDone>=pCount
  }
  &sql(CLOSE DiseaseRegistryUpdateDiagnoses)
  Quit tSC
}

ClassMethod DeleteDiagnoses(pCount As %Integer = 2) As %Status
{
  If pCount < 1 Quit $$$OK
  Set tSC = $$$OK, tDone = 0
  &sql(DECLARE DiseaseRegistryDeleteDiagnoses CURSOR FOR SELECT %ID FROM DiseaseRegistry_Model.Diagnosis ORDER BY %ID DESC)
  &sql(OPEN DiseaseRegistryDeleteDiagnoses)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to delete diagnoses. SQLCODE="_SQLCODE)
  For {
    &sql(FETCH DiseaseRegistryDeleteDiagnoses INTO :tID)
    Quit:SQLCODE'=0
    Set tSC = ##class(DiseaseRegistry.Model.Diagnosis).%DeleteId(tID)
    Quit:$$$ISERR(tSC)
    Set tDone = tDone+1
    Quit:tDone>=pCount
  }
  &sql(CLOSE DiseaseRegistryDeleteDiagnoses)
  Quit tSC
}

ClassMethod BuildAll() As %Status
{
  Write !,"Building DiseaseRegistryPatients...",!
  Set tSC = ##class(%DeepSee.Utils).%BuildCube("DiseaseRegistryPatients",0,1)
  If $$$ISERR(tSC) Quit tSC
  Write !,"Building DiseaseRegistryDiagnoses...",!
  Quit ##class(%DeepSee.Utils).%BuildCube("DiseaseRegistryDiagnoses",0,1)
}

ClassMethod SynchronizeAll(pWarm As %Boolean = 1) As %Status
{
  Write !,"Synchronizing DiseaseRegistryPatients...",!
  Set tSC = ##class(%DeepSee.Utils).%SynchronizeCube("DiseaseRegistryPatients",1,.tPatientFacts)
  If $$$ISERR(tSC) Quit tSC
  Write !,"Synchronizing DiseaseRegistryDiagnoses...",!
  Set tSC = ##class(%DeepSee.Utils).%SynchronizeCube("DiseaseRegistryDiagnoses",1,.tDiagnosisFacts)
  If $$$ISERR(tSC) Quit tSC
  Write !,"Updated facts: patients=",tPatientFacts,", diagnoses=",tDiagnosisFacts,!
  If pWarm Set tSC = ..WarmAll()
  Quit tSC
}

ClassMethod CreateDemoPivots() As %Status
{
  Set tMDX = "SELECT {[Measures].[%Count]} ON 0, NON EMPTY [Registry Status].[Registry Status].Members ON 1 FROM [DiseaseRegistryPatients]"
  Set tSC = ..SaveManualPivot("Disease Registry/Patients by Status.pivot","DiseaseRegistryPatients",tMDX)
  If $$$ISERR(tSC) Quit tSC
  Set tMDX = "SELECT {[Measures].[%Count],[Measures].[Notifiable Cases]} ON 0, NON EMPTY [Disease].[Disease Group].Members ON 1 FROM [DiseaseRegistryDiagnoses]"
  Quit ..SaveManualPivot("Disease Registry/Diagnoses by Group.pivot","DiseaseRegistryDiagnoses",tMDX)
}

ClassMethod SaveManualPivot(pFullName As %String, pCubeName As %String, pMDX As %String) As %Status [ Private ]
{
  Set tSC = $$$OK
  If ##class(%DeepSee.UserLibrary.Utils).%FolderItemExists(pFullName) {
    Set tPivot = ##class(%DeepSee.UserLibrary.Utils).%OpenFolderItem(pFullName,.tSC)
    If $$$ISERR(tSC) Quit tSC
    If 'tPivot.%IsA("%DeepSee.Dashboard.Pivot") Quit $$$ERROR($$$GeneralError,"Existing item is not a pivot: "_pFullName)
  } Else {
    Set tPivot = ##class(%DeepSee.Dashboard.Pivot).%New()
    Set tPivot.fullName = pFullName
  }
  Set tPivot.cubeName = pCubeName
  Set tPivot.caption = pFullName
  Set tPivot.manualMode = 1
  Set tPivot.userMDX = pMDX
  Set tPivot.mdx = pMDX
  Quit tPivot.%Save()
}

ClassMethod WarmAll() As %Status
{
  Set tSC = ##class(DiseaseRegistry.Util.CacheWarmer).WarmCube("DiseaseRegistryPatients",0,1,.tPatientStats)
  If $$$ISERR(tSC) Quit tSC
  Set tSC = ##class(DiseaseRegistry.Util.CacheWarmer).WarmCube("DiseaseRegistryDiagnoses",0,1,.tDiagnosisStats)
  If $$$ISERR(tSC) Quit tSC
  Write !,"Warmed ",tPatientStats("succeeded")+tDiagnosisStats("succeeded")," saved queries.",!
  Quit $$$OK
}

ClassMethod ShowCounts() As %Status
{
  &sql(SELECT COUNT(*) INTO :tPatients FROM DiseaseRegistry_Model.Patient)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to count patients. SQLCODE="_SQLCODE)
  &sql(SELECT COUNT(*) INTO :tDiagnoses FROM DiseaseRegistry_Model.Diagnosis)
  If SQLCODE < 0 Quit $$$ERROR($$$GeneralError,"Unable to count diagnoses. SQLCODE="_SQLCODE)
  Write !,"Source rows: ",tPatients," patients; ",tDiagnoses," diagnoses.",!
  Quit $$$OK
}

}
