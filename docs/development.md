# Development

Requirements: macOS or Linux, CommandBox 6.3+, Java 21, Python 3.10+, and Git.
The local runner uses Unix process and file-lock APIs; hosted jobs run on Ubuntu. Install
`commandbox-boxlang`, `commandbox-cfformat`, and `commandbox-docbox` in CommandBox.
The module source is CFML so it can load on BoxLang with CFML compatibility,
Lucee, and Adobe ColdFusion. The CI matrix is the supported runtime contract;
a configured job is not evidence of a passing run.

## Run the standalone contract

```sh
box install
box run-script format:check
python3 build/test_release_preflight.py
python3 build/test_sdk_selection.py
python3 build/test.py --engine boxlang@1.17.2+56
python3 build/test.py --engine lucee@6
python3 build/test.py --engine adobe@2023
```

The runner copies source to a disposable workspace, installs dependencies from
ForgeBox, starts its own loopback-only server and an independent Python R2
protocol fixture, runs TestBox, and removes its servers and workspace. It never
starts CommuniArts or requires Cloudflare credentials. It writes logs, TestBox
JSON, source hashes, and a cleanup report to a new temporary evidence directory.
Use `--output /absolute/new/directory` to choose that directory. A failing,
empty, errored, skipped, or source-modifying run exits nonzero.

The fixture independently checks Signature V4 over actual HTTP and stores binary
objects in memory. It is not a mock of SDK methods. Cloudflare IAM, TLS, billing,
CORS, custom domains, and real service limits still need a live smoke test.

For cbfs-r2 before the SDK's first publication, pass
`--sdk-source /absolute/path/to/r2sdk`. Source packages can remain siblings;
release artifacts must contain an exact published ForgeBox dependency.

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
`python3 build/package.py --help` for packaging options.

See [releasing](releasing.md) for publication gates and recovery.

The runner never discovers a sibling SDK implicitly. A published `r2sdk` version
is installed as declared unless `--sdk-source` is explicitly supplied. Folder
dependencies require that explicit development override. Hosted release verification
must omit it.
