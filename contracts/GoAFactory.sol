// SPDX-License-Identifier: GPL3
pragma solidity ^0.8.20;

// Author : Francesco Sullo < francesco@superpower.io>
// (c) Superpower Labs Inc.

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Initializable, UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {GoA} from "./GoA.sol";

//import {console} from "hardhat/console.sol";

contract GoAFactory is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
  using SafeERC20 for ERC20;
  event PriceSet(uint256 price);
  event StableCoinSet(address stableCoin, bool active);

  error ZeroAddress();
  error InsufficientFunds();
  error UnsupportedStableCoin();
  error InvalidArguments();
  error InvalidDiscount();

  struct ReservedRange {
    uint112 start;
    uint112 end;
  }

  GoA public goa;
  uint256 public price;
  mapping(address => bool) public stableCoins;
  uint256 public discount;
  address[] private _stableCoins;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address vault_) public initializer {
    __Ownable_init(_msgSender());
    __UUPSUpgradeable_init();
    goa = GoA(vault_);
  }

  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  // @notice The price is in points, so that 1 point = 0.01 USD
  function setPrice(uint256 price_) external virtual onlyOwner {
    // it is owner's responsibility to set a reasonable price
    price = price_;
    emit PriceSet(price);
  }

  function setStableCoin(address stableCoin, bool active) external virtual onlyOwner {
    if (active) {
      // We check if less than 6 because TetherUSD has 6 decimals
      // It should revert if the stableCoin is not an ERC20
      if (ERC20(stableCoin).decimals() < 6) {
        revert UnsupportedStableCoin();
      }
      if (!stableCoins[stableCoin]) {
        stableCoins[stableCoin] = true;
        _stableCoins.push(stableCoin);
        emit StableCoinSet(stableCoin, active);
      }
    } else if (stableCoins[stableCoin]) {
      delete stableCoins[stableCoin];
      // no risk of going out of cash because the factory will support just a couple of stable coins
      for (uint256 i = 0; i < _stableCoins.length; i++) {
        if (_stableCoins[i] == stableCoin) {
          _stableCoins[i] = _stableCoins[_stableCoins.length - 1];
          _stableCoins.pop();
          break;
        }
      }
      emit StableCoinSet(stableCoin, active);
    }
  }

  function finalPrice(address stableCoin) public view virtual returns (uint256) {
    return (price * (10 ** ERC20(stableCoin).decimals())) / 100;
  }

  function buy(address stableCoin, uint256[] calldata tokenIds) external virtual nonReentrant {
    uint256 payment = finalPrice(stableCoin) * tokenIds.length;
    if (payment > ERC20(stableCoin).balanceOf(_msgSender())) revert InsufficientFunds();
    for (uint256 i = 0; i < tokenIds.length; i++) {
      goa.safeMintAndActivate(_msgSender(), tokenIds[i]);
    }
    // we manage only trusted stable coins, so no risk of reentrancy
    ERC20(stableCoin).safeTransferFrom(_msgSender(), address(this), payment);
  }

  function claim(uint256[] calldata tokenIds) external virtual nonReentrant {
    for (uint256 i = 0; i < tokenIds.length; i++) {
      goa.safeMintAndActivate(_msgSender(), tokenIds[i]);
    }
  }

  function withdrawProceeds(address beneficiary, address stableCoin, uint256 amount) external virtual onlyOwner {
    uint256 balance = ERC20(stableCoin).balanceOf(address(this));
    if (amount == 0) {
      amount = balance;
    }
    if (amount > balance) revert InsufficientFunds();
    ERC20(stableCoin).safeTransfer(beneficiary, amount);
  }

  function getStableCoins() external view virtual returns (address[] memory) {
    return _stableCoins;
  }
}
