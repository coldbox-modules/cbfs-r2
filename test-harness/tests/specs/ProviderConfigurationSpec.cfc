component
	extends      ="coldbox.system.testing.BaseTestCase"
	appMapping   ="/harness"
	configMapping="harness.config.Coldbox"
{

	function run(){
		describe( "R2 disk configuration", function(){
			beforeEach( function(){
				setup();
			} );
			it( "rejects unsupported visibility before contacting the store", function(){
				var disk = getInstance( "R2Provider@cbfs-r2" );
				expect( function(){
					disk.startup( "invalid", { visibility : "readonly" } );
				} ).toThrow( "cbfs.ProviderConfigurationException" );
			} );
			it( "requires a bare public hostname", function(){
				for (
					var domain in [
						"",
						"https://assets.example.com",
						"assets.example.com/path",
						"assets.example.com?token=1"
					]
				) {
					var disk = getInstance( "R2Provider@cbfs-r2" );
					expect( function(){
						disk.startup( "invalid", { visibility : "public", publicDomain : domain } );
					} ).toThrow( "cbfs.ProviderConfigurationException" );
				}
			} );
			it( "supports private storage without a public hostname", function(){
				var disk = getInstance( "R2Provider@cbfs-r2" ).startup(
					"private",
					{
						accessKey              : "contract-access",
						secretKey              : "contract-secret",
						awsDomain              : "127.0.0.1:" & createObject( "java", "java.lang.System" ).getenv( "R2_CONTRACT_PORT" ),
						bucketName             : "private-contract",
						allowInsecureLocalhost : true
					}
				);
				expect( disk.hasStarted() ).toBeTrue();
				expect( disk.getProperties().visibility ).toBe( "private" );
				expect( disk.getProperties().cacheLookups ).toBeFalse();
				expect( function(){
					disk.chmod( "file.pdf", "777" );
				} ).toThrow( "r2sdk.UnsupportedACL" );
				expect( disk.setVisibility( "file.pdf", "private" ).getName() ).toBe( "private" );
			} );
			it( "keeps a configured prefix on writes, reads, copies and signed URLs", function(){
				var disk = getInstance( "R2Provider@cbfs-r2" ).startup(
					"prefix",
					{
						accessKey              : "contract-access",
						secretKey              : "contract-secret",
						awsDomain              : "127.0.0.1:" & createObject( "java", "java.lang.System" ).getenv( "R2_CONTRACT_PORT" ),
						bucketName             : "private-contract",
						path                   : "scoped/",
						allowInsecureLocalhost : true,
						defaultTimeOut         : 5,
						retriesOnError         : 0
					}
				);
				var key = createUUID() & ".txt";
				disk.create( key, "prefixed content" );
				try {
					expect( disk.get( key ) ).toBe( "prefixed content" );
					expect( disk.info( key ).path ).toBe( "scoped/" & key );
					expect( disk.temporaryURL( key ) ).toInclude( "/private-contract/scoped/" & key );
					disk.copy( key, key & ".copy" );
					expect( disk.get( key & ".copy" ) ).toBe( "prefixed content" );
				} finally {
					disk.delete( key );
					disk.delete( key & ".copy" );
				}
			} );
		} );
	}

}
