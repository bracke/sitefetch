with AUnit.Test_Suites;

package Sitefetch.Tests is
   --  Return the complete AUnit suite.
   --
   --  @return Test suite containing all Sitefetch tests.
   function Suite return AUnit.Test_Suites.Access_Test_Suite;
end Sitefetch.Tests;
