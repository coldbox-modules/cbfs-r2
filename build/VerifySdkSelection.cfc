/** Focused contract checks for package SDK source selection. */
component {

	function run(){
		fileSystemUtil.createMapping( "/build", fileSystemUtil.resolvePath( "build" ) );
		var selector  = createObject( "component", "build.SdkSelection" );
		var temporary = createObject( "java", "java.nio.file.Files" ).createTempDirectory(
			javacast( "string", "r2-sdk-selection-" ),
			javacast( "java.nio.file.attribute.FileAttribute[]", [] )
		);
		var root = createObject( "java", "java.lang.String" ).valueOf( javacast( "java.lang.Object", temporary ) );
		try {
			var workspace = root & "/run";
			directoryCreate( workspace );
			var source = root & "/r2sdk";
			directoryCreate( source );
			fileWrite( source & "/box.json", "{""slug"":""r2sdk""}" );
			var bytes = binaryDecode( "73646b20666978747572650a", "hex" );
			fileWrite( source & "/ModuleConfig.cfc", bytes );
			var published = manifest( "0.1.0" );
			selector.select( published, workspace );
			require(
				published.dependencies.r2sdk == "0.1.0" && !directoryExists( workspace & "/r2sdk" ),
				"A neighboring checkout replaced the published SDK dependency."
			);
			expectFailure( () => selector.select( manifest( "../r2sdk/" ), workspace ), "Supply --sdk-source" );
			var explicit = manifest( "../r2sdk/" );
			selector.select( explicit, workspace, source );
			var staged = createObject( "java", "java.io.File" ).init( workspace & "/r2sdk" ).getCanonicalPath();
			require( explicit.dependencies.r2sdk == staged & "/", "Explicit SDK dependency path was not staged." );
			require(
				hash( fileReadBinary( source & "/ModuleConfig.cfc" ), "SHA-256" ) == hash(
					fileReadBinary( workspace & "/r2sdk/ModuleConfig.cfc" ),
					"SHA-256"
				),
				"SDK fixture bytes changed during staging."
			);
			var wrong = root & "/other";
			directoryCreate( wrong );
			fileWrite( wrong & "/box.json", "{""slug"":""other""}" );
			expectFailure( () => selector.select( manifest( "0.1.0" ), workspace, wrong ), "not r2sdk" );
			expectFailure( () => selector.select( { slug : "r2sdk" }, workspace, source ), "only to cbfs-r2" );
			print.greenLine( "PASS SDK selection contract" );
		} finally {
			if ( directoryExists( root ) ) {
				directoryDelete( root, true );
			}
		}
	}

	private struct function manifest( required string dependency ){
		return { slug : "cbfs-r2", dependencies : { r2sdk : dependency } };
	}

	private function expectFailure( required any action, required string expected ){
		var failed = false;
		try {
			action();
		} catch ( any error ) {
			failed = findNoCase( expected, error.message ) > 0;
		}
		require( failed, "Expected rejection: " & expected );
	}

	private function require( required boolean condition, required string message ){
		if ( !condition ) {
			throw( message = message );
		}
	}

}
