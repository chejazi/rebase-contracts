## Rebase Spec

Rebase is a restaking protocol currently [deployed on Base](https://basescan.org/address/0xAf8955Ee7a816893F9Ebc4a74B010F079Df086e2). Rebase gives holders of ERC-20 assets a new way to put them to work across an emerging set of new apps and protocols powered by restaking.

### Staking and Restaking

Rebase enables you to stake your assets once (in Rebase), then _restake_ them across a number of different apps and protocols. Restaking enables an app to know you have assets staked and automatically be subscribed to any changes in your balance. This can be useful for, say, issuing a new token based on the user having staked an asset over time.

Neither the Rebase team nor the restaking apps ever control your funds: _only you_ can withdraw staked assets from Rebase, and you can do so _at any time_.

Each token a corresponding reToken ERC-20. When you stake ERC-20s in Rebase, you get a corresponding amount of _reTokens_. For example $DEGEN has [$reDEGEN](https://basescan.org/token/0x5f09c2fa5c4e11fa88964a549dfad2b6fd0c50ab]) which represents $DEGEN staked in Rebase. In order to unstake, stakers need to hold the corresponding amount of $reDEGEN in their wallet.

Users can stake their tokens, obtain reTokens, and do various actions with those reTokens. Some use cases include:
- Create liquidity around staked assets (liquid staking)
- Storing reTokens in a cold wallet while retaining the ability to restake
- Locking reTokens in a contract while retaining the ability to restake

### Write APIs

There are five main write methods when interacting with Rebase:

___

**`stake(address token, uint quantity, address[] memory apps)`**

Stake `quantity` units of `token` into the Rebase contract.
Transfer approval must be granted to the Rebase contract prior to calling this function.
Call reverts if one or more new apps in `apps` fails to restake.
Existing apps that fail to restake are removed from the user's app list.
User received a `quantity` units of reTokens, representing their staked asset in the contract. Eacn `token` has a corresponding ERC-20 reToken.

___

**`stakeETH(address[] memory apps)`**

Same implementation as `stake()`; the contract converts sent ETH to WETH first.

___

**`unstake(address token, uint quantity)`**

Unstakes `quantity` of token `token` and transfers them back to the user.
The user *must* have `quantity` corresponding reTokens in their wallet.
Unstaking still occurs even if `unrestaking` fails.
If `quantity` unstaked is their entire staked amount, the apps are removed as well.

___

**`restake(address[] memory apps, address[] memory tokens)`**

Restakes the `nth` token in `tokens` into the nth app in `apps`.
Restaking is symbolic; no tokens are actually transferred to `apps`.
Amount user has staked of each token must be > 0 or call reverts.
Restaking call to third party contracts must succeed or call reverts.

___

**`unrestake(address[] memory apps, address[] memory tokens)`**

Unrestakes the `nth` token in `tokens` from the nth app in `apps`.
Unrestaking is symbolic; no tokens are actually removed from `apps`.
Amount user has staked of each token must be > 0 or call reverts.
Call succeeds even if unrestaking call to individual apps reverts.

### Read APIs

**`function getUserStakedTokens(address user)`**

Returns an `address[]` array of tokens the user currently has staked in Rebase.

**`function getUserTokenStake(address user, address token)`**

Returns a `uint` corresponding to the amount of a `token` the `user` has staked in Rebase.

**`function getUserTokenApps(address user, address token)`**

Returns an `address[]` array of apps the user has restaked in for `token`.

**`function getTokenReToken(address token)`**

Returns the reToken `address` for `token`.

**`function getTokenStake(address token)`**

Returns a `uint` representing the total amount of `token` staked in Rebase.

**`function getReTokens()`**

Returns an `address[]` array of all tokens staked in Rebase.

**`function getReTokensLength()`**

Returns an `uint` of the total number of different tokens staked in Rebase.

**`function getReTokensAt(uint index)`**

Returns an `address` corresponding to the `index`th token in the set of tokens staked in Rebase.

## Tests

Tests for the Rebase contract are written using Foundry.

### Setup

```
forge install foundry-rs/forge-std
forge install OpenZeppelin/openzeppelin-foundry-upgrades
forge install OpenZeppelin/openzeppelin-contracts@v4.9.6
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.9.6
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
