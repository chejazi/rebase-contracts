// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./Rebase.sol";
import "./LPWrapper.sol";
import "./IUniswapLiquidity.sol";
import "./TickMath.sol";
import "./StakingApp.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "./INonfungiblePositionManager.sol";

interface IToken is IERC20Metadata {
    function image() external view returns (string memory);
}
interface ILegacyRebase {
    function getTokenStake(address) external view returns (uint);
}

contract RebaseReadAPI {
    LPWrapper private constant LP_WRAPPER = LPWrapper(0x80D25C6615BA03757619aB427c2D995D8B695162);
    ILegacyRebase private constant LEGACY_REBASE = ILegacyRebase(0xAf8955Ee7a816893F9Ebc4a74B010F079Df086e2);
    IUniswapV3Factory private constant UNISWAP_V3_FACTORY = IUniswapV3Factory(0x33128a8fC17869897dcE68Ed026d694621f6FDfD);
    INonfungiblePositionManager private constant UNISWAP_V3_POSITION_MANAGER = INonfungiblePositionManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
    IUniswapLiquidity private constant UNISWAP_LIQUIDITY = IUniswapLiquidity(0x234c57c010fD61017BFAf65DCfEF9b9860116a05);
    address private constant WRAPPED_ETH = 0x4200000000000000000000000000000000000006;
    Rebase private constant REBASE = Rebase(payable(0x89fA20b30a88811FBB044821FEC130793185c60B));

    uint160 private immutable sqrtInitialPriceLowerX96;
    uint160 private immutable sqrtInitialPriceUpperX96;

    constructor() {
        sqrtInitialPriceLowerX96 = TickMath.getSqrtRatioAtTick(-887200);
        sqrtInitialPriceUpperX96 = TickMath.getSqrtRatioAtTick(887200);
    }

    function getTokenMetadata(address[] memory tokens) public view returns (
        string[] memory,
        string[] memory,
        uint[] memory,
        uint[] memory,
        string[] memory
    ) {
        string[] memory names = new string[](tokens.length);
        string[] memory symbols = new string[](tokens.length);
        uint[] memory decimals = new uint[](tokens.length);
        uint[] memory supplies = new uint[](tokens.length);
        string[] memory images = new string[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            IToken token = IToken(tokens[i]);
            names[i] = token.name();
            symbols[i] = token.symbol();
            decimals[i] = token.decimals();
            supplies[i] = token.totalSupply();
            try token.image() returns (string memory image) {
                images[i] = image;
            } catch { }
        }
        return (names, symbols, decimals, supplies, images);
    }

    function getTokenStakes(address[] memory tokens) external view returns (uint[] memory) {
        uint[] memory stakes = new uint[](tokens.length);
        for (uint i = 0; i < tokens.length; i++) {
            stakes[i] = LEGACY_REBASE.getTokenStake(tokens[i]);
        }
        return stakes;
    }

    function getLPNFTs(address user) external view returns (
        uint[] memory,
        address[] memory,
        address[] memory
    ) {
        IERC721Enumerable minter = IERC721Enumerable(address(UNISWAP_V3_POSITION_MANAGER));
        uint numNFTs = minter.balanceOf(user);
        uint[] memory tokenIds = new uint[](numNFTs);
        address[] memory token0s = new address[](numNFTs);
        address[] memory token1s = new address[](numNFTs);
        for (uint i = 0; i < numNFTs; i++) {
            uint tokenId = minter.tokenOfOwnerByIndex(user, i);
            (,,address token0,address token1,,,,,,,,) = UNISWAP_V3_POSITION_MANAGER.positions(tokenId);
            tokenIds[i] = tokenId;
            token0s[i] = token0;
            token1s[i] = token1;
        }
        return (tokenIds, token0s, token1s);
    }

    function getRewardsPerSecond(address app, address stakingToken) public view returns (uint) {
        address[] memory pools = StakingApp(app).getTokenPools(stakingToken);
        uint rewardsPerSecond = 0;
        for (uint i = 0; i < pools.length; i++) {
            uint endTime = RewardPool(pools[i]).getEndTime();
            if (endTime > block.timestamp) {
                uint totalTime = endTime - RewardPool(pools[i]).getStartTime();
                rewardsPerSecond += RewardPool(pools[i]).getTotalReward() / totalTime;
            }
        }
        return rewardsPerSecond;
    }

    function getRewardsPerSecond(address app, address[] memory stakingTokens) external view returns (uint[] memory) {
        uint[] memory rewardsPerSecond = new uint[](stakingTokens.length);
        for (uint i = 0; i < stakingTokens.length; i++) {
            rewardsPerSecond[i] = getRewardsPerSecond(app, stakingTokens[i]);
        }
        return rewardsPerSecond;
    }

    function getWrappedLiquidity(address token0, address token1) external view returns (uint amount0, uint amount1) {
        address wrapper = address(LP_WRAPPER);
        IERC721Enumerable minter = IERC721Enumerable(address(UNISWAP_V3_POSITION_MANAGER));

        uint numNFTs = minter.balanceOf(wrapper);
        for (uint i = 0; i < numNFTs; i++) {
            uint tokenId = minter.tokenOfOwnerByIndex(wrapper, i);
            (,,address lpToken0,address lpToken1,,,,,,,,) = UNISWAP_V3_POSITION_MANAGER.positions(tokenId);
            if (lpToken0 == token0 && lpToken1 == token1) {
                (uint assets0, uint assets1) = getUnderlyingAssets(tokenId);
                amount0 += assets0;
                amount1 += assets1;
            } else if (lpToken0 == token1 && lpToken1 == token0) {
                (uint assets0, uint assets1) = getUnderlyingAssets(tokenId);
                amount0 += assets1;
                amount1 += assets0;
            }
        }
        return (amount0, amount1);
    }

    function getUnderlyingAssets(uint256 tokenId) public view returns (uint256 amount0, uint256 amount1) {
        // Step 1: Fetch position details
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
        ) = UNISWAP_V3_POSITION_MANAGER.positions(tokenId);

        // Step 2: Get the pool address from token0, token1, and fee
        address pool = UNISWAP_V3_FACTORY.getPool(token0, token1, fee);

        // Step 3: Fetch current pool state
        (uint160 sqrtPriceX96, , , , , ,) = IUniswapV3Pool(pool).slot0();

        // Step 4: Calculate token amounts
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        (amount0, amount1) = UNISWAP_LIQUIDITY.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceLowerX96,
            sqrtPriceUpperX96,
            liquidity
        );

        return (amount0, amount1);
    }

    // StakingApp -> RewardToken (+WRAPPED_ETH) -> LP Token -> RewardPool -> (RewardPerSecond, token0Amount, token1Amount)
    function getTokenLpRewards(address stakingApp) public view returns (uint rewardsPerSecond, address rewardToken, uint amountToken, uint amountWeth) {
        if (stakingApp == 0x9Db748Ef3d6c6d7DA2475c48d6d09a7D75251F81) {
            // Jobs App didn't have `getRewardToken`
            rewardToken = 0xd21111c0e32df451eb61A23478B438e3d71064CB; // $JOBS
        } else {
            rewardToken = StakingApp(stakingApp).getRewardToken();
        }
        address lpToken;
        try LP_WRAPPER.getLPToken(rewardToken, WRAPPED_ETH, 10000) returns (address lpTokenRes) {
            lpToken = lpTokenRes;
        } catch {
            return (rewardsPerSecond, rewardToken, amountToken, amountWeth);
        }

        rewardsPerSecond = getRewardsPerSecond(stakingApp, lpToken);

        uint liquidity = REBASE.getAppStake(stakingApp, lpToken);
        address pool = UNISWAP_V3_FACTORY.getPool(rewardToken, WRAPPED_ETH, 10000);
        (uint160 sqrtPriceX96, , , , , ,) = IUniswapV3Pool(pool).slot0();
        (amountWeth, amountToken) = UNISWAP_LIQUIDITY.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtInitialPriceLowerX96,
            sqrtInitialPriceUpperX96,
            uint128(liquidity)
        );

        if (WRAPPED_ETH > rewardToken) {
            (amountToken, amountWeth) = (amountWeth, amountToken);
        }
    }

    function getTokenLpRewards(address[] memory stakingApps) external view returns (uint[] memory, address[] memory, uint[] memory, uint[] memory) {
        uint[] memory rewardsPerSecond = new uint[](stakingApps.length);
        address[] memory rewardTokens = new address[](stakingApps.length);
        uint[] memory amountsToken = new uint[](stakingApps.length);
        uint[] memory amountsWeth = new uint[](stakingApps.length);
        for (uint i = 0; i < stakingApps.length; i++) {
            (rewardsPerSecond[i], rewardTokens[i], amountsToken[i], amountsWeth[i]) = getTokenLpRewards(stakingApps[i]);
        }
        return (rewardsPerSecond, rewardTokens, amountsToken, amountsWeth);
    }

}
