// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";

import {IntentChannel} from "../src/channels/IntentChannel.sol";
import {ExecutionCommitter} from "../src/channels/ExecutionCommitter.sol";
import {IIntent} from "../src/interfaces/IIntent.sol";
import {DemoToken} from "../src/tokens/DemoToken.sol";
import {MakerFill} from "../src/rfq/MakerFill.sol";
import {CommitmentTypes} from "../src/libraries/CommitmentTypes.sol";

contract RunDemoPrivate is Script {
  uint256 internal constant AMOUNT_IN = 1 ether;
  uint256 internal constant MIN_OUT = 1;
  uint256 internal constant QUOTE_OUT = 2 ether;
  uint256 internal constant MAKER_INVENTORY = 10_000 ether;

  uint256 internal constant BATCH_WINDOW = 300;
  uint256 internal constant MIN_DELAY = 30;

  function run() external {
    uint256 traderKey = vm.envUint("PRIVATE_KEY");
    uint256 makerKey = vm.envUint("MAKER_PRIVATE_KEY");
    address trader = vm.addr(traderKey);
    address maker = vm.addr(makerKey);

    vm.startBroadcast(traderKey);

    DemoToken inputToken = new DemoToken("Demo Token A", "TKA", trader, 1_000_000 ether);
    DemoToken outputToken = new DemoToken("Demo Token B", "TKB", trader, 1_000_000 ether);

    PoolManager poolManager = new PoolManager(trader);
    IntentChannel channel = new IntentChannel(address(0));
    ExecutionCommitter committer = new ExecutionCommitter(channel, poolManager);
    channel.setCommitter(address(committer));
    channel.setBatchParams(BATCH_WINDOW, MIN_DELAY);

    inputToken.approve(address(channel), type(uint256).max);
    outputToken.approve(address(channel), type(uint256).max);

    MakerFill makerFill = new MakerFill(maker);
    require(outputToken.transfer(address(makerFill), MAKER_INVENTORY), "MAKER_FUND_FAILED");

    IIntent.TradingIntent memory intent = IIntent.TradingIntent({
      trader: trader,
      inputToken: address(inputToken),
      outputToken: address(outputToken),
      amountIn: AMOUNT_IN,
      minOut: MIN_OUT,
      deadline: block.timestamp + 1 hours,
      nonce: 1,
      sourceChainId: block.chainid,
      destChainId: block.chainid
    });

    bytes32 intentHash = channel.hashIntent(intent);
    bytes memory traderSig = _sign(traderKey, intentHash);

    MakerFill.Quote memory quote = MakerFill.Quote({
      inputToken: intent.inputToken,
      outputToken: intent.outputToken,
      amountIn: intent.amountIn,
      amountOut: QUOTE_OUT,
      expiry: block.timestamp + 120
    });

    bytes32 quoteDigest = makerFill.quoteDigest(intentHash, quote);
    bytes memory makerSig = _sign(makerKey, quoteDigest);

    IIntent.RfqStep memory rfq = IIntent.RfqStep({
      makerFill: address(makerFill),
      maker: maker,
      amountOut: QUOTE_OUT,
      expiry: quote.expiry,
      makerSig: makerSig
    });

    IIntent.AmmStep memory amm = IIntent.AmmStep({
      poolManager: address(0),
      adapter: address(0),
      fallbackData: ""
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
    uint256 earliest = block.timestamp + MIN_DELAY;
    uint256 notBefore = _alignToBatchWindow(earliest);
    bytes32 salt = keccak256(abi.encode("secret", block.timestamp));
    bytes32 commitment = CommitmentTypes.hash(intentHash, planHash, notBefore, salt);

    channel.commitIntentPrivate(commitment, intent.inputToken, intent.amountIn, intent.deadline, notBefore, trader, "");
    console2.log("Committed privately. notBefore:", notBefore);

    if (block.timestamp < notBefore) {
      vm.warp(notBefore + 1);
    }

    committer.executeWithReveal(commitment, intent, traderSig, plan, salt);
    console2.log("Revealed + executed in batch window");

    vm.stopBroadcast();
  }

  function _alignToBatchWindow(uint256 timestamp) internal pure returns (uint256) {
    if (BATCH_WINDOW == 0) return timestamp;
    uint256 rounded = timestamp - (timestamp % BATCH_WINDOW);
    if (timestamp % BATCH_WINDOW == 0) return timestamp;
    return rounded + BATCH_WINDOW;
  }

  function _sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory sig) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    sig = abi.encodePacked(r, s, v);
  }
}
