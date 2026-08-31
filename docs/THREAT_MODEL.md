# Threat model

## Assets intentionally protected

- Wallet credentials and signing devices.
- User files reachable by the unsandboxed Quickshell process.
- Existing Omarchy configuration.
- Toolchain integrity and update provenance.
- The boundary between read-only inspection/local simulation and transaction submission.

## Trust boundaries

1. The user reviews and opts into the public Git repository.
2. The installer verifies every downloaded binary before extraction.
3. The Quickshell plugin is unsandboxed, so it is kept small and delegates to a fixed CLI.
4. Remote JSON-RPC services are untrusted. Responses have a short timeout and a 1 MiB size limit.
5. Explorer and RPC URLs are untrusted input and are structurally validated.
6. Agent-skill refusals are behavioral policy, not OS enforcement.

## Primary threats and mitigations

| Threat | Mitigation | Residual risk |
|---|---|---|
| Tampered release artifact | Pinned HTTPS URL and SHA-256 digest; CI drift check | A malicious upstream release plus deliberately updated lockfile still requires review |
| Malicious plugin update | Native Omarchy update shows the diff and requires fast-forward validation | Enabled plugin code retains user-level access |
| Credential leakage through RPC URL | Reject user info, queries, and fragments; never enumerate environment variables | A credential embedded unusually in a hostname or path cannot be identified reliably |
| Transaction submission by an agent | Guarded tool wrappers and explicit skill refusal | A user can deliberately bypass wrappers and run raw installed binaries |
| Anvil exposing deterministic test keys | Managed service and fork use `--accounts 0 --silent` | A manually launched raw Anvil process may choose different behavior |
| Surfpool contacting mainnet or reading the default Solana keypair | Fixed service uses `--offline`, `/dev/null`, zero startup airdrop, `ProtectHome=tmpfs`, and systemd network filtering that permits only localhost | A user can deliberately bypass the wrapper and run the raw binary |
| Surfpool MCP generating or returning key material | Arbitrary Surfpool subcommands and MCP are refused; the plugin exposes only service controls and read-only health | Upstream capabilities remain available in the raw binary outside the workstation wrapper |
| Existing config loss | Marker-bounded JSONC modification, native plugin state APIs, idempotent install | Manual edits inside the managed marker are replaced on reinstall |
| Host exposure of local RPC | Bind Anvil and Surfpool only to `127.0.0.1` | Other processes belonging to the same user can access the RPC |

## Out of scope

- Protecting a host already compromised at the user's privilege level.
- Sandboxing Quickshell itself.
- Securing raw tools invoked outside the workstation wrappers.
- Custody, signing, exchange, bridge, or mainnet deployment workflows.
