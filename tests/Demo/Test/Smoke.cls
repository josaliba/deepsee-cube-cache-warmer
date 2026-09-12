Class Demo.Test.Smoke Extends %UnitTest.TestCase
{

Method TestHealthPing()
{
  Do $$$AssertEquals(##class(Demo.Util.Health).Ping(), "OK")
}

}

