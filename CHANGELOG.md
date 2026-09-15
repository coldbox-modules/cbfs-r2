# Changelog

## 1.0.0 - 2026-09-15

- Initial cbfs disk provider backed by the separate r2sdk module.
- Support private signed downloads and public custom-domain URLs.
- Preserve binary uploads/downloads, prefixes, and confirmed copy-before-delete moves.
- Keep public/private visibility tied to bucket configuration without object ACLs.
- Add standalone HTTP contracts, CFFormat, DocBox API documentation, and release packaging.
- Add gated GitHub/ForgeBox publishing workflows for standalone repositories.
- Replace Python test orchestration with a CommandBox task and a Java 21 loopback fixture.
- Depend on the separately published r2sdk 1.0.0.
