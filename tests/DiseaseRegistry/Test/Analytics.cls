Class DiseaseRegistry.Test.Analytics Extends %UnitTest.TestCase
{

Method TestInteroperabilityEnabled()
{
  Do $$$AssertTrue(##class(%Library.EnsembleMgr).IsEnsembleNamespace($Namespace))
}

Method TestSynchronizationIsEnabled()
{
  Do $$$AssertEquals($Parameter("DiseaseRegistry.Model.Patient","DSTIME"), "AUTO")
  Do $$$AssertEquals($Parameter("DiseaseRegistry.Model.Diagnosis","DSTIME"), "AUTO")
}

Method TestCubeRegistration()
{
  Set patientClass = ##class(%DeepSee.Utils).%GetCubeClass("DiseaseRegistryPatients",.patientSC)
  Do $$$AssertStatusOK(patientSC)
  Do $$$AssertEquals(patientClass, "DiseaseRegistry.Cube.Patient")

  Set diagnosisClass = ##class(%DeepSee.Utils).%GetCubeClass("DiseaseRegistryDiagnoses",.diagnosisSC)
  Do $$$AssertStatusOK(diagnosisSC)
  Do $$$AssertEquals(diagnosisClass, "DiseaseRegistry.Cube.Diagnosis")
}

Method TestCubeManagerRegistry()
{
  Set registry = ##class(%DeepSee.CubeManager.Utils).GetActiveRegistry()
  Do $$$AssertEquals(registry, "DiseaseRegistry.CubeRegistry")

  Set map = ##class(%DeepSee.CubeManager.Utils).BuildRegistryMap(.sc,registry,1,.lookup)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(map.Groups.Count(),2)

  For groupIndex=1:1:map.Groups.Count() {
    Set group = map.Groups.GetAt(groupIndex)
    Do $$$AssertTrue(group.IsRegistered)
    Do $$$AssertEquals(group.Disabled,0)
    Do $$$AssertEquals(group.UpdatePlan,"Every")
    Do $$$AssertEquals(group.BuildFrequency,5)
    Do $$$AssertEquals(group.BuildTimeUnit,"Minute")

    Set cube = group.Cubes.GetAt(1)
    Do $$$AssertTrue(cube.DSTimeEnabled)
    Do $$$AssertEquals(cube.Disabled,0)
    Do $$$AssertNotEquals(cube.PostBuildCode,"")
    Do $$$AssertEquals(cube.PostSynchCode,cube.PostBuildCode)
  }
}

Method TestCacheWarmerRejectsMissingCubeName()
{
  Set sc = ##class(DiseaseRegistry.Util.CacheWarmer).QueueCube("")
  Do $$$AssertStatusNotOK(sc)
}

Method TestDashboardDefaultFilterComposition()
{
  Kill filters
  Set filters("[Registry Status].[H1].[Registry Status]") = "&[Active]"
  Set filters("[Emirate].[H1].[Emirate]") = "{&[Dubai],&[Ajman]}"
  Set baseMDX = "SELECT {[Measures].[%Count]} ON 0 FROM [DiseaseRegistryPatients]"

  Set sc = ##class(DiseaseRegistry.Util.CacheWarmer).ApplyDefaultFilters(baseMDX,.filters,.filteredMDX,.filterCount)
  Do $$$AssertStatusOK(sc)
  Do $$$AssertEquals(filterCount,2)
  Do $$$AssertTrue(filteredMDX[" %FILTER NONEMPTYCROSSJOIN(")
  Do $$$AssertTrue(filteredMDX["[Registry Status].[H1].[Registry Status].&[Active]")
  Do $$$AssertTrue(filteredMDX["%OR({[Emirate].[H1].[Emirate].&[Dubai],[Emirate].[H1].[Emirate].&[Ajman]})")
}

Method TestCacheWarmStatsArePersistent()
{
  Kill parameters,stats
  Set sc = ##class(DiseaseRegistry.Util.CacheWarmer).WarmMDX("",.parameters,0,.stats)
  Do $$$AssertStatusNotOK(sc)
  Set runId = $Get(stats("runId"),0)
  Do $$$AssertNotEquals(runId,0)

  Set run = ##class(DiseaseRegistry.Model.CacheWarmRun).%OpenId(runId,,.openSC)
  Do $$$AssertStatusOK(openSC)
  Do $$$AssertTrue($IsObject(run))
  Do $$$AssertEquals(run.Mode,"DirectMDX")
  Do $$$AssertEquals(run.Outcome,"Failure")
  Do $$$AssertEquals(run.TotalQueries,1)
  Do $$$AssertEquals(run.FailedQueries,1)
  Do $$$AssertEquals(run.Queries.Count(),1)
  Set query = run.Queries.GetAt(1)
  Do $$$AssertEquals(query.SourceType,"AdHocMDX")
  Do $$$AssertEquals(query.DefaultFilterCount,0)

  Set deleteSC = ##class(DiseaseRegistry.Model.CacheWarmRun).%DeleteId(runId)
  Do $$$AssertStatusOK(deleteSC)
}

}
