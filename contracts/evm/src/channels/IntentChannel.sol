// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIntent} from "../interfaces/IIntent.sol";
import {ECDSA} from "../utils/ECDSA.sol";
import {SafeTransferLib, IERC20} from "../utils/SafeTransferLib.sol";
import {CommitmentTypes} from "../libraries/CommitmentTypes.sol";

contract IntentChannel {
  using SafeTransferLib for IERC20;

  bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 private constant _INTENT_TYPEHASH =
    keccak256(
      "TradingIntent(address trader,address inputToken,address outputToken,uint256 amountIn,uint256 minOut,uint256 deadline,uint256 nonce,uint256 sourceChainId,uint256 destChainId)"
    );
  bytes32 private constant _COMMITMENT_AUTH_TYPEHASH =
    keccak256(
      "CommitmentAuthorization(bytes32 commitment,address trader,address inputToken,uint256 amountIn,uint256 deadline,uint256 notBefore)"
    );

  string public constant NAME = "IntentChannel";
  string public constant VERSION = "1";

  address public owner;
  address public committer;
  uint256 public batchWindow;
  uint256 public minDelay;

  enum IntentStatus {
    None,
    Committed,
    Released,
    Executed,
    Cancelled,
    Refunded
  }

  enum CommitmentStatus {
    None,
    Pending,
    Revealed,
    Cancelled,
    Refunded
  }

  struct CommitmentRecord {
    address trader;
    address inputToken;
    uint256 amountIn;
    uint256 deadline;
    uint256 notBefore;
    CommitmentStatus status;
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
  mapping(bytes32 => CommitmentRecord) public commitments; // commitment -> record
  mapping(bytes32 => bytes32) public commitmentOfIntent;   // intentHash -> commitment
  mapping(bytes32 => bytes32) public intentOfCommitment;   // commitment -> intentHash
  mapping(bytes32 => uint256) public notBeforeOf;          // intentHash -> notBefore

  event IntentCommitted(
    bytes32 indexed intentHash,
    address indexed trader,
    bytes32 planHash,
    uint256 amountIn,
    uint256 minOut,
    uint256 deadline
  );
  event IntentCommittedPrivate(
    bytes32 indexed commitment,
    address indexed trader,
    address inputToken,
    uint256 amountIn,
    uint256 notBefore,
    uint256 deadline
  );
  event IntentRevealed(
    bytes32 indexed commitment,
    bytes32 indexed intentHash,
    bytes32 indexed planHash,
    address trader
  );
  event IntentReleased(bytes32 indexed intentHash, address indexed to, uint256 amountIn);
  event IntentExecuted(bytes32 indexed intentHash, bool usedFallback, uint256 amountOut);
  event IntentCancelled(bytes32 indexed intentHash);
  event IntentRefunded(bytes32 indexed intentHash);
  event CommitmentCancelled(bytes32 indexed commitment, address indexed trader, uint256 refundAmount);
  event CommitterUpdated(address indexed committer);
  event BatchWindowUpdated(uint256 oldWindow, uint256 newWindow);
  event MinDelayUpdated(uint256 oldDelay, uint256 newDelay);

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

  function setBatchParams(uint256 newWindow, uint256 newDelay) external onlyOwner {
    uint256 oldWindow = batchWindow;
    uint256 oldDelay = minDelay;
    batchWindow = newWindow;
    minDelay = newDelay;
    emit BatchWindowUpdated(oldWindow, newWindow);
    emit MinDelayUpdated(oldDelay, newDelay);
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

  function commitIntentPrivate(
    bytes32 commitment,
    address inputToken,
    uint256 amountIn,
    uint256 deadline,
    uint256 notBefore,
    address trader,
    bytes calldata traderSig
  ) external payable {
    require(deadline >= block.timestamp, "INTENT_EXPIRED");
    require(inputToken != address(0), "NATIVE_INPUT_UNSUPPORTED");
    require(commitments[commitment].status == CommitmentStatus.None, "COMMITMENT_EXISTS");
    require(notBefore <= deadline, "NOTBEFORE_AFTER_DEADLINE");

    uint256 earliest = block.timestamp + minDelay;
    require(notBefore >= earliest, "TOO_SOON");
    uint256 aligned = _alignToBatchWindow(notBefore);
    require(notBefore == aligned, "NOT_ALIGNED");

    if (msg.sender != trader) {
      require(traderSig.length > 0, "MISSING_SIG");
      bytes32 digest = _hashCommitmentAuthorization(commitment, trader, inputToken, amountIn, deadline, notBefore);
      require(_recover(digest, traderSig) == trader, "INVALID_SIG");
    }

    commitments[commitment] = CommitmentRecord({
      trader: trader,
      inputToken: inputToken,
      amountIn: amountIn,
      deadline: deadline,
      notBefore: notBefore,
      status: CommitmentStatus.Pending
    });

    _escrowInput(inputToken, trader, amountIn);

    emit IntentCommittedPrivate(commitment, trader, inputToken, amountIn, notBefore, deadline);
  }

  function revealIntent(
    bytes32 commitment,
    IIntent.TradingIntent calldata intent,
    bytes calldata traderSig,
    IIntent.ExecutionPlan calldata plan,
    bytes32 salt
  ) external returns (bytes32 intentHash, bytes32 planHash) {
    CommitmentRecord storage record = commitments[commitment];
    require(record.status == CommitmentStatus.Pending, "COMMITMENT_NOT_PENDING");
    require(block.timestamp <= record.deadline, "INTENT_EXPIRED");
    require(block.timestamp >= record.notBefore, "BATCH_NOT_READY");
    require(intent.trader == record.trader, "TRADER_MISMATCH");
    require(intent.inputToken == record.inputToken, "INPUT_TOKEN_MISMATCH");
    require(intent.amountIn == record.amountIn, "AMOUNT_MISMATCH");
    require(intent.deadline == record.deadline, "DEADLINE_MISMATCH");

    intentHash = _hashIntent(intent);
    require(_recover(intentHash, traderSig) == intent.trader, "BAD_TRADER_SIG");

    require(plan.intentHash == intentHash, "PLAN_INTENT_MISMATCH");
    require(plan.deadline <= intent.deadline, "PLAN_DEADLINE");
    planHash = keccak256(abi.encode(plan));

    require(CommitmentTypes.verify(commitment, intentHash, planHash, record.notBefore, salt), "BAD_COMMITMENT");
    require(status[intentHash] == IntentStatus.None, "ALREADY_COMMITTED");

    planHashOf[intentHash] = planHash;
    traderOf[intentHash] = intent.trader;
    deadlineOf[intentHash] = intent.deadline;
    amountInOf[intentHash] = intent.amountIn;
    minOutOf[intentHash] = intent.minOut;
    destChainIdOf[intentHash] = intent.destChainId;
    inputTokenOf[intentHash] = intent.inputToken;
    outputTokenOf[intentHash] = intent.outputToken;
    notBeforeOf[intentHash] = record.notBefore;
    status[intentHash] = IntentStatus.Committed;

    commitmentOfIntent[intentHash] = commitment;
    intentOfCommitment[commitment] = intentHash;
    record.status = CommitmentStatus.Revealed;

    emit IntentRevealed(commitment, intentHash, planHash, intent.trader);
  }

  function cancelCommitment(bytes32 commitment) external {
    CommitmentRecord storage record = commitments[commitment];
    require(record.status == CommitmentStatus.Pending, "NOT_PENDING");
    require(msg.sender == record.trader, "NOT_TRADER");

    record.status = CommitmentStatus.Cancelled;
    _refundCommitment(record);
    emit CommitmentCancelled(commitment, record.trader, record.amountIn);
  }

  function refundCommitment(bytes32 commitment) external {
    CommitmentRecord storage record = commitments[commitment];
    require(record.status == CommitmentStatus.Pending, "NOT_PENDING");
    require(block.timestamp > record.deadline, "NOT_EXPIRED");

    record.status = CommitmentStatus.Refunded;
    _refundCommitment(record);
    emit CommitmentCancelled(commitment, record.trader, record.amountIn);
  }

  function takeInputForExecution(bytes32 intentHash, address to) external onlyCommitter returns (uint256 amountIn) {
    require(status[intentHash] == IntentStatus.Committed, "NOT_COMMITTED");
    require(block.timestamp >= notBeforeOf[intentHash], "BATCH_NOT_READY");
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

  function hashCommitmentAuthorization(
    bytes32 commitment,
    address trader,
    address inputToken,
    uint256 amountIn,
    uint256 deadline,
    uint256 notBefore
  ) external view returns (bytes32) {
    return _hashCommitmentAuthorization(commitment, trader, inputToken, amountIn, deadline, notBefore);
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

  function _alignToBatchWindow(uint256 timestamp) internal view returns (uint256) {
    if (batchWindow == 0) return timestamp;
    uint256 rounded = timestamp - (timestamp % batchWindow);
    if (timestamp % batchWindow == 0) return timestamp;
    return rounded + batchWindow;
  }

  function _escrowInput(address inputToken, address trader, uint256 amountIn) internal {
    if (inputToken == address(0)) {
      require(msg.value == amountIn, "BAD_MSG_VALUE");
      return;
    }
    require(msg.value == 0, "UNEXPECTED_VALUE");
    IERC20(inputToken).safeTransferFrom(trader, address(this), amountIn);
  }

  function _refundCommitment(CommitmentRecord storage record) internal {
    if (record.amountIn == 0) return;
    if (record.inputToken == address(0)) {
      (bool ok, ) = record.trader.call{value: record.amountIn}("");
      require(ok, "NATIVE_REFUND_FAILED");
    } else {
      IERC20(record.inputToken).safeTransfer(record.trader, record.amountIn);
    }
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

  function _hashCommitmentAuthorization(
    bytes32 commitment,
    address trader,
    address inputToken,
    uint256 amountIn,
    uint256 deadline,
    uint256 notBefore
  ) internal view returns (bytes32) {
    // forge-lint: disable-next-line(asm-keccak256)
    bytes32 structHash = keccak256(
      abi.encode(_COMMITMENT_AUTH_TYPEHASH, commitment, trader, inputToken, amountIn, deadline, notBefore)
    );
    return _hashTypedDataV4(structHash);
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
