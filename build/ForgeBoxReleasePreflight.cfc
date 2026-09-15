/** Refuse publication of a ForgeBox version that already exists, including build metadata variants. */
component {

	function run( required string slug, required string version ){
		var result = inspectSlug( slug );
		verifyResult( result.exitCode, result.output, version );
		print.greenLine( "ForgeBox version is available for initial publication." );
	}

	function selftest(){
		verifyEntry( { versions : [ { version : "0.1.0" } ] }, "0.2.0" );
		expectRefusal( () => verifyEntry( { versions : [ { version : "0.1.0+1" } ] }, "0.1.0+2" ) );
		for (
			var entry in [
				[],
				{},
				{ versions : "unknown" },
				{ versions : [ {} ] },
				{ versions : [ { version : 3 } ] }
			]
		) {
			expectRefusal( () => verifyEntry( entry, "0.1.0" ) );
		}
		expectRefusal( () => verifyResult( 0, "Service temporarily unavailable", "0.1.0" ) );
		verifyResult(
			1,
			"The entry slug sent is invalid or does not exist",
			"0.1.0"
		);
		for (
			var message in [
				"Authentication failed",
				"Timed out",
				"Service unavailable",
				""
			]
		) {
			expectRefusal( () => verifyResult( 1, message, "0.1.0" ) );
		}
		print.greenLine( "ForgeBox release preflight refusal contracts passed." );
	}

	private function verifyResult(
		required numeric exitCode,
		required string output,
		required string version
	){
		if ( exitCode != 0 ) {
			if ( find( "The entry slug sent is invalid or does not exist", output ) ) {
				return;
			}
			refuse( "Could not verify ForgeBox publication state; publication is stopped." );
		}
		try {
			verifyEntry( deserializeJSON( output ), version );
		} catch ( any error ) {
			if ( error.type == "ForgeBoxReleasePreflight.Refusal" ) {
				rethrow;
			}
			refuse( "ForgeBox returned an invalid version inventory." );
		}
	}

	private function verifyEntry( required any entry, required string version ){
		if ( !isStruct( entry ) || !structKeyExists( entry, "versions" ) || !isArray( entry.versions ) ) {
			refuse( "ForgeBox returned no version inventory; publication is stopped." );
		}
		var wanted = listFirst( version, "+" );
		for ( var item in entry.versions ) {
			if (
				!isStruct( item ) || !structKeyExists( item, "version" ) ||
				!createObject( "java", "java.lang.Class" ).forName( "java.lang.String" ).isInstance( item.version )
			) {
				refuse( "ForgeBox returned an invalid version inventory." );
			}
			if ( listFirst( item.version, "+" ) == wanted ) {
				refuse( "This version already exists on ForgeBox; inspect and recover the existing release." );
			}
		}
	}

	private function inspectSlug( required string slug ){
		var args = createObject( "java", "java.util.ArrayList" ).init();
		for (
			var item in [
				"box",
				"forgebox",
				"show",
				"slug=" & slug,
				"--json"
			]
		) {
			args.add( javacast( "string", item ) );
		}
		var tempRoot = createObject( "java", "java.lang.System" ).getenv( "TMPDIR" );
		if ( isNull( tempRoot ) || !len( tempRoot ) ) {
			tempRoot = "/tmp/";
		}
		var outputFile = tempRoot & "/communiarts-forgebox-preflight-" & lCase(
			replace( createUUID(), "-", "", "all" )
		) & ".log";
		fileWrite( outputFile, "" );
		var permissions = createObject( "java", "java.nio.file.attribute.PosixFilePermissions" ).fromString( "rw-------" );
		var javaPath    = createObject( "java", "java.nio.file.Paths" ).get(
			javacast( "string", outputFile ),
			javacast( "string[]", [] )
		);
		createObject( "java", "java.nio.file.Files" ).setPosixFilePermissions( javaPath, permissions );
		var builder = createObject( "java", "java.lang.ProcessBuilder" ).init( args );
		builder.redirectErrorStream( true );
		builder.redirectOutput( createObject( "java", "java.io.File" ).init( outputFile ) );
		try {
			var child = builder.start();
			child.getOutputStream().close();
			var completed = child.waitFor( 120, createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS );
			if ( !completed ) {
				child.destroyForcibly();
				child.waitFor();
				refuse( "Could not verify ForgeBox publication state; publication is stopped." );
			}
			return {
				exitCode : child.exitValue(),
				output   : fileRead( outputFile )
			};
		} finally {
			if ( fileExists( outputFile ) ) {
				fileDelete( outputFile );
			}
		}
	}

	private function expectRefusal( required any callback ){
		var refused = false;
		try {
			callback();
		} catch ( any error ) {
			if ( error.type != "ForgeBoxReleasePreflight.Refusal" ) {
				rethrow;
			}
			refused = true;
		}
		if ( !refused ) {
			throw( message = "Expected release preflight refusal." );
		}
	}

	private function refuse( required string message ){
		throw( type = "ForgeBoxReleasePreflight.Refusal", message = message );
	}

}
