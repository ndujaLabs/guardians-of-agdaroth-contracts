// SPDX-License-Identifier: GPL3
pragma solidity ^0.8.20;

import {CrunaProtectedNFTTimeControlled} from "@cruna/protocol/token/CrunaProtectedNFTTimeControlled.sol";
import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {Base} from "wormhole-solidity-sdk/Base.sol";

//import "hardhat/console.sol";

// @dev This contract is a simple example of a protected NFT.
contract GoA is CrunaProtectedNFTTimeControlled, Base, IWormholeReceiver {
  error Forbidden();
  error OnlyRelayerAllowed();
  error WrongSourceChain();
  error WrongSourceAddress();
  error NotTheMintingChain();
  error WrongValue();
  error NotTheOwner();

  address public factory;
  uint256 public gasLimit = 140_000;

  // @dev This modifier will only allow the factory to call the function.
  //   The factory is the contract that manages the sale of the tokens.
  modifier onlyFactory() {
    if (factory == address(0) || _msgSender() != factory) revert Forbidden();
    _;
  }

  // @dev This constructor will initialize the contract with the necessary parameters
  //   The contracts of whom we pass the addresses in the construction, will be deployed
  //   using Nick's factory, so we may in theory hardcode them in the code. However,
  //   if so, we will not be able to test the contract.
  constructor(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    address admin,
    address _wormholeRelayer,
    address _wormhole
  )
    CrunaProtectedNFTTimeControlled("Guardians of Agdaroth", "GoA", minDelay, proposers, executors, admin)
    Base(_wormholeRelayer, _wormhole)
  {}

  function init(
    address managerAddress_,
    bool progressiveTokenIds_,
    bool allowUntrustedTransfers_,
    uint112,
    uint112
  ) external virtual override {
    _canManage(true);
    if (managerAddress_ == address(0)) revert ZeroAddress();
    uint112 firstTokenId_ = uint112(block.chainid * 1e6);
    nftConf = NftConf({
      progressiveTokenIds: progressiveTokenIds_,
      allowUntrustedTransfers: allowUntrustedTransfers_,
      nextTokenId: firstTokenId_,
      // we may change this value in the future if we extend the collection
      maxTokenId: uint112(block.chainid * 1e6 + 10000),
      managerHistoryLength: 1,
      unusedField: 0
    });
    managerHistory.push(ManagerHistory({managerAddress: managerAddress_, firstTokenId: firstTokenId_, lastTokenId: 0}));
  }

  // @dev Set factory to 0x0 to disable a factory.
  // @notice This is the only function that can be called by the owner.
  //   It does not introduce centralization, because it is related with
  //   the factory that sells the tokens, not the NFT itself.
  // @param factory The address of the factory.
  function setFactory(address factory_) external virtual {
    _canManage(true);
    if (factory_ == address(0)) revert ZeroAddress();
    factory = factory_;
  }

  // @dev This function will mint a new token
  // @param to The address of the recipient
  function safeMintAndActivate(address to, uint256 tokenId) public virtual onlyFactory {
    _mintAndActivate(to, tokenId);
  }

  // @dev This function will update the gas limit, in case at some moment it will come out that the expected limit is not enough
  function updateGasLimit(uint256 gasLimit_) external virtual {
    _canManage(false);
    gasLimit = gasLimit_;
  }

  // @dev This function will return the base URI of the contract
  function _baseURI() internal view virtual override returns (string memory) {
    return "https://meta.ndujalabs.com/goa/";
  }

  // @dev This function will return the contract URI of the contract
  function contractURI() public view virtual returns (string memory) {
    return "https://meta.ndujalabs.com/goa/info";
  }

  function quoteCrossChainMinting(uint16 targetChain) public view virtual returns (uint256 cost) {
    (cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, gasLimit);
  }

  function nextAvailableTokenId() public view virtual returns (uint256) {
    return nftConf.nextTokenId;
  }

  function sendCrossChainMinting(uint16 targetChain, address targetAddress, uint256 tokenId) public payable virtual {
    if (_msgSender() != ownerOf(tokenId)) {
      revert NotTheOwner();
    }
    uint256 cost = quoteCrossChainMinting(targetChain);
    if (msg.value != cost) revert WrongValue();
    wormholeRelayer.sendPayloadToEvm{value: cost}(targetChain, targetAddress, abi.encode(_msgSender(), tokenId), 0, gasLimit);
  }

  function receiveWormholeMessages(
    bytes memory payload,
    bytes[] memory,
    bytes32 sourceAddress,
    uint16,
    bytes32
  ) public payable virtual override onlyWormholeRelayer {
    // tokens will be deployed using Nick's factory, so they will have the same address on every chain
    if (sourceAddress != bytes32(uint256(uint160(address(this))))) revert WrongSourceAddress();
    //
    (address sender, uint256 tokenId) = abi.decode(payload, (address, uint256));
    _mintAndActivate(sender, tokenId);
  }
}
