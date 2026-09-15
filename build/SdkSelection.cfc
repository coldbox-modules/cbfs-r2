/** Select an explicitly supplied local SDK without replacing published dependencies. */
component {

	function select(
		required struct manifest,
		required string workspace,
		string sdkSource = ""
	){
		if ( manifest.slug != "cbfs-r2" ) {
			require( !len( sdkSource ), "--sdk-source applies only to cbfs-r2." );
			return manifest;
		}
		require(
			structKeyExists( manifest, "dependencies" ) && structKeyExists( manifest.dependencies, "r2sdk" ),
			"cbfs-r2 requires an r2sdk dependency."
		);
		if ( !len( sdkSource ) ) {
			require(
				left( manifest.dependencies.r2sdk, 1 ) != ".",
				"Supply --sdk-source until r2sdk has a published dependency version."
			);
			return manifest;
		}
		var source = canonical( sdkSource );
		require( directoryExists( source ), "The explicit SDK source directory does not exist." );
		require( fileExists( source & "/box.json" ), "The explicit SDK source has no box.json." );
		require(
			deserializeJSON( fileRead( source & "/box.json" ) ).slug == "r2sdk",
			"The explicit SDK source is not r2sdk."
		);
		var destination = canonical( workspace ) & "/r2sdk";
		require( !directoryExists( destination ), "The SDK destination already exists." );
		copySource( source, destination );
		manifest.dependencies[ "r2sdk" ] = destination & "/";
		return manifest;
	}

	private function copySource( required string source, required string destination ){
		var paths  = createObject( "java", "java.nio.file.Paths" );
		var files  = createObject( "java", "java.nio.file.Files" );
		var root   = paths.get( javacast( "string", source ), javacast( "string[]", [] ) );
		var stream = files.walk( root, javacast( "java.nio.file.FileVisitOption[]", [] ) );
		try {
			var iterator = stream.iterator();
			while ( iterator.hasNext() ) {
				var path     = iterator.next();
				var pathText = createObject( "java", "java.lang.String" ).valueOf(
					javacast( "java.lang.Object", path )
				);
				var relative = len( pathText ) > len( source ) ? mid(
					pathText,
					len( source ) + 2,
					len( pathText )
				) : "";
				var skip = false;
				for ( var part in listToArray( replace( relative, chr( 92 ), "/", "all" ), "/" ) ) {
					if (
						listFindNoCase(
							".git,.engine,.artifacts,.tmp,modules,coldbox,testbox,__pycache__,results",
							part
						) || ( left( part, 4 ) == ".env" && part != ".env.example" )
					) {
						skip = true;
						break;
					}
				}
				if ( skip ) {
					continue;
				}
				var target = destination & ( len( relative ) ? "/" & relative : "" );
				require( !files.isSymbolicLink( path ), "Symlinks are not allowed in the SDK source." );
				if ( files.isDirectory( path, javacast( "java.nio.file.LinkOption[]", [] ) ) ) {
					if ( !directoryExists( target ) ) {
						directoryCreate( target, true );
					}
				} else if ( files.isRegularFile( path, javacast( "java.nio.file.LinkOption[]", [] ) ) ) {
					fileWrite( target, files.readAllBytes( path ) );
				}
			}
		} finally {
			stream.close();
		}
	}

	private string function canonical( required string path ){
		return createObject( "java", "java.io.File" ).init( path ).getCanonicalPath();
	}

	private function require( required boolean condition, required string message ){
		if ( !condition ) {
			throw( message = message );
		}
	}

}
