/** Run the standalone TestBox contract in a disposable CommandBox workspace. */
component {

	function run(
		string engine    = "boxlang@1.17.2+56",
		string output    = "",
		string sdkSource = ""
	){
		var root = createObject( "java", "java.io.File" )
			.init( fileSystemUtil.resolvePath( "." ) )
			.getCanonicalPath();
		var results = len( output )
		 ? createObject( "java", "java.io.File" ).init( output ).getCanonicalPath()
		 : tempDirectory( "r2-module-results-" );
		require(
			left( results & "/", len( root & "/" ) ) != root & "/",
			"Evidence must be outside package source."
		);
		if ( len( output ) ) {
			require( !directoryExists( results ), "Evidence directory already exists." );
			directoryCreate( results, true );
		}
		var workspace  = tempDirectory( "r2-module-work-" );
		var slug       = deserializeJSON( fileRead( root & "/box.json" ) ).slug;
		var package    = workspace & "/" & slug;
		var before     = sourceHashes( root );
		var started    = getTickCount();
		var serverName = "r2-module-" & lCase( replace( createUUID(), "-", "", "all" ) );
		var report     = {
			passed       : false,
			engine       : engine,
			sourceSha256 : before,
			cleanup      : {}
		};
		var contract = javacast( "null", "" );
		var testPort = 0;
		var lockPath = createObject( "java", "java.nio.file.Paths" ).get(
			javacast( "string", getTempDirectory() & "r2-module-test.lock" ),
			javacast( "string[]", [] )
		);
		var channel = createObject( "java", "java.nio.channels.FileChannel" ).open(
			lockPath,
			javacast(
				"java.nio.file.OpenOption[]",
				[
					createObject( "java", "java.nio.file.StandardOpenOption" ).CREATE,
					createObject( "java", "java.nio.file.StandardOpenOption" ).WRITE
				]
			)
		);
		var lock = channel.lock();
		try {
			try {
				copySource( root, package );
				var manifest = deserializeJSON( fileRead( package & "/box.json" ) );
				fileSystemUtil.createMapping( "/build", root & "/build" );
				createObject( "component", "build.SdkSelection" ).select( manifest, workspace, sdkSource );
				fileWrite( package & "/box.json", serializeJSON( manifest, false, false ) & chr( 10 ) );
				runProcess(
					"dependencies",
					[ "box", "install", "--production" ],
					package,
					results
				);
				runProcess(
					"harness-dependencies",
					[ "box", "install" ],
					package & "/test-harness",
					results
				);
				contract         = startContract( package, results );
				var contractPort = contract.port;
				testPort         = freePort();
				var config       = {
					name        : serverName,
					openBrowser : false,
					app         : {
						cfengine            : engine,
						serverHomeDirectory : workspace & "/engine"
					},
					web : {
						host              : "127.0.0.1",
						http              : { port : testPort },
						webroot           : "test-harness",
						directoryBrowsing : false
					},
					JVM : { heapSize : 512 },
					env : { R2_CONTRACT_PORT : contractPort }
				};
				if ( left( engine, 7 ) == "boxlang" ) {
					config[ "scripts" ] = { onServerInitialInstall : "install bx-esapi@1.10.0+14" };
				}
				var configFile = package & "/server-test.json";
				fileWrite( configFile, serializeJSON( config, false, false ) );
				runProcess(
					"server-start",
					[
						"box",
						"server",
						"start",
						"serverConfigFile=" & configFile,
						"saveSettings=false"
					],
					package,
					results
				);
				var address  = "http://127.0.0.1:" & testPort & "/tests/runner.cfm";
				var response = createObject( "java", "java.net.URI" )
					.create( javacast( "string", address ) )
					.toURL()
					.openConnection();
				response.setConnectTimeout( 180000 );
				response.setReadTimeout( 180000 );
				var bytes = response.getInputStream().readAllBytes();
				fileWrite( results & "/http-response.txt", bytes );
				var result = deserializeJSON( charsetEncode( bytes, "UTF-8" ) );
				fileWrite( results & "/testbox.json", serializeJSON( result, false, false ) & chr( 10 ) );
				report[ "runtime" ] = {
					CFMLEngine        : result.CFMLEngine ?: "",
					CFMLEngineVersion : result.CFMLEngineVersion ?: ""
				};
				report[ "tests" ] = {
					totalPass    : val( result.totalPass ),
					totalFail    : val( result.totalFail ),
					totalError   : val( result.totalError ),
					totalSkipped : val( result.totalSkipped ),
					totalSpecs   : val( result.totalSpecs )
				};
				require( report.tests.totalSpecs > 0, "TestBox discovered no specs." );
				require(
					report.tests.totalFail == 0 && report.tests.totalError == 0 && report.tests.totalSkipped == 0,
					"TestBox did not pass every discovered spec."
				);
				report[ "passed" ] = true;
			} catch ( any error ) {
				report[ "error" ]      = error.message;
				report[ "errorType" ]  = error.type;
				report[ "errorStack" ] = error.stackTrace ?: "";
			} finally {
				cleanup(
					workspace,
					package,
					results,
					testPort,
					serverName,
					contract,
					report
				);
			}
			report[ "sourceUnchanged" ] = serializeJSON( before, false, false ) == serializeJSON(
				sourceHashes( root ),
				false,
				false
			);
			report[ "passed" ] = report.passed && report.sourceUnchanged &&
			structKeyExists( report.cleanup, "serverStopped" ) && report.cleanup.serverStopped &&
			structKeyExists( report.cleanup, "contractStopped" ) && report.cleanup.contractStopped &&
			structKeyExists( report.cleanup, "workspaceRemoved" ) && report.cleanup.workspaceRemoved;
			report[ "seconds" ] = ( getTickCount() - started ) / 1000;
			fileWrite( results & "/summary.json", serializeJSON( report, false, false ) & chr( 10 ) );
			if ( !report.passed ) {
				throw( message = "Standalone contract failed; see " & results & "/summary.json" );
			}
			print.greenLine( "PASS " & results & "/summary.json" );
		} finally {
			lock.release();
			channel.close();
		}
	}

	private function cleanup(
		required string workspace,
		required string package,
		required string results,
		required numeric testPort,
		required string serverName,
		required any contract,
		required struct report
	){
		try {
			copyRuntimeLogs( workspace, results );
		} catch ( any logError ) {
			report[ "runtimeLogError" ] = logError.message;
		}
		try {
			if ( testPort > 0 ) {
				runProcess(
					"server-stop",
					[ "box", "server", "stop", "name=" & serverName ],
					package,
					results,
					90,
					false
				);
				report.cleanup[ "serverStopped" ] = !portOpen( testPort );
				if ( report.cleanup.serverStopped ) {
					runProcess(
						"server-forget",
						[
							"box",
							"server",
							"forget",
							"name=" & serverName,
							"--force"
						],
						package,
						results,
						60,
						false
					);
				}
			}
		} catch ( any serverError ) {
			report[ "serverCleanupError" ] = serverError.message;
		}
		try {
			if ( !isNull( contract ) ) {
				contract.process.destroy();
				if (
					!contract.process.waitFor(
						javacast( "long", 5 ),
						createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
					)
				) {
					contract.process.destroyForcibly();
					contract.process.waitFor();
				}
				report.cleanup[ "contractStopped" ] = !contract.process.isAlive();
			}
		} catch ( any contractError ) {
			report[ "contractCleanupError" ] = contractError.message;
		}
		try {
			if ( directoryExists( workspace ) ) {
				directoryDelete( workspace, true );
			}
			report.cleanup[ "workspaceRemoved" ] = !directoryExists( workspace );
		} catch ( any workspaceError ) {
			report[ "workspaceCleanupError" ] = workspaceError.message;
		}
	}

	private string function tempDirectory( required string prefix ){
		var path = createObject( "java", "java.nio.file.Files" ).createTempDirectory(
			javacast( "string", prefix ),
			javacast( "java.nio.file.attribute.FileAttribute[]", [] )
		);
		return createObject( "java", "java.lang.String" ).valueOf( javacast( "java.lang.Object", path ) );
	}

	private function copySource( required string root, required string destination ){
		directoryCreate( destination, true );
		var files = sourcePaths( root );
		var api   = createObject( "java", "java.nio.file.Files" );
		for ( var relative in files ) {
			var target = destination & "/" & relative;
			if ( !directoryExists( getDirectoryFromPath( target ) ) ) {
				directoryCreate( getDirectoryFromPath( target ), true );
			}
			fileWrite( target, api.readAllBytes( files[ relative ] ) );
		}
	}

	private struct function sourceHashes( required string root ){
		var hashes = structNew( "ordered" );
		var files  = sourcePaths( root );
		var names  = structKeyArray( files );
		names.sort( "text" );
		for ( var name in names ) {
			hashes[ name ] = lCase( hash( fileReadBinary( root & "/" & name ), "SHA-256" ) );
		}
		return hashes;
	}

	private struct function sourcePaths( required string root ){
		var paths    = {};
		var api      = createObject( "java", "java.nio.file.Files" );
		var javaRoot = createObject( "java", "java.nio.file.Paths" ).get(
			javacast( "string", root ),
			javacast( "string[]", [] )
		);
		var stream = api.walk( javaRoot, javacast( "java.nio.file.FileVisitOption[]", [] ) );
		try {
			var iterator = stream.iterator();
			while ( iterator.hasNext() ) {
				var path     = iterator.next();
				var pathText = createObject( "java", "java.lang.String" ).valueOf(
					javacast( "java.lang.Object", path )
				);
				var relative = len( pathText ) > len( root ) ? replace(
					mid( pathText, len( root ) + 2, len( pathText ) ),
					chr( 92 ),
					"/",
					"all"
				) : "";
				if ( !len( relative ) || excluded( relative ) ) {
					continue;
				}
				require( !api.isSymbolicLink( path ), "Source contains a symlink: " & relative );
				if ( api.isRegularFile( path, javacast( "java.nio.file.LinkOption[]", [] ) ) ) {
					paths[ relative ] = path;
				}
			}
		} finally {
			stream.close();
		}
		return paths;
	}

	private boolean function excluded( required string relative ){
		for ( var part in listToArray( relative, "/" ) ) {
			if (
				listFindNoCase( ".git,.engine,.artifacts,.tmp,modules,coldbox,testbox,__pycache__,results", part ) || (
					left( part, 4 ) == ".env" && part != ".env.example"
				)
			) {
				return true;
			}
		}
		return false;
	}

	private struct function startContract( required string package, required string results ){
		var args = createObject( "java", "java.util.ArrayList" ).init();
		args.add( javacast( "string", "java" ) );
		args.add( javacast( "string", package & "/test-harness/tests/resources/R2ContractServer.java" ) );
		var builder = createObject( "java", "java.lang.ProcessBuilder" ).init( args );
		builder.directory( createObject( "java", "java.io.File" ).init( package ) );
		builder.redirectError( createObject( "java", "java.io.File" ).init( results & "/contract.log" ) );
		var portFile = results & "/contract-port.txt";
		builder.redirectOutput( createObject( "java", "java.io.File" ).init( portFile ) );
		var child = builder.start();
		try {
			var deadline = getTickCount() + 30000;
			while ( !len( trim( fileRead( portFile ) ) ) && child.isAlive() && getTickCount() < deadline ) {
				sleep( 25 );
			}
			require( len( trim( fileRead( portFile ) ) ), "Contract server did not start." );
			var port = val( trim( fileRead( portFile ) ) );
			require( port > 0, "Contract server returned no port." );
			return { process : child, port : port };
		} catch ( any error ) {
			child.destroyForcibly();
			child.waitFor();
			rethrow;
		}
	}

	private numeric function freePort(){
		var listener = createObject( "java", "java.net.ServerSocket" ).init(
			javacast( "int", 0 ),
			javacast( "int", 0 ),
			createObject( "java", "java.net.InetAddress" ).getByName( "127.0.0.1" )
		);
		var port = listener.getLocalPort();
		listener.close();
		return port;
	}

	private boolean function portOpen( required numeric port ){
		var socket = createObject( "java", "java.net.Socket" ).init();
		try {
			socket.connect(
				createObject( "java", "java.net.InetSocketAddress" ).init(
					javacast( "string", "127.0.0.1" ),
					javacast( "int", port )
				),
				javacast( "int", 1000 )
			);
			return true;
		} catch ( any error ) {
			return false;
		} finally {
			socket.close();
		}
	}

	private function copyRuntimeLogs( required string workspace, required string results ){
		if ( !directoryExists( workspace & "/engine" ) ) {
			return;
		}
		var files = sourcePaths( workspace & "/engine" );
		for ( var relative in files ) {
			if ( right( relative, 4 ) == ".log" ) {
				var target = results & "/runtime-logs/" & relative;
				if ( !directoryExists( getDirectoryFromPath( target ) ) ) {
					directoryCreate( getDirectoryFromPath( target ), true );
				}
				fileWrite( target, fileReadBinary( workspace & "/engine/" & relative ) );
			}
		}
	}

	private numeric function runProcess(
		required string label,
		required array argv,
		required string workingDirectory,
		required string results,
		numeric seconds  = 600,
		boolean required = true
	){
		print.line( "RUN " & label );
		var args = createObject( "java", "java.util.ArrayList" ).init();
		for ( var item in argv ) {
			args.add( javacast( "string", item ) );
		}
		var builder = createObject( "java", "java.lang.ProcessBuilder" ).init( args );
		builder.directory( createObject( "java", "java.io.File" ).init( workingDirectory ) );
		builder.environment().put( "BOX_CONFIG_modulesExclude", "[""commandbox-hostupdater""]" );
		builder.redirectErrorStream( true );
		builder.redirectOutput( createObject( "java", "java.io.File" ).init( results & "/" & label & ".log" ) );
		var child = builder.start();
		child.getOutputStream().close();
		var completed = child.waitFor(
			javacast( "long", seconds ),
			createObject( "java", "java.util.concurrent.TimeUnit" ).SECONDS
		);
		if ( !completed ) {
			child.destroyForcibly();
			child.waitFor();
			throw( message = label & " timed out; see its log." );
		}
		if ( required && child.exitValue() != 0 ) {
			throw( message = label & " failed; see its log." );
		}
		return child.exitValue();
	}

	private function require( required boolean condition, required string message ){
		if ( !condition ) {
			throw( message = message );
		}
	}

}
