// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIntent} from "../interfaces/IIntent.sol";
import {ECDSA} from "../utils/ECDSA.sol";
import {SafeTransferLib, IERC20} from "../utils/SafeTransferLib.sol";

contract IntentChannel {
  using SafeTransferLib for IERC20;

  bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 private constant _INTENT_TYPEHASH =
    keccak256(
      "TradingIntent(address trader,address inputToken,address outputToken,uint256 amountIn,uint256 minOut,uint256 deadline,uint256 nonce,uint256 sourceChainId,uint256 destChainId)"
    );

  string public constant NAME = "IntentChannel";
  string public constant VERSION = "1";

  address public owner;
  address public committer;

  enum IntentStatus {
    None,
    Committed,
    Released,
    Executed,
    Cancelled,
    Refunded
  }

  mapping(bytes32 => IntentStatus) public status;
  mapping(bytes32 => bytes32) public planHashOf;      // intentHash -> planHash
  mapping(bytes32 => address) public traderOf;        // intentHash -> trader
  mapping(bytes32 => uint256) public deadlineOf;      // intentHash -> deadline
  mapping(bytes32 => uint256) public amountInOf;      // for refund/unlock
  mapping(bytes32 => uint256) public minOutOf;
  mapping(bytes32 => uint256) public destChainIdOf;
  mapping(bytes32 => address) public inputTokenOf;
  mapping(bytes32 => address) public outputTokenOf;

  event IntentCommitted(
    bytes32 indexed intentHash,
    address indexed trader,
    bytes32 planHash,
    uint256 amountIn,
    uint256 minOut,
    uint256 deadline
  );
  event IntentReleased(bytes32 indexed intentHash, address indexed to, uint256 amountIn);
  event IntentExecuted(bytes32 indexed intentHash, bool usedFallback, uint256 amountOut);
  event IntentCancelled(bytes32 indexed intentHash);
  event IntentRefunded(bytes32 indexed intentHash);
  event CommitterUpdated(address indexed committer);

  modifier onlyOwner() {
    _onlyOwner();
    _;
  }

  modifier onlyCommitter() {
    _onlyCommitter();
    _;
  }

  function _onlyOwner() internal view {
    require(msg.sender == owner, "NOT_OWNER");
  }

  function _onlyCommitter() internal view {
    require(msg.sender == committer, "NOT_COMMITTER");
  }

  constructor(address committer_) {
    owner = msg.sender;
    committer = committer_;
  }

  function setCommitter(address committer_) external onlyOwner {
    committer = committer_;
    emit CommitterUpdated(committer_);
  }

  function commitIntent(
    IIntent.TradingIntent calldata intent,
    bytes calldata traderSig,
    IIntent.ExecutionPlan calldata plan
  ) external returns (bytes32 intentHash, bytes32 planHash) {
    require(block.timestamp <= intent.deadline, "INTENT_EXPIRED");

    intentHash = _hashIntent(intent);
    require(_recover(intentHash, traderSig) == intent.trader, "BAD_TRADER_SIG");

    require(plan.intentHash == intentHash, "PLAN_INTENT_MISMATCH");
    require(plan.deadline <= intent.deadline, "PLAN_DEADLINE");
    planHash = keccak256(abi.encode(plan));

    require(status[intentHash] == IntentStatus.None, "ALREADY_COMMITTED");

    planHashOf[intentHash] = planHash;
    traderOf[intentHash] = intent.trader;
    deadlineOf[intentHash] = intent.deadline;
    amountInOf[intentHash] = intent.amountIn;
    minOutOf[intentHash] = intent.minOut;
    destChainIdOf[intentHash] = intent.destChainId;
    inputTokenOf[intentHash] = intent.inputToken;
    outputTokenOf[intentHash] = intent.outputToken;
    status[intentHash] = IntentStatus.Committed;

    IERC20(intent.inputToken).safeTransferFrom(intent.trader, address(this), intent.amountIn);

    emit IntentCommitted(intentHash, intent.trader, planHash, intent.amountIn, intent.minOut, intent.deadline);
  }

  function takeInputForExecution(bytes32 intentHash, address to) external onlyCommitter returns (uint256 amountIn) {
    require(status[intentHash] == IntentStatus.Committed, "NOT_COMMITTED");
    amountIn = amountInOf[intentHash];
    require(amountIn > 0, "NO_INPUT");

    amountInOf[intentHash] = 0;
    status[intentHash] = IntentStatus.Released;
    IERC20(inputTokenOf[intentHash]).safeTransfer(to, amountIn);
    emit IntentReleased(intentHash, to, amountIn);
  }

  function markExecuted(
    bytes32 intentHash,
    uint256 amountOut,
    bool usedFallback
  ) external onlyCommitter {
    require(status[intentHash] == IntentStatus.Released, "NOT_RELEASED");
    status[intentHash] = IntentStatus.Executed;
    emit IntentExecuted(intentHash, usedFallback, amountOut);
  }

  function getIntentData(bytes32 intentHash)
    external
    view
    returns (
      address trader,
      address inputToken,
      address outputToken,
      uint256 amountIn,
      uint256 minOut,
      uint256 deadline,
      uint256 destChainId
    )
  {
    trader = traderOf[intentHash];
    inputToken = inputTokenOf[intentHash];
    outputToken = outputTokenOf[intentHash];
    amountIn = amountInOf[intentHash];
    minOut = minOutOf[intentHash];
    deadline = deadlineOf[intentHash];
    destChainId = destChainIdOf[intentHash];
  }

  function hashIntent(IIntent.TradingIntent calldata intent) external view returns (bytes32) {
    return _hashIntent(intent);
  }

  function cancel(bytes32 intentHash) external {
    require(msg.sender == traderOf[intentHash], "NOT_TRADER");
    require(status[intentHash] == IntentStatus.Committed, "NOT_COMMITTED");
    uint256 amountIn = amountInOf[intentHash];
    require(amountIn > 0, "NO_INPUT");

    amountInOf[intentHash] = 0;
    status[intentHash] = IntentStatus.Cancelled;
    IERC20(inputTokenOf[intentHash]).safeTransfer(traderOf[intentHash], amountIn);
    emit IntentCancelled(intentHash);
  }

  function refundExpired(bytes32 intentHash) external {
    require(block.timestamp > deadlineOf[intentHash], "NOT_EXPIRED");
    require(status[intentHash] == IntentStatus.Committed, "NOT_COMMITTED");
    uint256 amountIn = amountInOf[intentHash];
    require(amountIn > 0, "NO_INPUT");

    amountInOf[intentHash] = 0;
    status[intentHash] = IntentStatus.Refunded;
    IERC20(inputTokenOf[intentHash]).safeTransfer(traderOf[intentHash], amountIn);
    emit IntentRefunded(intentHash);
  }

  function _hashIntent(IIntent.TradingIntent calldata intent) internal view returns (bytes32) {
    // forge-lint: disable-next-line(asm-keccak256)
    bytes32 structHash = keccak256(
      abi.encode(
        _INTENT_TYPEHASH,
        intent.trader,
        intent.inputToken,
        intent.outputToken,
        intent.amountIn,
        intent.minOut,
        intent.deadline,
        intent.nonce,
        intent.sourceChainId,
        intent.destChainId
      )
    );
    return _hashTypedDataV4(structHash);
  }

  function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
    // forge-lint: disable-next-line(asm-keccak256)
    return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
  }

  function _domainSeparatorV4() internal view returns (bytes32) {
    // forge-lint: disable-next-line(asm-keccak256)
    return keccak256(
      abi.encode(
        _EIP712_DOMAIN_TYPEHASH,
        keccak256(bytes(NAME)),
        keccak256(bytes(VERSION)),
        block.chainid,
        address(this)
      )
    );
  }

  function _recover(bytes32 digest, bytes calldata sig) internal pure returns (address) {
    return ECDSA.recover(digest, sig);
  }
}
