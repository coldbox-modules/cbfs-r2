<cfsetting showDebugOutput="false" requestTimeout="120">
<cfscript>
	result = new testbox.system.TestBox( directory = "tests.specs" ).run( reporter = "json" );
	cfcontent( type = "application/json", reset = true );
	writeOutput( result );
</cfscript>
