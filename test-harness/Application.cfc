/** Isolated module harness; never load a consuming application's configuration. */
component {

	this.name                      = "r2-module-" & hash( getCurrentTemplatePath() );
	this.sessionManagement         = true;
	this.setClientCookies          = true;
	variables.appRoot              = getDirectoryFromPath( getCurrentTemplatePath() );
	this.mappings[ "/harness" ]    = variables.appRoot;
	this.mappings[ "/coldbox" ]    = variables.appRoot & "coldbox";
	this.mappings[ "/testbox" ]    = variables.appRoot & "testbox";
	this.mappings[ "/tests" ]      = variables.appRoot & "tests";
	this.mappings[ "/moduleroot" ] = createObject( "java", "java.io.File" )
		.init( variables.appRoot & "../.." )
		.getCanonicalPath();
	this.mappings[ "/packageModules" ] = createObject( "java", "java.io.File" )
		.init( variables.appRoot & "../modules" )
		.getCanonicalPath();
	request.MODULE_NAME = "cbfs-r2";

	function onApplicationStart(){
		application.cbBootstrap = new coldbox.system.Bootstrap(
			"harness.config.Coldbox",
			variables.appRoot,
			"",
			"/harness"
		);
		application.cbBootstrap.loadColdbox();
		return true;
	}

	function onRequestStart( string targetPage ){
		application.cbBootstrap.onRequestStart( arguments.targetPage );
		return true;
	}

}
