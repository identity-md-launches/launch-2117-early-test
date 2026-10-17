# EARLY TEST (EARLY)

A fixed-supply ERC-20 token for Ethereum. Join the community on
[Telegram](https://t.me/EARLYCATODAY).

## Token and assumptions

| Property | Value |
| --- | --- |
| Solidity contract | `EarlyToken` in `src/EarlyToken.sol` |
| Token name | `EARLY TEST` |
| Symbol | `EARLY` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Initial recipient | Constructor caller, `msg.sender` |
| Community metadata | `TELEGRAM_URL()` returns `https://t.me/EARLYCATODAY` |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Intended launch chain | Ethereum, chain ID `1` |

The entire supply is minted once in the constructor, with a single
`Transfer(address(0), deployer, supply)` event. In the intended launch the
deployer is the launch factory, so the factory receives all tokens. An EOA
deploying directly would instead receive all tokens itself. The transaction
origin and the caller of a factory are not used as recipients.

The request to “connect to this telegram” is interpreted as providing the public
community link. The link is available both above and through the immutable
`TELEGRAM_URL()` getter. The token does not send Telegram messages, join groups,
verify membership, or require bot credentials. Telegram membership is not a
condition for holding or transferring EARLY. The supplied URL is preserved
exactly; its availability and ownership are not verified by the contract.

No additional token mechanics were requested. Transfers have no fee or tax and
deliver the full amount. There is no owner, administrator, mint entry point,
burn entry point, pause, blacklist, seizure, transfer limit, upgrade, proxy, or
configuration step. No application contract is needed.

## Interface and behavior

The token uses the vendored OpenZeppelin Contracts v5.2.0 ERC-20 implementation.
It exposes `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `allowance`,
`transfer`, `approve`, and `transferFrom`, plus the `INITIAL_SUPPLY` and
`TELEGRAM_URL` constant getters.

- Successful transfers and approvals return `true`. Invalid actions revert with
  ERC-6093 custom errors, including insufficient balance, insufficient allowance,
  and invalid zero-address recipients or spenders.
- Zero-value transfers between valid addresses succeed and emit `Transfer`.
  Self-transfers preserve the balance but still require sufficient balance.
- `approve` replaces the caller's allowance. Approving zero revokes it. Finite
  allowances decrease on `transferFrom`, including transfers back to the owner.
  An allowance of `type(uint256).max` remains unchanged when spent.
- Approvals emit `Approval`; transfers emit `Transfer`. As in OpenZeppelin v5,
  `transferFrom` does not additionally emit `Approval` for allowance consumption.
- A reverted operation leaves balances, allowances, and supply unchanged.
  The deployer needs the same holder approval as any other spender.

## Build and check

Run from this repository's root with Foundry and Solidity **0.8.26** available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x1f53106fd55198b12509fc421db5f06b36a006cfe9d2f3daa5058fe4ba6f92d8 forge test
forge fmt --check
sha256sum --check dependencies.sha256
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer runs of 200,
and `bytecode_hash = "none"`. Fuzzing uses 512 cases per fuzz test; each invariant
uses 128 sequences of up to 64 calls. The seed above is supplied by the assignment;
tests do not read or modify environment variables themselves. Tests need no RPC,
fork, wallet, API key, FFI, or filesystem cheatcodes.

All library and test dependencies are included as ordinary source files in
`lib/`. No install step or network access is needed once the pinned compiler and
Foundry are installed. Versions, source URLs, licenses, and integrity hashes are
documented in [DEPENDENCIES.md](DEPENDENCIES.md).

The test suites cover:

- Exact metadata, supply, constructor mint event, and CREATE2 factory ownership
  of the initial balance.
- Transfers, approval replacement/revocation, delegated spending, infinite
  approvals, zero amounts, self-transfers, precise failures, and rollback.
- Rejection of mint, burn, administrative, and upgrade selectors; absence of
  prohibited runtime opcodes; the runtime size limit; rejected direct ETH sends.
- Fuzzed balances and allowances, and stateful sequences checked against a
  separate ledger for four participants, including failed spending attempts.
- Exact 10%/88%/2% launch distribution, distributor claims, and both directions
  of pool token transfers using local test participants.

The local launch fixture checks token movements only. It does not implement
Uniswap pool initialization, pricing, or swaps. Those are exercised by the
network's separate protected launch harness, whose factory, pool libraries,
manifest, and deployment environment are not part of this project.

## Deployment parameters and responsibilities

Deploy the creation bytecode for `src/EarlyToken.sol:EarlyToken` with no appended
constructor arguments and no ETH. The build artifact is
`out/EarlyToken.sol/EarlyToken.json`. The constructor makes no external calls
and has no dependency on an existing chain contract, owner address, registry,
router, or oracle. There are no linked external libraries.

The network's launch step handles the factory transaction and manifest. This
repository supplies the token source and does not include a launch manifest,
signing key, broadcast script, or deployment transaction. Only `EarlyToken`
is a production contract; all factories and handlers under `test/` are test
fixtures.

The token constructor allocates **100% to the deploying factory**. Subsequent
allocation belongs to the launch infrastructure: 10% to its distributor, 88%
to the pool, and 2% to the requester-designated remainder recipient. These
allocations are not encoded as token taxes or extra constructor mints. The
network's stated paired asset, pool fee, and opening valuation are pool and
manifest parameters, not token configuration.

## After launch

There are no owner-only setters, initialization calls, or ongoing onchain
operator tasks. The launch operator is responsible for verifying the deployed
source with these exact compiler settings, confirming metadata and supply,
executing the factory's distribution and liquidity operations, and publishing
the resulting chain and token address. This repository does not claim a live
deployment or an executed pool integration test.

The community operator maintains the Telegram destination and publishes the
verified token address there. The contract's Telegram URL cannot be changed;
continued control of the Telegram handle is an offchain responsibility.

Holders control their tokens and allowances. Approve only trusted spenders and
the amount needed; unlimited allowances expose the full balance to that spender.
When replacing an active allowance, revoking it first and confirming the
revocation helps manage the standard ERC-20 approval transaction-ordering risk.
The token has no administrative recovery function: tokens sent to the token
contract or to an inaccessible address cannot be recovered by an operator.
Direct ETH payments revert, and forcibly received ETH or other assets cannot
be rescued through this contract.

See [SECURITY.md](SECURITY.md) for the local review scope and remaining release
responsibilities.

