## Rebase Spec

Rebase is a staking protocol deployed on Base. Rebase gives holders of ERC-20 assets a safe, new way to put them to work across an emerging set of new apps and protocols powered by staking and restaking.

### Staking and Restaking

Rebase enables you to stake your assets once (in Rebase), then _restake_ them across a number of different apps and protocols. For instance, builders can build an app that issues a new token to users staking $DEGEN over time. The app can use the Rebase protocol for staking so that users can trust their assets are staked safely.

Neither the Rebase team nor the restaking apps ever control your funds: _only you_ can withdraw staked assets from Rebase, and you can do so _at any time_.

Each token has corresponding reToken ERC-20 automatically deployed by Rebase. When you stake an ERC-20s on Rebase, you receive a corresponding amount that token's _reTokens_. In order to unstake, stakers need to hold the corresponding amount of reTokens in their wallet, which get subsequently burned.

Users can stake their tokens, obtain reTokens, and do various actions with those reTokens. Some use cases include:
- Trading reTokens (liquidity)
- Storing reTokens in a cold wallet (security)
- Locking reTokens for additional functionality (eg $DEGEN tipping)

### Write APIs

There are three main write methods when interacting with Rebase:

___

**`stake(address token, uint quantity, address app)`**

Stake `quantity` units of `token` into the Rebase contract.
Restake those same tokens into `app`. Reverts if restaking fails.
Transfer approval must be granted to the Rebase contract prior to calling this function.
User received `quantity` units of reTokens, representing their staked assets.

___

**`stakeETH(address app)`**

Same implementation as `stake`; the contract converts sent ETH to WETH first.

___

**`unstake(address token, uint quantity, app)`**

Unstakes `quantity` of token `token` and transfers them back to the user.
Unrestakes those same tokens from `app`. Proceeds even if unrestaking fails.
The user *must* have `quantity` corresponding reTokens in their wallet.
Remove the token from the user's app-stake-list if entire stake is unstaked.
Remove the app from the user's app-list if no tokens are staked in app.


### Read APIs

**`getApps(address user)`**

Returns an `address[]` array of apps the `user` currently has tokens staked in on Rebase.

**`getApp(address user, uint index)`**

Returns the `address` of the `index`th app that the `user` currently has tokens staked in on Rebase.

**`getNumApps(address user)`**

Returns a `uint` of the total number of different apps the `user` has staked tokens in on Rebase.

**`getStake(address user, address app, address token)`**

Returns a `uint` quantity of `token` the `user` has staked in `app` on Rebase.

**`getTokensAndStakes(address user, address app)`**

Returns an `(address[], uint[])` pair of tokens and stakes that the `user` has staked in `app` on Rebase.

**`getTokenAndStake(address user, address app, uint index)`**

Returns a pair `(address, uint)` of the `index`th  token and stake that the `user` has staked in `app` on Rebase.

**`getNumTokenStakes(address user, address app)`**

Returns a `uint` of the total number of different tokens the `user` has staked in `app` on Rebase.

**`getTokenReToken(address token)`**

Returns the reToken `address` for `token`.

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
