# Squeek (SQK)

A fixed-supply ERC-20 for Ethereum. The deployable contract is `src/Squeek.sol:Squeek`.

| Parameter | Value |
| --- | --- |
| Name | `Squeek` |
| Symbol | `SQK` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Constructor ETH value | `0` |
| Solidity compiler | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

`INITIAL_SUPPLY` is the named constant for the supply in smallest units. The constructor mints it
once and emits `Transfer(address(0), deployer, INITIAL_SUPPLY)`. It neither calls external contracts
nor needs any chain address, oracle, configuration, or initialization transaction.

## Behavior and assumptions

The brief specifies ordinary ERC-20 behavior, implemented by the vendored OpenZeppelin Contracts
v5.0.2 ERC-20. Each successful transfer moves its exact amount. There are no transfer taxes, burns,
rebases, limits, or recipient callbacks. A zero-amount transfer is valid and emits `Transfer`; a
self-transfer preserves the balance but still requires sufficient funds. Transfers to the zero
address revert. Successful `transfer`, `approve`, and `transferFrom` return `true`.

`approve` sets or replaces the caller's allowance for a nonzero spender and emits `Approval`.
`transferFrom` requires allowance even when the spender is also the sender; finite allowances
decrease by the amount spent. The maximum `uint256` allowance is unlimited and does not decrease.
OpenZeppelin v5 does not emit another `Approval` when `transferFrom` spends an allowance, so
integrations should read `allowance` instead of reconstructing it solely from those events.
Invalid addresses, insufficient balances, and insufficient allowances revert with the vendored
ERC-6093 custom errors, leaving balances and allowances unchanged.

There is no owner, privileged role, external mint or burn function, pause, blacklist, seizure,
upgrade, proxy, or permit function. The deployer has the same transfer rights as any holder.
The supply and metadata cannot be changed after deployment. No application contract is required.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xf92e0eca3f7366fa2915e2d34d7dcde731269d872b86a5a3005d58716d47c785 forge test
forge fmt --check
```

All imported sources and their licenses are ordinary files in `lib/`. No dependency installation,
RPC, external service, FFI, filesystem cheatcode permission, or environment configuration is needed
by the tests. The optional seed above controls the runner; tests never read or change environment
variables. Solidity 0.8.26 is supplied by the build environment rather than included as a binary.
Archive versions, source URLs, and archive SHA-256 digests are recorded in `DEPENDENCIES.json`.
Only the five required OpenZeppelin Solidity files are vendored, alongside its license; forge-std's
source and both licenses are vendored for tests.

Tests cover metadata, the constructor mint event, direct and CREATE2 factory deployment, complete
distribution, exact transfers, zero and self transfers, allowance replacement and revocation,
finite and unlimited spending, event emission, unauthorized spending, invalid addresses, and
rollback on failures. They also check that common mint/admin calls are unavailable and runtime
bytecode contains no `DELEGATECALL`, `CALLCODE`, or `SELFDESTRUCT`.

Six fuzz tests use 512 runs each. Two stateful invariant checks run over 128 sequences of 64 actions
over four holders, with unexpected reverts treated as failures. They check fixed supply, total
balance conservation, and balances/allowances against independent accounting after transfers,
approvals, and delegated transfers. Test actors and factory helpers exist only under `test/`.

Local validation with the supplied seed passed `forge build`, `forge test`, and `forge fmt --check`.
Foundry reported 30 passing tests (including the grouped invariant suite), no failures, and 8,192
invariant handler calls with no reverts. The built token has 1,752 bytes of runtime code and no
unresolved library links.

## Deployment and operational responsibilities

Deploy **Squeek's creation bytecode**, with no appended arguments, from the intended supply
recipient. The artifact is `out/Squeek.sol/Squeek.json`; `forge inspect src/Squeek.sol:Squeek bytecode`
prints its creation bytecode. No library linking or post-deployment initialization is needed.
Do not deploy through an intermediate helper unless that helper can distribute the tokens:
the helper, not its caller or `tx.origin`, would receive the entire supply.

For this assignment, the IdentityMD factory is the immediate deployer and receives all tokens.
The factory performs the separately managed launch distribution: 10% to the launch distributor,
80% to the pool, and the remaining 10% to the requester-designated recipient. These are factory
responsibilities; the token constructor does not allocate or reserve any of the supply. The
manifest and launch machinery select the real addresses and pool parameters. No `launch.json`
or deployed address is produced by this project.

After launch, the deployer should verify the deployed source and compiler settings, confirm the
metadata, total supply, and allocation balances, and publish the token address. There are no
owner settings or maintenance calls. Holders are responsible for custody and allowances; when
changing an existing nonzero allowance, setting it to zero and waiting for confirmation before
granting the replacement reduces the standard ERC-20 approval race. Unlimited allowances let
the spender use present and future balances until revoked.

There is no rescue mechanism for tokens sent to this token contract or to another address unable
to transfer them. Ordinary ETH transfers to the token revert because it has no payable receiver;
forcibly sent ETH cannot be recovered. These are consequences of an immutable token without
administrative powers.

## Review scope

The supplied security reference was reviewed against the implementation. Token operations make
no external calls and use no signatures, oracles, randomness, proxy storage, or linked libraries.
All post-deployment balance changes require the holder's call or allowance. Standard ERC-20
zero-value transfers and optional unlimited approvals are retained deliberately.

Local checks exercise the token's factory and distribution behavior; the factory test does not
deploy Uniswap or execute real swaps. The supplied protected integration tests require the
separate launch harness and manifest environment, which are not included in this repository.
No claim is made that those integration tests ran here. No RPC or live-chain transactions are
needed for this implementation. Slither and Mythril were not run. Local tests and source review
are not an independent security audit; the launch's independent review and on-chain verification
remain the release operators' responsibilities.
