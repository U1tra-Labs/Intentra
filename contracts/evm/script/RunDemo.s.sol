// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {IntentChannel} from "../src/channels/IntentChannel.sol";
import {ExecutionCommitter} from "../src/channels/ExecutionCommitter.sol";
import {YellowClearingHook} from "../src/hooks/YellowClearingHook.sol";
import {UniswapV4Adapter} from "../src/amm/UniswapV4Adapter.sol";
import {LiquidityManager} from "../src/uniswap/LiquidityManager.sol";
import {IIntent} from "../src/interfaces/IIntent.sol";
import {DemoToken} from "../src/tokens/DemoToken.sol";
import {MakerFill} from "../src/rfq/MakerFill.sol";

contract RunDemo is Script {
  address internal constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
  uint24 internal constant FEE = 3000;
  int24 internal constant TICK_SPACING = 60;
  int24 internal constant TICK_LOWER = -600;
  int24 internal constant TICK_UPPER = 600;

  uint256 internal constant AMOUNT_IN = 1 ether;
  uint256 internal constant MIN_OUT = 1;
  uint256 internal constant QUOTE_OUT = 2 ether;
  uint256 internal constant MAKER_INVENTORY = 10_000 ether;
  uint256 internal constant CROSS_CHAIN_ID = 42161;

  function run() external {
    uint256 traderKey = vm.envUint("PRIVATE_KEY");
    uint256 makerKey = vm.envUint("MAKER_PRIVATE_KEY");
    address trader = vm.addr(traderKey);
    address maker = vm.addr(makerKey);

    vm.startBroadcast(traderKey);

    DemoToken token0 = new DemoToken("Demo Token A", "TKA", trader, 1_000_000 ether);
    DemoToken token1 = new DemoToken("Demo Token B", "TKB", trader, 1_000_000 ether);

    PoolManager poolManager = new PoolManager(trader);
    IntentChannel channel = new IntentChannel(address(0));
    ExecutionCommitter committer = new ExecutionCommitter(channel, poolManager);
    channel.setCommitter(address(committer));

    uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
    bytes memory hookArgs = abi.encode(poolManager, channel, address(committer));
    (address hookAddress, bytes32 salt) =
      HookMiner.find(CREATE2_DEPLOYER, flags, type(YellowClearingHook).creationCode, hookArgs);
    YellowClearingHook hook = new YellowClearingHook{salt: salt}(poolManager, channel, address(committer));
    require(address(hook) == hookAddress, "HOOK_ADDR_MISMATCH");
    UniswapV4Adapter adapter = new UniswapV4Adapter(address(poolManager), address(hook), FEE, TICK_SPACING);
    LiquidityManager liquidityManager = new LiquidityManager(poolManager);

    console2.log("IntentChannel:", address(channel));
    console2.log(string.concat("yellow-watch --rpc $RPC_URL --channel ", vm.toString(address(channel))));

    (PoolKey memory key, bool zeroForOne) = _buildPoolKey(token0, token1, hook);
    uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
    liquidityManager.initializePool(key, sqrtPriceX96);

    token0.approve(address(liquidityManager), type(uint256).max);
    token1.approve(address(liquidityManager), type(uint256).max);
    token0.approve(address(channel), type(uint256).max);
    token1.approve(address(channel), type(uint256).max);

    ModifyLiquidityParams memory params = ModifyLiquidityParams({
      tickLower: _alignedTick(TICK_LOWER),
      tickUpper: _alignedTick(TICK_UPPER),
      liquidityDelta: int256(1_000 ether),
      salt: bytes32(0)
    });

    liquidityManager.modifyLiquidity(key, params, "", trader);

    DemoToken inputToken = zeroForOne ? token0 : token1;
    DemoToken outputToken = zeroForOne ? token1 : token0;

    MakerFill makerFillFunded = new MakerFill(maker);
    MakerFill makerFillExpired = new MakerFill(maker);

    require(outputToken.transfer(address(makerFillFunded), MAKER_INVENTORY), "MAKER_FUND_FAILED");
    require(outputToken.transfer(address(makerFillExpired), MAKER_INVENTORY), "MAKER_FUND_FAILED");

    console2.log("Scenario A: RFQ success (maker funded)");
    _runScenario(ScenarioParams({
      channel: channel,
      committer: committer,
      adapter: adapter,
      makerFill: makerFillFunded,
      traderKey: traderKey,
      makerKey: makerKey,
      trader: trader,
      inputToken: address(inputToken),
      outputToken: address(outputToken),
      amountIn: AMOUNT_IN,
      minOut: MIN_OUT,
      quoteOut: QUOTE_OUT,
      expiry: block.timestamp + 120,
      nonce: 1
    }));

    console2.log("Scenario B: RFQ fails (quote expired) -> v4 fallback");
    _runScenario(ScenarioParams({
      channel: channel,
      committer: committer,
      adapter: adapter,
      makerFill: makerFillExpired,
      traderKey: traderKey,
      makerKey: makerKey,
      trader: trader,
      inputToken: address(inputToken),
      outputToken: address(outputToken),
      amountIn: AMOUNT_IN,
      minOut: MIN_OUT,
      quoteOut: QUOTE_OUT,
      expiry: block.timestamp - 1,
      nonce: 2
    }));

    console2.log("Scenario C: Cross-chain intent (plan only, no execute)");
    _printCrossChainPlan(CrossChainParams({
      channel: channel,
      trader: trader,
      inputToken: address(inputToken),
      outputToken: address(outputToken),
      amountIn: AMOUNT_IN,
      minOut: MIN_OUT,
      nonce: 3
    }));

    vm.stopBroadcast();
  }

  struct ScenarioParams {
    IntentChannel channel;
    ExecutionCommitter committer;
    UniswapV4Adapter adapter;
    MakerFill makerFill;
    uint256 traderKey;
    uint256 makerKey;
    address trader;
    address inputToken;
    address outputToken;
    uint256 amountIn;
    uint256 minOut;
    uint256 quoteOut;
    uint256 expiry;
    uint256 nonce;
  }

  struct CrossChainParams {
    IntentChannel channel;
    address trader;
    address inputToken;
    address outputToken;
    uint256 amountIn;
    uint256 minOut;
    uint256 nonce;
  }

  function _runScenario(ScenarioParams memory p) internal {
    console2.log("========================================");
    console2.log("Scenario");
    console2.log("makerFill:", address(p.makerFill));
    console2.log("amountIn:", p.amountIn);
    console2.log("minOut:", p.minOut);
    console2.log("quoteOut:", p.quoteOut);
    console2.log("expiry:", p.expiry);

    IIntent.TradingIntent memory intent = IIntent.TradingIntent({
      trader: p.trader,
      inputToken: p.inputToken,
      outputToken: p.outputToken,
      amountIn: p.amountIn,
      minOut: p.minOut,
      deadline: block.timestamp + 1 hours,
      nonce: p.nonce,
      sourceChainId: block.chainid,
      destChainId: block.chainid
    });

    bytes32 intentHash = p.channel.hashIntent(intent);
    bytes memory traderSig = _sign(p.traderKey, intentHash);

    bytes memory fallbackData = p.adapter.buildFallbackData(
      intentHash,
      intent.inputToken,
      intent.outputToken,
      intent.amountIn,
      intent.minOut,
      intent.deadline
    );

    MakerFill.Quote memory quote = MakerFill.Quote({
      inputToken: intent.inputToken,
      outputToken: intent.outputToken,
      amountIn: intent.amountIn,
      amountOut: p.quoteOut,
      expiry: p.expiry
    });

    bytes32 quoteDigest = p.makerFill.quoteDigest(intentHash, quote);
    bytes memory makerSig = _sign(p.makerKey, quoteDigest);

    IIntent.RfqStep memory rfq = IIntent.RfqStep({
      makerFill: address(p.makerFill),
      maker: vm.addr(p.makerKey),
      amountOut: p.quoteOut,
      expiry: p.expiry,
      makerSig: makerSig
    });

    IIntent.AmmStep memory amm = IIntent.AmmStep({
      poolManager: address(p.adapter.poolManager()),
      adapter: address(p.adapter),
      fallbackData: fallbackData
    });

    IIntent.LifiStep memory lifi = IIntent.LifiStep({
      lifiDiamond: address(0),
      approvalAddress: address(0),
      callData: "",
      value: 0,
      minAmountOut: 0,
      toChainId: 0
    });

    IIntent.ExecutionPlan memory plan = IIntent.ExecutionPlan({
      intentHash: intentHash,
      primary: rfq,
      amm: amm,
      lifi: lifi,
      deadline: intent.deadline
    });

    bytes32 planHash = keccak256(abi.encode(plan));
    console2.log("intentHash");
    console2.logBytes32(intentHash);
    console2.log("planHash");
    console2.logBytes32(planHash);

    uint256 makerInputBefore = DemoToken(p.inputToken).balanceOf(address(p.makerFill));
    uint256 traderOutBefore = DemoToken(p.outputToken).balanceOf(p.trader);

    p.channel.commitIntent(intent, traderSig, plan);
    p.committer.execute(plan);

    uint256 makerInputAfter = DemoToken(p.inputToken).balanceOf(address(p.makerFill));
    uint256 traderOutAfter = DemoToken(p.outputToken).balanceOf(p.trader);

    bool usedFallback = makerInputAfter == makerInputBefore;
    uint256 amountOut = traderOutAfter - traderOutBefore;

    console2.log(usedFallback ? "Result: FALLBACK (v4)" : "Result: RFQ SUCCESS");
    console2.log("outputReceived:", amountOut);
  }

  function _printCrossChainPlan(CrossChainParams memory p) internal view {
    IIntent.TradingIntent memory intent = IIntent.TradingIntent({
      trader: p.trader,
      inputToken: p.inputToken,
      outputToken: p.outputToken,
      amountIn: p.amountIn,
      minOut: p.minOut,
      deadline: block.timestamp + 1 hours,
      nonce: p.nonce,
      sourceChainId: block.chainid,
      destChainId: CROSS_CHAIN_ID
    });

    bytes32 intentHash = p.channel.hashIntent(intent);

    IIntent.RfqStep memory rfq = IIntent.RfqStep({
      makerFill: address(0),
      maker: address(0),
      amountOut: 0,
      expiry: 0,
      makerSig: ""
    });

    IIntent.AmmStep memory amm = IIntent.AmmStep({
      poolManager: address(0),
      adapter: address(0),
      fallbackData: ""
    });

    IIntent.LifiStep memory lifi = IIntent.LifiStep({
      lifiDiamond: address(0x1111111111111111111111111111111111111111),
      approvalAddress: address(0x2222222222222222222222222222222222222222),
      callData: hex"1234",
      value: 0,
      minAmountOut: p.minOut,
      toChainId: CROSS_CHAIN_ID
    });

    IIntent.ExecutionPlan memory plan = IIntent.ExecutionPlan({
      intentHash: intentHash,
      primary: rfq,
      amm: amm,
      lifi: lifi,
      deadline: intent.deadline
    });

    bytes32 planHash = keccak256(abi.encode(plan));
    console2.log("intentHash");
    console2.logBytes32(intentHash);
    console2.log("planHash");
    console2.logBytes32(planHash);
    console2.log("lifiDiamond:", lifi.lifiDiamond);
    console2.log("toChainId:", lifi.toChainId);
  }

  function _buildPoolKey(
    DemoToken token0,
    DemoToken token1,
    YellowClearingHook hook
  ) internal pure returns (PoolKey memory key, bool zeroForOne) {
    Currency currency0 = Currency.wrap(address(token0));
    Currency currency1 = Currency.wrap(address(token1));
    zeroForOne = address(token0) < address(token1);

    key = PoolKey({
      currency0: zeroForOne ? currency0 : currency1,
      currency1: zeroForOne ? currency1 : currency0,
      fee: FEE,
      tickSpacing: TICK_SPACING,
      hooks: IHooks(address(hook))
    });
  }

  function _alignedTick(int24 tick) internal pure returns (int24) {
    int24 rounded = tick / TICK_SPACING * TICK_SPACING;
    return rounded;
  }

  function _sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory sig) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    sig = abi.encodePacked(r, s, v);
  }
}
