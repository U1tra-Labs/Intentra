// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library ECDSA {
  function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
    if (signature.length != 65) return address(0);
    bytes32 r;
    bytes32 s;
    uint8 v;
    assembly {
      r := mload(add(signature, 32))
      s := mload(add(signature, 64))
      v := byte(0, mload(add(signature, 96)))
    }
    if (v < 27) v += 27;
    if (v != 27 && v != 28) return address(0);
    return ecrecover(hash, v, r, s);
  }
}
