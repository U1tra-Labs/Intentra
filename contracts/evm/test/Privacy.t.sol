// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IntentChannel} from "../src/channels/IntentChannel.sol";
import {IIntent} from "../src/interfaces/IIntent.sol";
import {DemoToken} from "../src/tokens/DemoToken.sol";
import {CommitmentTypes} from "../src/libraries/CommitmentTypes.sol";

contract PrivacyTest is Test {
  IntentChannel internal channel;
  DemoToken internal inputToken;
  DemoToken internal outputToken;

  uint256 internal traderKey;
  address internal trader;
  address internal relayer;

  function setUp() public {
    traderKey = 0xA11CE;
    trader = vm.addr(traderKey);
    relayer = address(0xBEEF);

    channel = new IntentChannel(address(this));
    channel.setBatchParams(60, 30);

    inputToken = new DemoToken("Input", "IN", trader, 1_000_000 ether);
    outputToken = new DemoToken("Output", "OUT", trader, 1_000_000 ether);

    vm.prank(trader);
    inputToken.approve(address(channel), type(uint256).max);
  }

  function test_CommitRevealFlow() public {
    (IIntent.TradingIntent memory intent, bytes32 intentHash) = _buildIntent();
    IIntent.ExecutionPlan memory plan = _buildPlan(intentHash, intent.deadline);
    bytes32 planHash = keccak256(abi.encode(plan));

    uint256 notBefore = _aligned(block.timestamp + channel.minDelay());
    bytes32 salt = bytes32(uint256(1));
    bytes32 commitment = CommitmentTypes.hash(intentHash, planHash, notBefore, salt);

    vm.prank(trader);
    channel.commitIntentPrivate(
      commitment,
      intent.inputToken,
      intent.amountIn,
      intent.deadline,
      notBefore,
      trader,
      ""
    );

    vm.warp(notBefore);
    bytes memory traderSig = _sign(traderKey, intentHash);
    channel.revealIntent(commitment, intent, traderSig, plan, salt);

    assertEq(uint256(channel.status(intentHash)), uint256(IntentChannel.IntentStatus.Committed));
    assertEq(channel.planHashOf(intentHash), planHash);
    assertEq(channel.notBeforeOf(intentHash), notBefore);
  }

  function test_RejectEarlyReveal() public {
    (IIntent.TradingIntent memory intent, bytes32 intentHash) = _buildIntent();
    IIntent.ExecutionPlan memory plan = _buildPlan(intentHash, intent.deadline);
    bytes32 planHash = keccak256(abi.encode(plan));

    uint256 notBefore = _aligned(block.timestamp + channel.minDelay());
    bytes32 salt = bytes32(uint256(2));
    bytes32 commitment = CommitmentTypes.hash(intentHash, planHash, notBefore, salt);

    vm.prank(trader);
    channel.commitIntentPrivate(
      commitment,
      intent.inputToken,
      intent.amountIn,
      intent.deadline,
      notBefore,
      trader,
      ""
    );

    bytes memory traderSig = _sign(traderKey, intentHash);
    vm.expectRevert("BATCH_NOT_READY");
    channel.revealIntent(commitment, intent, traderSig, plan, salt);
  }

  function test_RejectInvalidSalt() public {
    (IIntent.TradingIntent memory intent, bytes32 intentHash) = _buildIntent();
    IIntent.ExecutionPlan memory plan = _buildPlan(intentHash, intent.deadline);
    bytes32 planHash = keccak256(abi.encode(plan));

    uint256 notBefore = _aligned(block.timestamp + channel.minDelay());
    bytes32 salt = bytes32(uint256(3));
    bytes32 commitment = CommitmentTypes.hash(intentHash, planHash, notBefore, salt);

    vm.prank(trader);
    channel.commitIntentPrivate(
      commitment,
      intent.inputToken,
      intent.amountIn,
      intent.deadline,
      notBefore,
      trader,
      ""
    );

    vm.warp(notBefore);
    bytes memory traderSig = _sign(traderKey, intentHash);
    vm.expectRevert("BAD_COMMITMENT");
    channel.revealIntent(commitment, intent, traderSig, plan, bytes32(uint256(4)));
  }

  function test_BatchAlignment() public {
    (IIntent.TradingIntent memory intent, bytes32 intentHash) = _buildIntent();
    IIntent.ExecutionPlan memory plan = _buildPlan(intentHash, intent.deadline);
    bytes32 planHash = keccak256(abi.encode(plan));

    uint256 misaligned = block.timestamp + channel.minDelay() + 1;
    bytes32 commitment = CommitmentTypes.hash(intentHash, planHash, misaligned, bytes32(uint256(5)));

    vm.prank(trader);
    vm.expectRevert("NOT_ALIGNED");
    channel.commitIntentPrivate(
      commitment,
      intent.inputToken,
      intent.amountIn,
      intent.deadline,
      misaligned,
      trader,
      ""
    );
  }

  function test_RefundUnrevealedAfterDeadline() public {
    (IIntent.TradingIntent memory intent, bytes32 intentHash) = _buildIntent();
    IIntent.ExecutionPlan memory plan = _buildPlan(intentHash, intent.deadline);
    bytes32 planHash = keccak256(abi.encode(plan));

    uint256 notBefore = _aligned(block.timestamp + channel.minDelay());
    bytes32 salt = bytes32(uint256(6));
    bytes32 commitment = CommitmentTypes.hash(intentHash, planHash, notBefore, salt);

    uint256 balanceBefore = inputToken.balanceOf(trader);

    vm.prank(trader);
    channel.commitIntentPrivate(
      commitment,
      intent.inputToken,
      intent.amountIn,
      intent.deadline,
      notBefore,
      trader,
      ""
    );

    vm.warp(intent.deadline + 1);
    channel.refundCommitment(commitment);

    uint256 balanceAfter = inputToken.balanceOf(trader);
    assertEq(balanceAfter, balanceBefore);
  }

  function test_RelayerCommitWithSignature() public {
    (IIntent.TradingIntent memory intent, bytes32 intentHash) = _buildIntent();
    IIntent.ExecutionPlan memory plan = _buildPlan(intentHash, intent.deadline);
    bytes32 planHash = keccak256(abi.encode(plan));

    uint256 notBefore = _aligned(block.timestamp + channel.minDelay());
    bytes32 salt = bytes32(uint256(7));
    bytes32 commitment = CommitmentTypes.hash(intentHash, planHash, notBefore, salt);

    bytes32 digest = channel.hashCommitmentAuthorization(
      commitment,
      trader,
      intent.inputToken,
      intent.amountIn,
      intent.deadline,
      notBefore
    );
    bytes memory sig = _sign(traderKey, digest);

    vm.prank(relayer);
    channel.commitIntentPrivate(
      commitment,
      intent.inputToken,
      intent.amountIn,
      intent.deadline,
      notBefore,
      trader,
      sig
    );

    (
      address storedTrader,
      address storedToken,
      uint256 storedAmount,
      ,
      uint256 storedNotBefore,
      IntentChannel.CommitmentStatus status
    ) = channel.commitments(commitment);
    assertEq(storedTrader, trader);
    assertEq(storedToken, intent.inputToken);
    assertEq(storedAmount, intent.amountIn);
    assertEq(storedNotBefore, notBefore);
    assertEq(uint256(status), uint256(IntentChannel.CommitmentStatus.Pending));
  }

  function _buildIntent() internal view returns (IIntent.TradingIntent memory intent, bytes32 intentHash) {
    intent = IIntent.TradingIntent({
      trader: trader,
      inputToken: address(inputToken),
      outputToken: address(outputToken),
      amountIn: 1 ether,
      minOut: 1,
      deadline: block.timestamp + 1 hours,
      nonce: 1,
      sourceChainId: block.chainid,
      destChainId: block.chainid
    });
    intentHash = channel.hashIntent(intent);
  }

  function _buildPlan(bytes32 intentHash, uint256 deadline) internal pure returns (IIntent.ExecutionPlan memory plan) {
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
      lifiDiamond: address(0),
      approvalAddress: address(0),
      callData: "",
      value: 0,
      minAmountOut: 0,
      toChainId: 0
    });
    plan = IIntent.ExecutionPlan({
      intentHash: intentHash,
      primary: rfq,
      amm: amm,
      lifi: lifi,
      deadline: deadline
    });
  }

  function _aligned(uint256 timestamp) internal view returns (uint256) {
    uint256 batchWindow = channel.batchWindow();
    if (batchWindow == 0) return timestamp;
    uint256 rounded = timestamp - (timestamp % batchWindow);
    if (timestamp % batchWindow == 0) return timestamp;
    return rounded + batchWindow;
  }

  function _sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory sig) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    sig = abi.encodePacked(r, s, v);
  }
}
