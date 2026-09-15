/** Refuse installed dependencies and generated evidence in this module's Git index. */
component {

	function run(){
		var root = createObject( "java", "java.io.File" )
			.init( fileSystemUtil.resolvePath( "." ) )
			.getCanonicalFile();
		var process = createObject( "java", "java.lang.ProcessBuilder" )
			.init(
				javacast(
					"string[]",
					[
						"git",
						"ls-files",
						"--",
						"modules",
						"test-harness/modules",
						"test-harness/coldbox",
						"test-harness/testbox",
						".engine",
						".artifacts"
					]
				)
			)
			.directory( root )
			.redirectErrorStream( true )
			.start();
		var reader = createObject( "java", "java.io.BufferedReader" ).init(
			createObject( "java", "java.io.InputStreamReader" ).init( process.getInputStream() )
		);
		var unexpected = [];
		try {
			while ( true ) {
				var path = reader.readLine();
				if ( isNull( path ) ) {
					break;
				}
				unexpected.append( path );
			}
		} finally {
			reader.close();
		}
		if ( process.waitFor() != 0 ) {
			throw( message = "Cannot inspect tracked dependency paths." );
		}
		if ( unexpected.len() ) {
			throw( message = "Installed dependency source is tracked: " & arrayToList( unexpected, ", " ) );
		}
		print.greenLine( "PASS no installed dependency source tracked" );
	}

}
