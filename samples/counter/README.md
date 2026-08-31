# Counter security smoke test

This sample has no external Solidity dependencies. Inside `limechain-web3 shell`:

```bash
forge build
forge test
slither .
echidna test/CounterEchidna.sol --contract CounterEchidna --config echidna.yaml
```

The workstation preinstalls the pinned Solidity compiler so these commands do not need to fetch a compiler after installation.
