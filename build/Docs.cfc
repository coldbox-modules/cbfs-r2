/** Generate a complete API reference, including inherited module APIs. */
component {

	function run(){
		var root        = getCWD();
		var descriptor  = deserializeJSON( fileRead( root & "/box.json" ) );
		var mappingName = descriptor.slug == "cbfs-r2" ? "cbfsr2" : descriptor.slug;
		fileSystemUtil.createMapping( mappingName, root );
		var sources                        = {};
		sources[ mappingName & ".models" ] = root & "/models";
		var included                       = { "#mappingName#" : true };
		directoryList(
			root & "/modules",
			true,
			"path",
			"ModuleConfig.cfc"
		).each( function( item ){
			var folder = getDirectoryFromPath( item );
			if ( fileExists( folder & "box.json" ) ) {
				var dependency = deserializeJSON( fileRead( folder & "box.json" ) );
				if ( !structKeyExists( included, dependency.slug ) ) {
					fileSystemUtil.createMapping( dependency.slug, folder );
					included[ dependency.slug ] = true;
					if (
						directoryExists( folder & "models" ) && listFindNoCase(
							"s3sdk,cbfs,r2sdk",
							dependency.slug
						)
					) {
						sources[ dependency.slug & ".models" ] = folder & "models";
					}
				}
			}
		} );
		if ( directoryExists( root & "/.artifacts/apidocs" ) ) {
			directoryDelete( root & "/.artifacts/apidocs", true );
		}
		directoryCreate( root & "/.artifacts/apidocs", true, true );
		command( "docbox generate" )
			.params(
				mappings                = sources,
				excludes                = "testing",
				"strategy-projectTitle" = descriptor.slug & " " & descriptor.version,
				"strategy-outputDir"    = root & "/.artifacts/apidocs"
			)
			.run();
		if ( shell.getExitCode() ) {
			error( "API documentation generation failed" );
		}
	}

}
