Class DiseaseRegistry.Cube.Patient Extends %DeepSee.CubeDefinition [ DependsOn = DiseaseRegistry.Model.Patient ]
{

XData Cube [ XMLNamespace = "http://www.intersystems.com/deepsee" ]
{
<cube name="DiseaseRegistryPatients"
      caption="Disease Registry Patients"
      owner="_SYSTEM"
      sourceClass="DiseaseRegistry.Model.Patient">

  <dimension name="Registry Status" hasAll="true" allCaption="All Registry Statuses">
    <hierarchy name="H1">
      <level name="Registry Status" sourceProperty="RegistryStatus" />
    </hierarchy>
  </dimension>

  <dimension name="Gender" hasAll="true" allCaption="All Genders">
    <hierarchy name="H1">
      <level name="Gender" sourceProperty="Gender" />
    </hierarchy>
  </dimension>

  <dimension name="Emirate" hasAll="true" allCaption="All Emirates">
    <hierarchy name="H1">
      <level name="Emirate" sourceProperty="Emirate" />
    </hierarchy>
  </dimension>

  <dimension name="Registration" hasAll="true" allCaption="All Registration Years">
    <hierarchy name="H1">
      <level name="Registration Year" sourceProperty="RegistrationYear" />
    </hierarchy>
  </dimension>

</cube>
}

}
