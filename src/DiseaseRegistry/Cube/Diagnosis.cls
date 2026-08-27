Class DiseaseRegistry.Cube.Diagnosis Extends %DeepSee.CubeDefinition [ DependsOn = DiseaseRegistry.Model.Diagnosis ]
{

XData Cube [ XMLNamespace = "http://www.intersystems.com/deepsee" ]
{
<cube name="DiseaseRegistryDiagnoses"
      caption="Disease Registry Diagnoses"
      owner="_SYSTEM"
      sourceClass="DiseaseRegistry.Model.Diagnosis">

  <measure name="Notifiable Cases"
           sourceProperty="Notifiable"
           aggregate="COUNT" />

  <dimension name="Disease" hasAll="true" allCaption="All Diseases">
    <hierarchy name="H1">
      <level name="Disease Group" sourceProperty="DiseaseGroup" />
      <level name="Disease Name" sourceProperty="DiseaseName" />
      <level name="Disease Code" sourceProperty="DiseaseCode" />
    </hierarchy>
  </dimension>

  <dimension name="Diagnosis Period" hasAll="true" allCaption="All Diagnosis Years">
    <hierarchy name="H1">
      <level name="Diagnosis Year" sourceProperty="DiagnosisYear" />
    </hierarchy>
  </dimension>

  <dimension name="Facility" hasAll="true" allCaption="All Facilities">
    <hierarchy name="H1">
      <level name="Facility" sourceProperty="Facility" />
    </hierarchy>
  </dimension>

  <dimension name="Diagnosis Status" hasAll="true" allCaption="All Diagnosis Statuses">
    <hierarchy name="H1">
      <level name="Diagnosis Status" sourceProperty="DiagnosisStatus" />
    </hierarchy>
  </dimension>

  <dimension name="Severity" hasAll="true" allCaption="All Severities">
    <hierarchy name="H1">
      <level name="Severity" sourceProperty="Severity" />
    </hierarchy>
  </dimension>

  <dimension name="Notifiable" hasAll="true" allCaption="All Notification Types">
    <hierarchy name="H1">
      <level name="Notifiable" sourceProperty="Notifiable" />
    </hierarchy>
  </dimension>

</cube>
}

}
