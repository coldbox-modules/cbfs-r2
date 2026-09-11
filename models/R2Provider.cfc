/** cbfs disk backed by r2sdk; visibility describes the bucket, never an object ACL. */
component extends="cbfs.models.providers.S3Provider" {

	/**
	 * Configure and start this disk without provisioning cloud resources.
	 *
	 * @name       Unique cbfs disk name.
	 * @properties R2 credentials, account endpoint, bucket, prefix and visibility.
	 *
	 * @return This configured disk.
	 *
	 * @throws cbfs.ProviderConfigurationException ,r2sdk.InvalidCredentials,r2sdk.InvalidEndpoint
	 */
	function startup( required string name, struct properties = {} ){
		param arguments.properties.path         = "";
		param arguments.properties.visibility   = "private";
		param arguments.properties.publicDomain = "";
		if ( !listFindNoCase( "private,public", arguments.properties.visibility ) ) {
			throw(
				type    = "cbfs.ProviderConfigurationException",
				message = "R2 disk visibility must be private or public."
			);
		}
		if (
			arguments.properties.visibility == "public" &&
			!reFindNoCase( "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", arguments.properties.publicDomain )
		) {
			throw(
				type    = "cbfs.ProviderConfigurationException",
				message = "Public R2 disks require their Cloudflare public domain as a bare hostname."
			);
		}
		arguments.properties.cacheLookups = false;
		variables.s3                      = createObject( "component", "r2sdk.models.Client" ).init(
			argumentCollection = arguments.properties
		);
		variables.wirebox.autowire( variables.s3 );
		arguments.properties.ssl = variables.s3.getSSL();
		setName( arguments.name );
		setProperties( arguments.properties );
		variables.intercept.announce( "cbfsOnDiskStart", { "disk" : this } );
		return this;
	}

	/**
	 * Write text or binary contents and announce cbfsOnFileCreate after success.
	 *
	 * @path       Relative object key.
	 * @contents   Text or binary contents, buffered in memory.
	 * @visibility Must match the configured bucket visibility.
	 * @metadata   User metadata.
	 * @overwrite  Permit replacing an existing object; preflight check is not atomic.
	 *
	 * @return This disk.
	 *
	 * @throws cbfs.FileOverrideException ,r2sdk.UnsupportedACL,StorageWriteException
	 */
	function create(
		required path,
		required contents,
		string visibility = variables.properties.visibility,
		struct metadata   = {},
		boolean overwrite = false
	){
		requireBucketVisibility( arguments.visibility );
		if ( !arguments.overwrite && exists( arguments.path, true ) ) {
			throw( type = "cbfs.FileOverrideException", message = "The stored object already exists." );
		}
		var result = variables.s3.putObject(
			bucketName  = variables.properties.bucketName,
			uri         = objectKey( arguments.path ),
			data        = arguments.contents,
			contentType = getMimeType( arguments.path ),
			metaHeaders = arguments.metadata
		);
		if ( !len( result ) ) {
			throw( type = "StorageWriteException", message = "The object store did not confirm the write." );
		}
		variables.intercept.announce( "cbfsOnFileCreate", { "file" : this.file( arguments.path ) } );
		return this;
	}

	/**
	 * Upload a local file, optionally deleting it only after a confirmed write.
	 *
	 * @source       Local filesystem path.
	 * @directory    Relative destination directory.
	 * @name         Destination filename; defaults to the source filename.
	 * @visibility   Must match bucket visibility.
	 * @overwrite    Permit replacing an existing object.
	 * @deleteSource Delete the local source after success.
	 *
	 * @return cbfs.models.File
	 */
	function createFromFile(
		required string source,
		required string directory,
		string name          = getFileFromPath( arguments.source ),
		string visibility    = variables.properties.visibility,
		boolean overwrite    = true,
		boolean deleteSource = false
	){
		var destination = listAppend( arguments.directory, arguments.name, "/" );
		create(
			destination,
			fileReadBinary( arguments.source ),
			arguments.visibility,
			{},
			arguments.overwrite
		);
		if ( arguments.deleteSource ) {
			fileDelete( arguments.source );
		}
		return this.file( destination );
	}

	/**
	 * Read arbitrary bytes without allowing the CFML HTTP client to decode them as text.
	 *
	 * @path Relative object key.
	 *
	 * @return Binary object contents.
	 *
	 * @throws cbfs.FileNotFoundException ,StorageReadException
	 */
	any function getAsBinary( required path ){
		if ( !exists( arguments.path, true ) ) {
			throw( type = "cbfs.FileNotFoundException", message = "The requested object does not exist." );
		}
		var response = variables.s3.getObject(
			bucketName  = variables.properties.bucketName,
			uri         = objectKey( arguments.path ),
			getAsBinary = true
		).response;
		if ( isBinary( response ) ) {
			return response;
		}
		if ( getMetadata( response ).name == "java.io.ByteArrayOutputStream" ) {
			return response.toByteArray();
		}
		throw( type = "StorageReadException", message = "The object store did not return binary contents." );
	}

	/**
	 * Return configured bucket visibility; no Cloudflare permission lookup occurs.
	 *
	 * @path Relative object key.
	 *
	 * @return private or public.
	 */
	string function visibility( required string path ){
		return variables.properties.visibility;
	}

	/**
	 * Return a signed private download or an encoded public custom-domain URL.
	 *
	 * @path Relative object key.
	 *
	 * @return Download URL; private URLs expire after the default one minute.
	 */
	string function url( required string path ){
		if ( variables.properties.visibility == "private" ) {
			return temporaryURL( arguments.path );
		}
		var encodedKey = new r2sdk.models.SignatureV4().buildCanonicalURI( objectKey( arguments.path ) );
		return ( variables.properties.ssl ? "https://" : "http://" ) & variables.properties.publicDomain & encodedKey;
	}

	/**
	 * Accept only the existing bucket visibility; this never changes a Cloudflare bucket.
	 *
	 * @path       Relative object key.
	 * @visibility Desired visibility; must match this disk.
	 *
	 * @return This disk.
	 *
	 * @throws r2sdk.UnsupportedACL
	 */
	function setVisibility( required string path, required string visibility ){
		requireBucketVisibility( arguments.visibility );
		return this;
	}

	/**
	 * Reject filesystem permissions because R2 does not provide object ACLs.
	 *
	 * @path Relative key.
	 * @mode Requested filesystem mode.
	 *
	 * @throws r2sdk.UnsupportedACL
	 */
	function chmod( required string path, required string mode ){
		throw( type = "r2sdk.UnsupportedACL", message = "R2 does not support per-object filesystem permissions." );
	}

	/**
	 * Copy an object after source and overwrite checks.
	 *
	 * @source      Relative source key.
	 * @destination Relative destination key.
	 * @overwrite   Permit replacing an existing object.
	 *
	 * @return This disk.
	 *
	 * @throws cbfs.FileNotFoundException ,cbfs.FileOverrideException,StorageWriteException
	 */
	function copy(
		required source,
		required destination,
		boolean overwrite = false
	){
		if ( !exists( arguments.source, true ) ) {
			throw( type = "cbfs.FileNotFoundException", message = "The source object does not exist." );
		}
		if ( !arguments.overwrite && exists( arguments.destination, true ) ) {
			throw( type = "cbfs.FileOverrideException", message = "The destination object already exists." );
		}
		if (
			!variables.s3.copyObject(
				fromBucket = variables.properties.bucketName,
				fromURI    = objectKey( arguments.source ),
				toBucket   = variables.properties.bucketName,
				toURI      = objectKey( arguments.destination )
			)
		) {
			throw( type = "StorageWriteException", message = "The object store did not confirm the copy." );
		}
		variables.intercept.announce(
			"cbfsOnFileCopy",
			{
				"source"      : arguments.source,
				"destination" : arguments.destination,
				"disk"        : this
			}
		);
		return this;
	}

	/**
	 * Copy first, then delete the source; this is not an atomic rename.
	 *
	 * @source      Relative source key.
	 * @destination Relative destination key.
	 * @overwrite   Permit replacing an existing object.
	 *
	 * @return This disk. Source remains if copy fails; both may remain if delete fails.
	 */
	function move(
		required source,
		required destination,
		boolean overwrite = false
	){
		if ( arguments.source == arguments.destination ) {
			return this;
		}
		copy(
			arguments.source,
			arguments.destination,
			arguments.overwrite
		);
		delete( arguments.source, true );
		variables.intercept.announce(
			"cbfsOnFileMove",
			{
				"source"      : arguments.source,
				"destination" : arguments.destination,
				"disk"        : this
			}
		);
		return this;
	}

	/**
	 * Read object metadata using HEAD after an existence check.
	 *
	 * @path Relative object key.
	 *
	 * @return cbfs metadata struct; canRead/canWrite describe provider capabilities, not an IAM audit.
	 *
	 * @throws cbfs.FileNotFoundException
	 */
	struct function info( required path ){
		if ( !exists( arguments.path, true ) ) {
			throw( type = "cbfs.FileNotFoundException", message = "The requested object does not exist." );
		}
		var key     = objectKey( arguments.path );
		var headers = variables.s3.getObjectInfo( bucketName = variables.properties.bucketName, uri = key );
		var result  = {
			"name"         : getFileFromPath( key ),
			"path"         : key,
			"parent"       : getDirectoryFromPath( key ),
			"lastModified" : headers[ "Last-Modified" ],
			"size"         : val( headers[ "Content-Length" ] ),
			"type"         : headers[ "Content-Type" ],
			"canRead"      : true,
			"canWrite"     : true,
			"isHidden"     : variables.properties.visibility == "private"
		};
		variables.intercept.announce(
			"cbfsOnFileInfoRequest",
			{ "file" : this.file( arguments.path ), "info" : result }
		);
		return result;
	}

	private string function objectKey( required string path ){
		// Match cbfs path normalization so a trailing prefix slash cannot make
		// writes use a different key from reads and existence checks.
		var combined = replace(
			variables.properties.path & "/" & arguments.path,
			"\",
			"/",
			"all"
		);
		return listToArray( combined, "/" ).toList( "/" );
	}

	private void function requireBucketVisibility( required string visibility ){
		if ( arguments.visibility != variables.properties.visibility ) {
			throw(
				type    = "r2sdk.UnsupportedACL",
				message = "Object visibility must match the R2 disk. Use separate disks for public and private buckets."
			);
		}
	}

}
