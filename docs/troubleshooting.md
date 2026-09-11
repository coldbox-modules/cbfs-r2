# Troubleshooting

| Symptom | Check |
| --- | --- |
| `r2sdk.InvalidCredentials` | Supply an R2 S3 access key ID and secret, not a Cloudflare API token. |
| `r2sdk.InvalidEndpoint` | Use the bare account hostname, without scheme, bucket, slash, or query string. |
| `r2sdk.UnsupportedACL` | R2 visibility belongs to the bucket. Remove ACL arguments and use separate public/private buckets. |
| Signature mismatch | Confirm credentials, system UTC clock, encoded object name, HTTP method, and any signed headers. Do not rewrite a signed URL. |
| 403 | Check bucket-scoped credential permissions and expiry; distinguish access denial from absence. |
| Public URL 404 | Enable the custom domain on the correct bucket; confirm the object prefix. |
| Private download expires | Generate URLs when needed instead of persisting them in the database. |
| Memory pressure during upload | The provider buffers file contents. Enforce upload limits and plan multipart/streaming work before accepting large files. |

Debug logging can contain object names or signed request data. Keep it disabled
in production and redact credentials, authorization headers, and signed URLs
before sharing logs.

## Live smoke test

Use a disposable private bucket with a narrowly scoped credential. Write a small
binary object with a unique key; read it back and compare SHA-256; check HEAD
metadata; download a short-lived signed URL; copy then move; verify the source
and destination; delete all test objects. An unsigned private URL must fail.
For public storage, repeat URL checks on a separate bucket with its configured
custom domain. Never make a private bucket public to troubleshoot a download.
Record runtime, module and dependency versions, endpoint jurisdiction, timestamp,
and results without credentials. Local contract success does not replace this
account-specific check.
