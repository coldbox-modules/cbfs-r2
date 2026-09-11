# Contributing

Use a feature branch. Document public API changes and add focused TestBox coverage.
Storage changes need real HTTP protocol tests using synthetic credentials.
Never commit keys, signed URLs, private data, or environment files.

Run formatting, standalone tests, documentation generation, and package verification
before opening a pull request. See [development](docs/development.md) and
[releasing](docs/releasing.md) for commands and release responsibilities.

Use Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `ci:`). Explain
breaking changes with `BREAKING CHANGE:` in the body, and update the changelog.
