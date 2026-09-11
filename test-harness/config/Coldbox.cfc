component {

	function configure(){
		coldbox = {
			"appName"                 : "R2 module harness",
			"defaultEvent"            : "",
			"handlersIndexAutoReload" : false,
			"modulesExternalLocation" : [ "/packageModules" ]
		};
		moduleSettings = {
			"r2sdk" : {
				"accessKey"              : "contract-access",
				"secretKey"              : "contract-secret",
				"awsDomain"              : "127.0.0.1:" & getSystemSetting( "R2_CONTRACT_PORT" ),
				"defaultBucketName"      : "private-contract",
				"allowInsecureLocalhost" : true,
				"defaultTimeOut"         : 5,
				"retriesOnError"         : 0
			}
		};
	}

	function cbLoadInterceptorHelpers( event, interceptData, rc, prc ){
		controller
			.getModuleService()
			.registerAndActivateModule( moduleName = request.MODULE_NAME, invocationPath = "moduleroot" );
	}

}
