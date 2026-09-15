/** Build an allowlisted, reproducible ForgeBox module ZIP. */
component {

	function run(
		string output     = ".artifacts",
		string sdkVersion = "",
		string repository = ""
	){
		var root = createObject( "java", "java.io.File" )
			.init( fileSystemUtil.resolvePath( "." ) )
			.getCanonicalPath();
		var manifest = deserializeJSON( fileRead( root & "/box.json" ) );
		var version  = manifest.version;
		validateVersion( version, "Package" );
		if ( len( sdkVersion ) ) {
			require( manifest.slug == "cbfs-r2", "SDK version override applies only to cbfs-r2." );
			manifest.dependencies[ "r2sdk" ] = sdkVersion;
		}
		if ( structKeyExists( manifest, "dependencies" ) ) {
			for ( var name in manifest.dependencies ) {
				validateVersion( manifest.dependencies[ name ], name );
			}
		}
		if ( len( repository ) ) {
			require(
				reFind( "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", repository ) == 1,
				"Repository must be an owner/name pair."
			);
			var repositoryUrl           = "https://github.com/" & repository;
			manifest[ "homepage" ]      = repositoryUrl;
			manifest[ "documentation" ] = repositoryUrl & "/blob/main/README.md";
			manifest[ "bugs" ]          = repositoryUrl & "/issues";
			var repositoryInfo          = structNew( "ordered" );
			repositoryInfo[ "type" ]    = "git";
			repositoryInfo[ "URL" ]     = repositoryUrl;
			manifest[ "repository" ]    = repositoryInfo;
		}
		for ( var key in [ "scripts", "devDependencies", "installPaths" ] ) {
			structDelete( manifest, key );
		}
		manifest[ "ignore" ] = [];
		var files            = {};
		for (
			var filename in [
				"ModuleConfig.cfc",
				"README.md",
				"LICENSE",
				"NOTICE",
				"CHANGELOG.md",
				"CONTRIBUTING.md",
				"SECURITY.md"
			]
		) {
			files[ filename ] = fileReadBinary( root & "/" & filename );
		}
		for ( var folder in [ "models", "docs" ] ) {
			collectFiles( root, folder, files );
		}
		files[ "box.json" ]         = javacast( "string", serializeJSON( manifest, false, false ) & chr( 10 ) ).getBytes( "UTF-8" );
		files[ "ModuleConfig.cfc" ] = moduleConfig( files[ "ModuleConfig.cfc" ], version );
		var destinationRoot         = createObject( "java", "java.io.File" )
			.init( fileSystemUtil.resolvePath( output ) )
			.getCanonicalPath();
		if ( !directoryExists( destinationRoot ) ) {
			directoryCreate( destinationRoot, true );
		}
		var destination = destinationRoot & "/" & manifest.slug & "-" & version & ".zip";
		writeZip( destination, files );
		var checksum = lCase( hash( fileReadBinary( destination ), "SHA-256" ) );
		fileWrite( destination & ".sha256", checksum & "  " & getFileFromPath( destination ) & chr( 10 ) );
		var fileHashes = structNew( "ordered" );
		var names      = structKeyArray( files );
		names.sort( "text" );
		for ( var name in names ) {
			fileHashes[ name ] = lCase( hash( files[ name ], "SHA-256" ) );
		}
		var report          = structNew( "ordered" );
		report[ "package" ] = manifest;
		report[ "sha256" ]  = checksum;
		report[ "files" ]   = fileHashes;
		fileWrite( destinationRoot & "/manifest.json", serializeJSON( report, false, false ) & chr( 10 ) );
		print.greenLine( destination );
	}

	private function validateVersion( required string version, required string name ){
		require(
			reFind( "^[0-9]+[.][0-9]+[.][0-9]+(?:-[0-9A-Za-z.-]+)?(?:[+][0-9A-Za-z.-]+)?$", version ) == 1,
			name & " must use an exact semantic version."
		);
	}

	private function collectFiles(
		required string root,
		required string folder,
		required struct files
	){
		var paths    = createObject( "java", "java.nio.file.Paths" );
		var javaRoot = paths.get( javacast( "string", root & "/" & folder ), javacast( "string[]", [] ) );
		var api      = createObject( "java", "java.nio.file.Files" );
		var stream   = api.walk( javaRoot, javacast( "java.nio.file.FileVisitOption[]", [] ) );
		try {
			var iterator = stream.iterator();
			while ( iterator.hasNext() ) {
				var path = iterator.next();
				require( !api.isSymbolicLink( path ), "Symlinks are not allowed in release artifacts." );
				if ( api.isRegularFile( path, javacast( "java.nio.file.LinkOption[]", [] ) ) ) {
					var pathText = createObject( "java", "java.lang.String" ).valueOf(
						javacast( "java.lang.Object", path )
					);
					var relative = replace(
						mid( pathText, len( root ) + 2, len( pathText ) ),
						chr( 92 ),
						"/",
						"all"
					);
					var hidden = false;
					for ( var part in listToArray( relative, "/" ) ) {
						if ( left( part, 1 ) == "." ) {
							hidden = true;
							break;
						}
					}
					if ( !hidden ) {
						files[ relative ] = api.readAllBytes( path );
					}
				}
			}
		} finally {
			stream.close();
		}
	}

	private function moduleConfig( required any bytes, required string version ){
		var source  = charsetEncode( bytes, "UTF-8" );
		var pattern = createObject( "java", "java.util.regex.Pattern" ).compile(
			javacast( "string", "(this\.version\s*=\s*"")[^""]+("";)" )
		);
		var matcher = pattern.matcher( javacast( "string", source ) );
		require( matcher.find(), "Expected one module version declaration." );
		var updated = left( source, matcher.start() ) & matcher.group( 1 ) & version & matcher.group( 2 ) &
		mid( source, matcher.end() + 1, len( source ) );
		require( !matcher.find(), "Expected one module version declaration." );
		return javacast( "string", updated ).getBytes( "UTF-8" );
	}

	private function writeZip( required string destination, required struct files ){
		var names = structKeyArray( files );
		names.sort( "text" );
		var stream = createObject( "java", "org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream" ).init(
			createObject( "java", "java.io.FileOutputStream" ).init( destination )
		);
		stream.setLevel( 9 );
		var fixedTime = createObject( "java", "java.time.LocalDateTime" )
			.of(
				javacast( "int", 2020 ),
				javacast( "int", 1 ),
				javacast( "int", 1 ),
				javacast( "int", 0 ),
				javacast( "int", 0 )
			)
			.atZone( createObject( "java", "java.time.ZoneId" ).systemDefault() )
			.toInstant()
			.toEpochMilli();
		try {
			for ( var name in names ) {
				var entry = createObject( "java", "org.apache.commons.compress.archivers.zip.ZipArchiveEntry" ).init(
					javacast( "string", name )
				);
				entry.setTime( fixedTime );
				entry.setUnixMode( 33188 );
				stream.putArchiveEntry( entry );
				stream.write( files[ name ] );
				stream.closeArchiveEntry();
			}
			stream.finish();
		} finally {
			stream.close();
		}
	}

	private function require( required boolean condition, required string message ){
		if ( !condition ) {
			throw( message = message );
		}
	}

}
