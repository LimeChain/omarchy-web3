# Build provenance

Tagged releases are expected to publish:

1. A source archive generated from the tagged commit.
2. `SHA256SUMS` for the archive and checked-in SBOM.
3. A GitHub artifact attestation binding the archive and SBOM to the release workflow and commit.

Consumers should verify the checksum first and then verify the attestation with GitHub CLI:

```bash
gh attestation verify limechain-omarchy-web3-*.tar.gz --repo limechain/omarchy-web3
```

Development snapshots are not release attestations.
