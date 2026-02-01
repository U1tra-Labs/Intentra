// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMakerFill} from "./IMakerFill.sol";
import {IIntent} from "../interfaces/IIntent.sol";
import {ECDSA} from "../utils/ECDSA.sol";
import {SafeTransferLib, IERC20} from "../utils/SafeTransferLib.sol";

// NOTE: Future extension point: route selection for cross-chain fills can live here
// (e.g., per-destination inventory rules or chain-aware quoting).
contract MakerFill is IMakerFill {
  using SafeTransferLib for IERC20;

  bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 private constant _QUOTE_TYPEHASH =
    keccak256(
      "MakerQuote(bytes32 intentHash,address inputToken,address outputToken,uint256 amountIn,uint256 amountOut,uint256 expiry)"
    );

  string public constant NAME = "MakerFill";
  string public constant VERSION = "1";

  // forge-lint: disable-next-line(screaming-snake-case-immutable)
  address public immutable maker;

  struct Quote {
    address inputToken;
    address outputToken;
    uint256 amountIn;
    uint256 amountOut;
    uint256 expiry;
  }

  constructor(address maker_) {
    maker = maker_;
  }

  function fill(
    bytes32 intentHash,
    address inputToken,
    address outputToken,
    uint256 amountIn,
    uint256 minOut,
    bytes calldata makerPayload
  ) external returns (uint256 amountOut) {
    IIntent.RfqStep memory rfq = abi.decode(makerPayload, (IIntent.RfqStep));
    require(rfq.maker == maker, "MAKER_MISMATCH");
    require(block.timestamp <= rfq.expiry, "QUOTE_EXPIRED");
    require(rfq.amountOut >= minOut, "QUOTE_TOO_LOW");

    bytes32 quoteHash = _hashQuote(intentHash, inputToken, outputToken, amountIn, rfq.amountOut, rfq.expiry);
    require(ECDSA.recover(quoteHash, rfq.makerSig) == maker, "BAD_MAKER_SIG");

    IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amountIn);
    IERC20(outputToken).safeTransfer(msg.sender, rfq.amountOut);

    amountOut = rfq.amountOut;
  }

  function quoteDigest(bytes32 intentHash, Quote calldata q) external view returns (bytes32) {
    return _hashQuote(intentHash, q.inputToken, q.outputToken, q.amountIn, q.amountOut, q.expiry);
  }

  function _hashQuote(
    bytes32 intentHash,
    address inputToken,
    address outputToken,
    uint256 amountIn,
    uint256 amountOut,
    uint256 expiry
  ) internal view returns (bytes32) {
    // forge-lint: disable-next-line(asm-keccak256)
    bytes32 structHash = keccak256(
      abi.encode(_QUOTE_TYPEHASH, intentHash, inputToken, outputToken, amountIn, amountOut, expiry)
    );
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
}
