// SPDX-License-Identifier: GPL3
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CrunaProtectedNFTTimeControlled} from "@cruna/protocol/token/CrunaProtectedNFTTimeControlled.sol";
import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

//import "hardhat/console.sol";

// @dev This contract is a simple example of a protected NFT.
contract GoA is CrunaProtectedNFTTimeControlled, IWormholeReceiver {
  using Strings for uint256;

  error Forbidden();
  error OnlyRelayerAllowed();
  error WrongSourceChain();
  error WrongSourceAddress();
  error NotTheMintingChain();
  error WrongValue();
  error RelayerNotSet();
  error NoReservedTokensOnThisChain();
  error Disabled();

  IWormholeRelayer public wormholeRelayer;

  uint256 public gasLimit = 140_000;

  // on Polygon and Ethereum we have reserved tokens to Everdragons and Everdragons2
  uint256 public reservedTokens;
  address public claimer;

  address public factory;

  // @dev This constructor will initialize the contract with the necessary parameters
  //   The contracts of whom we pass the addresses in the construction, will be deployed
  //   using Nick's factory, so we may in theory hardcode them in the code. However,
  //   if so, we will not be able to test the contract.
  constructor(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    address admin
  ) CrunaProtectedNFTTimeControlled("Guardians of Agdaroth", "GoA", minDelay, proposers, executors, admin) {}

  function init(address, bool, bool, uint256, uint256) external virtual override {
    revert Disabled();
  }

  function initGoA(
    address managerAddress_,
    bool progressiveTokenIds_,
    bool allowUntrustedTransfers_,
    uint256 reservedTokens_,
    address claimer_,
    address relayer_
  ) external virtual {
    _canManage(true);
    if (nftConf.managerHistoryLength > 0) revert AlreadyInitiated();
    reservedTokens = reservedTokens_;
    if (managerAddress_ == address(0)) revert ZeroAddress();
    uint112 firstTokenId_ = uint112(block.chainid * 1e4 + 1);
    uint112 nextTokenId_ = uint112(firstTokenId_ + reservedTokens_);
    nftConf = NftConf({
      progressiveTokenIds: progressiveTokenIds_,
      allowUntrustedTransfers: allowUntrustedTransfers_,
      nextTokenId: uint112(nextTokenId_),
      // we may change this value in the future if we extend the collection
      maxTokenId: firstTokenId_ + 1e4 - 1,
      managerHistoryLength: 1,
      unusedField: 0
    });
    managerHistory.push(ManagerHistory({managerAddress: managerAddress_, firstTokenId: firstTokenId_, lastTokenId: 0}));
    claimer = claimer_;
    wormholeRelayer = IWormholeRelayer(relayer_);
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
  function safeMintAndActivate(address to, uint256 amount) public virtual {
    if (factory == address(0) || _msgSender() != factory) revert Forbidden();
    _mintAndActivateByAmount(to, amount);
  }

  // @dev This function will update the gas limit, in case at some moment it will come out that the expected limit is not enough
  function updateGasLimit(uint256 gasLimit_) external virtual {
    _canManage(false);
    gasLimit = gasLimit_;
  }

  // @dev This function will return the base URI of the contract
  function _baseURI() internal view virtual override returns (string memory) {
    return string.concat("https://meta.ndujalabs.com/goa/", block.chainid.toString(), "/");
  }

  // @dev This function will return the contract URI of the contract
  function contractURI() public view virtual returns (string memory) {
    return string.concat("https://meta.ndujalabs.com/goa/", block.chainid.toString(), "/info");
  }

  function setClaimer(address _claimer) external virtual {
    _canManage(true);
    if (reservedTokens == 0) revert NoReservedTokensOnThisChain();
    claimer = _claimer;
  }

  function claim(uint256[] calldata tokenIds) external virtual {
    if (claimer == address(0)) revert NoReservedTokensOnThisChain();
    IERC721 nft = IERC721(claimer);
    for (uint256 i = 0; i < tokenIds.length; i++) {
      if (nft.ownerOf(tokenIds[i]) != _msgSender()) revert NotTheTokenOwner();
      _mintAndActivate(_msgSender(), block.chainid * 1e4 + tokenIds[i]);
    }
  }

  function quoteCrossChainMinting(uint16 targetChain) public view virtual returns (uint256 cost) {
    (cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, gasLimit);
  }

  function nextAvailableTokenId() public view virtual returns (uint256) {
    return nftConf.nextTokenId;
  }

  function sendCrossChainMinting(uint16 targetChain, address, uint256 tokenId) public payable virtual {
    if (address(wormholeRelayer) == address(0)) revert RelayerNotSet();
    if (_msgSender() != ownerOf(tokenId)) {
      revert NotTheTokenOwner();
    }
    uint256 cost = quoteCrossChainMinting(targetChain);
    if (msg.value != cost) revert WrongValue();
    wormholeRelayer.sendPayloadToEvm{value: cost}(targetChain, address(this), abi.encode(_msgSender(), tokenId), 0, gasLimit);
  }

  function receiveWormholeMessages(
    bytes memory payload,
    bytes[] memory,
    bytes32 sourceAddress,
    uint16,
    bytes32
  ) public payable virtual override {
    if (_msgSender() != address(wormholeRelayer)) revert OnlyRelayerAllowed();
    // tokens will be deployed using Nick's factory, so they will have the same address on every chain
    if (sourceAddress != bytes32(uint256(uint160(address(this))))) revert WrongSourceAddress();
    //
    (address sender, uint256 tokenId) = abi.decode(payload, (address, uint256));
    _mintAndActivate(sender, tokenId);
  }
}
