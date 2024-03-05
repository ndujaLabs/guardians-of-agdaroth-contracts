// SPDX-License-Identifier: GPL3
pragma solidity ^0.8.20;

import {GoA} from "../GoA.sol";

//import "hardhat/console.sol";

// This is used to calculate exactly the GAS_LIMIT to be set in the smart contract when receiving a message
contract GoAMock is GoA {
  constructor(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    address admin,
    address _wormholeRelayer,
    address _wormhole
  ) GoA(minDelay, proposers, executors, admin, _wormholeRelayer, _wormhole) {}

  // used to set the hardcode GAS_LIMIT
  function receiveWormholeMessages(bytes memory payload, bytes[] memory, bytes32, uint16, bytes32) public payable override {
    //    uint256 g = gasleft();
    (address sender, uint256 tokenId) = abi.decode(payload, (address, uint256));
    _mintAndActivate(sender, block.chainid * 1e6 + (tokenId % 1e6));
    //    console.log("Gas used: %d", g - gasleft());
  }
}
