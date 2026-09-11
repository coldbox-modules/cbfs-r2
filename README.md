# cbfs-r2

A Cloudflare R2 disk provider for [cbfs](https://cbfs.ortusbooks.com), using the
separate `r2sdk` module. Keep application file operations on cbfs and select local
storage in development or R2 in production through configuration.

Apache 2.0 · ColdBox module · BoxLang CFML / Lucee / Adobe ColdFusion

Releases: [GitHub](https://github.com/coldbox-modules/cbfs-r2/releases) ·
[ForgeBox](https://forgebox.io/view/cbfs-r2). See [development](docs/development.md)
for local installs and verification.

## Installation and configuration

Install with `box install cbfs-r2`. CommandBox installs cbfs
and r2sdk as dependencies. Register a disk in ColdBox configuration:

```cfml
moduleSettings.cbfs.disks.documents = {
    provider : "R2Provider@cbfs-r2",
    properties : {
        accessKey : getSystemSetting( "R2_ACCESS_KEY_ID" ),
        secretKey : getSystemSetting( "R2_SECRET_ACCESS_KEY" ),
        awsDomain : getSystemSetting( "R2_ENDPOINT_HOST" ),
        bucketName : "documents",
        path : "",
        visibility : "private"
    }
};
```

The endpoint is the bare account hostname, such as
`0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com`. It is not a public
media domain. Keys must have permission to read/write the configured bucket.

```cfml
property name="documents" inject="cbfs:disks:documents";

// Save bytes and retain only the relative key in your database.
documents.create( "receipts/123.pdf", pdfBytes );
var bytes = documents.getAsBinary( "receipts/123.pdf" );
var download = documents.temporaryURL( "receipts/123.pdf", 2 );
documents.copy( "receipts/123.pdf", "archive/123.pdf" );
documents.delete( "receipts/123.pdf" );
```

For local development, configure the same disk name using cbfs's local provider.
Application callers keep the same dependency and methods.

## Public images and private receipts

Use separate buckets. A public disk sets `visibility="public"` and
`publicDomain="assets.example.com"`; configure that domain on the bucket in
Cloudflare first. Public `url()` returns an encoded custom-domain URL. Private
`url()` returns a signed URL; `temporaryURL()` always signs the authenticated R2
endpoint. Never store a signed URL as a durable database reference.

Visibility describes the bucket; it cannot change Cloudflare's configuration.
Changing an individual object to a different visibility or calling `chmod()`
throws `r2sdk.UnsupportedACL`. A public custom domain does not belong on a private
receipt bucket.

## Configuration reference

| Property | Default | Purpose |
| --- | --- | --- |
| `accessKey`, `secretKey` | required | R2 S3 credentials, not API bearer tokens |
| `awsDomain` | required | Bare account endpoint; EU/FedRAMP endpoint labels accepted |
| `bucketName` | required | Bucket already provisioned in Cloudflare |
| `path` | empty | Object-key prefix for this disk |
| `visibility` | `private` | `private` or `public`, matching the actual bucket |
| `publicDomain` | empty | Required bare hostname for a public disk |
| `defaultTimeOut` | `30` | Request timeout in seconds |
| `retriesOnError` | `3` | S3 SDK transport retry count |
| `debug` | `false` | Avoid enabling in production |
| `allowInsecureLocalhost` | `false` | HTTP only to explicit `127.0.0.1:port` test fixtures |

HTTPS, Signature V4, path-style addressing, and disabled object ACLs are enforced.
Existence lookups are uncached to avoid stale overwrite decisions.

## Behavior and limits

Object operations cover create, createFromFile, get/getAsBinary, exists,
info/size/mimeType, URLs, copy, move, and delete. `createFromFile` buffers the file
in memory and retains it unless `deleteSource=true`; the source is deleted only
after the object store confirms the write. Enforce upload limits.

Copy completes before move deletes its source. Moves are not atomic; a failed
delete can leave both copies. `overwrite=false` uses a preflight existence check,
not a conditional write, so use unique immutable keys for concurrent uploads.
Directory operations inherited from cbfs still require explicit R2 verification;
do not assume untested inheritance establishes compatibility.

The package retains cbfs lifecycle/file interception events. It adds no handlers,
routes, migrations, application settings outside its namespace, or cloud resources.

## Documentation and contribution

- [Development, formatting, and tests](docs/development.md)
- [Troubleshooting and live smoke test](docs/troubleshooting.md)
- [Release automation and recovery](docs/releasing.md)
- [Contribution guidelines](CONTRIBUTING.md) · [Security](SECURITY.md)
- Generate API HTML locally with `box run-script build:docs`.

Local tests use an independent HTTP fixture with synthetic credentials. Live R2
permissions, custom-domain TLS, and account configuration need a separate smoke
test. See [Cloudflare's compatibility reference](https://developers.cloudflare.com/r2/api/s3/api/).
