/// Runs the cache-warmer package tests and the demo tests from any shell:
///
///   docker compose exec iris iris session IRIS -U USER "##class(Demo.Util.Tests).RunAll()"
///
/// The process exits with status 1 when a suite fails, so the command works in CI.
Class Demo.Util.Tests
{

/// pRoot is the directory that holds the repository, as seen from inside the container.
ClassMethod RunAll(pRoot As %String = "/home/irisowner/dev")
{
  Set failed = 0
  Set failed = failed + ..RunSuite(pRoot_"/packages/cube-cache-warmer/tests", "dc/bi/CubeCacheWarmer/Test")
  Set failed = failed + ..RunSuite(pRoot_"/tests", "Demo/Test")
  If failed {
    Write !,failed," test suite(s) failed.",!
    Do ##class(%SYSTEM.Process).Terminate(,1)
    Quit
  }
  Write !,"All test suites passed.",!
  Quit
}

/// Run one suite directory and return 1 when any of its tests failed.
ClassMethod RunSuite(pRoot As %String, pSuite As %String) As %Integer
{
  Set ^UnitTestRoot = pRoot
  Set sc = ##class(%UnitTest.Manager).RunTest(pSuite, "/loadud")
  If $$$ISERR(sc) {
    Do $SYSTEM.Status.DisplayError(sc)
    Quit 1
  }
  // Results of the run just completed live under the newest index of ^UnitTest.Result.
  // Each suite, test case and test method node holds a $LIST whose first item is the
  // status: 0 failed, 1 passed, 2 skipped.
  Set index = $Order(^UnitTest.Result(""), -1)
  Set suite = ""
  For {
    Set suite = $Order(^UnitTest.Result(index, suite), 1, data)
    Quit:suite=""
    If $ListValid(data), $ListGet(data, 1) = 0 Quit
  }
  Quit (suite '= "")
}

}
