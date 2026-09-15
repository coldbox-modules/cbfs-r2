component
	extends      ="coldbox.system.testing.BaseTestCase"
	appMapping   ="/harness"
	configMapping="harness.config.Coldbox"
{

	function run(){
		describe( "R2 S3 HTTP contract", () => {
			beforeEach( () => setup() );
			it( "signs actual HTTP requests, preserves binary bytes, and issues private and public URLs", () => {
				var port = val( getSystemSetting( "R2_CONTRACT_PORT", "0" ) );
				expect( port ).toBeGT( 0 );
				var endpoint = "127.0.0.1:#port#";
				var disk     = getWireBox().getInstance( "R2Provider@cbfs-r2" );
				disk.startup(
					"private-contract",
					{
						"accessKey"              : "contract-access",
						"secretKey"              : "contract-secret",
						"awsDomain"              : endpoint,
						"awsRegion"              : "auto",
						"bucketName"             : "private-contract",
						"defaultBucketName"      : "private-contract",
						"path"                   : "",
						"publicDomain"           : endpoint,
						"visibility"             : "private",
						"allowInsecureLocalhost" : true,
						"defaultACL"             : "",
						"signatureType"          : "V4",
						"defaultTimeOut"         : 5,
						"retriesOnError"         : 0
					}
				);
				var key   = "receipts/organization/folder/file.pdf";
				var bytes = binaryDecode( "00010203fffe80abcd2500", "hex" );
				expect( disk.exists( key ) ).toBeFalse();
				disk.create( key, bytes );
				expect( disk.exists( key ) ).toBeTrue();
				expect( disk.info( key ).size ).toBe( 11 );
				expect( disk.visibility( key ) ).toBe( "private" );
				expect( () => disk.setVisibility( key, "public" ) ).toThrow( "r2sdk.UnsupportedACL" );
				expect( () => disk.create( "public.pdf", bytes, "public" ) ).toThrow( "r2sdk.UnsupportedACL" );
				expect( hash( disk.getAsBinary( key ), "SHA-256" ) ).toBe( hash( bytes, "SHA-256" ) );
				expect( () => disk.create( key, bytes ) ).toThrow( "cbfs.FileOverrideException" );
				var signedUrl = disk.temporaryURL( key, 2 );
				expect( signedUrl ).toStartWith( "http://#endpoint#/private-contract/" );
				var downloaded = getHttp( signedUrl );
				expect( downloaded.statusCode ).toStartWith( "200" );
				expect( hash( downloaded.fileContent, "SHA-256" ) ).toBe( hash( bytes, "SHA-256" ) );
				var unicodeKey = "receipts/organization/été + 25%.pdf";
				disk.create( unicodeKey, bytes );
				expect( hash( getHttp( disk.temporaryURL( unicodeKey, 2 ) ).fileContent, "SHA-256" ) ).toBe(
					hash( bytes, "SHA-256" )
				);
				disk.copy( key, "copied.pdf" );
				expect( hash( disk.getAsBinary( "copied.pdf" ), "SHA-256" ) ).toBe( hash( bytes, "SHA-256" ) );
				expect( () => disk.copy( key, "copied.pdf" ) ).toThrow( "cbfs.FileOverrideException" );
				disk.move( "copied.pdf", "moved.pdf" );
				expect( disk.exists( "copied.pdf" ) ).toBeFalse();
				expect( disk.exists( "moved.pdf" ) ).toBeTrue();
				expect( () => disk.move( "moved.pdf", "fail-copy.pdf" ) ).toThrow();
				expect( disk.exists( "moved.pdf" ) ).toBeTrue();
				var uploadPath = getTempDirectory() & createUUID() & ".pdf";
				try {
					fileWrite( uploadPath, bytes );
					disk.createFromFile(
						source       = uploadPath,
						directory    = "uploads",
						name         = "upload.pdf",
						overwrite    = false,
						deleteSource = true
					);
					expect( fileExists( uploadPath ) ).toBeFalse();
					expect( hash( disk.getAsBinary( "uploads/upload.pdf" ), "SHA-256" ) ).toBe(
						hash( bytes, "SHA-256" )
					);
				} finally {
					if ( fileExists( uploadPath ) ) {
						fileDelete( uploadPath );
					}
				}
				var tamperedUrl = replace(
					signedUrl,
					"X-Amz-Expires=120",
					"X-Amz-Expires=119"
				);
				expect( getHttp( tamperedUrl ).statusCode ).toStartWith( "403" );
				expect( () => disk.temporaryURL( key, 0 ) ).toThrow( "r2sdk.InvalidSignedURL" );
				disk.delete( key );
				expect( disk.exists( key ) ).toBeFalse();
				var publicDisk = getWireBox().getInstance( "R2Provider@cbfs-r2" );
				publicDisk.startup(
					"public-contract",
					{
						"accessKey"              : "contract-access",
						"secretKey"              : "contract-secret",
						"awsDomain"              : endpoint,
						"awsRegion"              : "auto",
						"bucketName"             : "public-contract",
						"defaultBucketName"      : "public-contract",
						"path"                   : "",
						"publicDomain"           : "assets.example.test",
						"visibility"             : "public",
						"allowInsecureLocalhost" : true,
						"defaultACL"             : "",
						"signatureType"          : "V4",
						"defaultTimeOut"         : 5,
						"retriesOnError"         : 0
					}
				);
				publicDisk.create( "logos/logo.png", bytes );
				expect( publicDisk.url( "logos/logo.png" ) ).toBe( "http://assets.example.test/logos/logo.png" );
				expect( publicDisk.url( "logos/été + 25%.png" ) ).toBe(
					"http://assets.example.test/logos/%C3%A9t%C3%A9%20%2B%2025%25.png"
				);
				publicDisk.delete( "logos/logo.png" );
				var evidence = deserializeJSON( getHttp( "http://#endpoint#/__evidence" ).fileContent );
				expect( evidence.len() ).toBeGTE( 10 );
				expect( evidence.filter( ( entry ) => !entry.valid ).len() ).toBe( 1 );
				var rejectedRequests = evidence.filter( ( entry ) => !entry.valid );
				expect( rejectedRequests[ 1 ].error ).toBe( "signature mismatch" );
			} );
		} );
	}

	private struct function getHttp( required string address ){
		cfhttp(
			url         = arguments.address,
			method      = "GET",
			result      = "local.response",
			getAsBinary = "auto",
			timeout     = 5
		);
		return response;
	}

}
