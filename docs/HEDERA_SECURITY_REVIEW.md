# Hedera lightweight profile review

## Decision

`hedera-core` is a lightweight, read-only observer. It uses Hedera's fixed public Mirror Node REST endpoints for Mainnet, Testnet, and Previewnet and opens deep links on HashScan. It installs no Hedera binary, starts no local service, creates no account, and requires neither Docker nor Kubernetes.

The default is Testnet. Network switching accepts only the three names compiled into the guarded CLI; users cannot provide an arbitrary Mirror Node URL. Responses have a short timeout, reject redirects, and are capped at 1 MiB.

## Supported surface

- Latest block, consensus timestamp, HAPI version, node count, and latency.
- Curated consensus-node output.
- Curated account metadata and balance lookup by `0.0.N` or EVM address.
- Curated transaction result lookup by transaction ID.
- Latest-block deep links to the matching HashScan network.

The CLI deliberately does not forward full Mirror Node responses. Account key fields, transfer lists, and unrelated payloads stay outside the workstation output.

## Why Solo is separate

[Hiero Solo](https://github.com/hiero-ledger/solo) is the official local-network direction, but the current supported deployment creates a Kubernetes-based network and funded test accounts. Its present requirements—at least 12 GB RAM and 6 CPU cores—are unsuitable as the default experience for small Omarchy machines. It also writes operator and test-account signing material to disk, which conflicts with this plugin's no-key boundary.

Solo contributors have discussed small-hardware support, including Raspberry Pi-class systems. That roadmap is encouraging but is not treated as a released dependency contract. A future `hedera-solo-lab` must remain optional and separate from `hedera-core`, and will be reviewed only against an actual supported upstream release and its documented account/key behavior.

## Limitations

- Mirror Node is an indexed historical view, not a consensus-node submission endpoint.
- The profile cannot deploy contracts, submit transactions, emulate Hedera Services, or reproduce HTS/system-contract semantics locally.
- Network connectivity is required; the profile is lightweight, not offline.
- A public service can observe the workstation's IP address and request metadata.

## Official references

- [Mirror Node REST API](https://docs.hedera.com/hedera/sdks-and-apis/rest-api)
- [List blocks](https://docs.hedera.com/api-reference/blocks/list-blocks)
- [Network nodes](https://docs.hedera.com/api-reference/network/get-the-network-address-book-nodes)
- [Account lookup](https://docs.hedera.com/api-reference/accounts/get-account-by-alias-id-or-evm-address)
- [Solo quick start](https://solo.hiero.org/docs/simple-solo-setup/quickstart/)
- [Using Solo with Hiero SDKs](https://solo.hiero.org/docs/using-solo/using-solo-with-hiero-sdks/)
