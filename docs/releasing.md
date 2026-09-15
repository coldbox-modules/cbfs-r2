# Releases

This module is maintained at [coldbox-modules/cbfs-r2](https://github.com/coldbox-modules/cbfs-r2).
Its standalone GitHub Actions workflow verifies each pull request and publishes
new versions from `main` after all required jobs pass.

## One-time setup

1. Confirm repository ownership and ForgeBox slug ownership. Preserve Apache
   licensing and attribution. Set repository homepage/bugs/documentation metadata.
2. Publish r2sdk first. Keep cbfs-r2's dependency pinned to the exact released
   SDK version and test that published dependency in a clean install.
3. Add `FORGEBOX_TOKEN` as a secret on the `forgebox` GitHub environment. The
   workflow's built-in GitHub token needs contents-write permission for releases.
   Restrict this environment to the protected `main` branch. Optional environment
   reviewers can add a publication approval without changing the build pipeline.
4. Require the verification jobs before merging. Disable force pushes to main
   and protect release tags from deletion or replacement.
5. Review the initial version and changelog. Merge to main to trigger publication
   after every required test and packaging check passes.

## Versioning and automatic publishing

Version numbers are explicit in `box.json`; maintainers review them with the
change. Use semantic versioning: fix = patch, compatible feature = minor,
breaking API/behavior change = major. Conventional commit subjects are encouraged
for readable history, but a commit subject cannot silently change a release number.

Pull requests run formatting, standalone contracts, documentation, and artifact
checks. Pushes to main run the same checks, then publish only when the manifest
version has no existing release tag or ForgeBox version. A ForgeBox lookup
failure stops publication; only an explicit missing-entry response allows a
first publication. Prerelease versions produce GitHub prereleases. All jobs use the event's exact source SHA.
Release jobs are serialized and never cancel an in-progress publication.

The workflow builds an allowlisted ZIP, checksums, and generated API docs. It
creates a draft GitHub release targeting the tested SHA, uploads artifacts, then
publishes the module to ForgeBox from an isolated unpacked artifact. The release
becomes public after ForgeBox succeeds. No credentials are provided to PR tests.
The ZIP excludes tests, build scripts, dependencies, credentials, and CI files.
ForgeBox repackages the verified files; the ZIP checksum identifies the GitHub
artifact, while manifest.json records the individual payload file hashes.
Documentation ships with the module, and API HTML is downloadable with each release.

## Failed or partial publication

GitHub and ForgeBox are separate systems; publication is not atomic. If either
fails, inspect the logs and both destinations before retrying. Do not force-publish
over a version, move a tag, or delete a published version to make a run green.
The preflight also refuses an existing ForgeBox version after a partial release,
even if its GitHub tag is missing; it never silently substitutes old package bytes.
A failed draft release should remain draft. If ForgeBox accepted the version,
verify its artifact and checksum before completing the corresponding GitHub
release manually. If it did not, delete only the unpublished draft/tag after
review, then rerun verification for the original source. Fix code with a new
version rather than changing an already published artifact.

Local validation cannot prove ForgeBox credentials, repository permissions, or
hosted multi-runtime jobs. The first real release must be observed to completion
and followed by a fresh `box install <slug>@<version>` consumer smoke test.
