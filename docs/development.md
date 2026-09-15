# Development

Requirements: macOS or Linux, CommandBox 6.3+, Java 21, and Git.
The local runner uses Unix process and file-lock APIs; hosted jobs run on Ubuntu. Install
`commandbox-boxlang`, `commandbox-cfformat`, and `commandbox-docbox` in CommandBox.
The module source is CFML so it can load on BoxLang with CFML compatibility,
Lucee, and Adobe ColdFusion. The CI matrix is the supported runtime contract;
a configured job is not evidence of a passing run.

## Run the standalone contract

```sh
box install
box run-script format:check
box task run build/ForgeBoxReleasePreflight selftest
box run-script test:sdk-selection
box task run build/TestStandalone.cfc run boxlang@1.17.2+56
box task run build/TestStandalone.cfc run lucee@6
box task run build/TestStandalone.cfc run adobe@2023
```

The repository rejects installed dependency source in Git during formatting checks.
The runner copies source to a disposable workspace, installs dependencies from
ForgeBox, starts its own loopback-only server and an independent Java 21 R2
protocol fixture, runs TestBox, and removes its servers and workspace. It never
starts CommuniArts or requires Cloudflare credentials. It writes logs, TestBox
JSON, source hashes, and a cleanup report to a new temporary evidence directory.
Pass the output directory as the second task argument to choose it. A failing,
empty, errored, skipped, or source-modifying run exits nonzero.

The fixture independently checks Signature V4 over actual HTTP and stores binary
objects in memory. It is not a mock of SDK methods. Cloudflare IAM, TLS, billing,
CORS, custom domains, and real service limits still need a live smoke test.

For cbfs-r2 development against an explicit local SDK checkout, pass its path
as the third task argument. Hosted release verification uses the published
dependency from ForgeBox.

## Make changes

Run `box run-script format` after CFML edits. Keep the public S3/cbfs signatures
compatible, including positional arguments. Add behavior tests at the module
boundary for changed operations. Use unique keys, test binary bytes and special
characters, and assert failure behavior as well as success. Never put real access
keys, signed production URLs, or uploaded user files in fixtures.

## Build

`box run-script build:docs` generates DocBox HTML under `.artifacts/apidocs`.
`box run-script build:module` creates a deterministic package ZIP and SHA-256
manifest under `.artifacts`. It refuses folder dependencies; use the documented
SDK version override when preparing the first provider release. Run
`box task run build/Package run .artifacts '' owner/repository` to build with
repository metadata.

See [releasing](releasing.md) for publication gates and recovery.

The runner never discovers a sibling SDK implicitly. A published `r2sdk` version
is installed as declared unless a source path is explicitly supplied. Folder
dependencies require that explicit development override.
