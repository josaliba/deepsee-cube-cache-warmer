Class DiseaseRegistry.Test.Smoke Extends %UnitTest.TestCase
{

Method TestHealthPing()
{
  Do $$$AssertEquals(##class(DiseaseRegistry.Util.Health).Ping(), "OK")
}

}

