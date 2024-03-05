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

  struct Config {
    GoA goa;
    uint32 price;
    mapping(address => bool) stableCoins;
    address[] stableCoinsList;
  }

  error ZeroAddress();
  error InsufficientFunds();
  error InsufficientAllowance();
  error UnsupportedStableCoin();
  error InvalidArguments();
  error InvalidDiscount();
  error NoClaimOnThisChain();

  Config public config;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address payable vault_) public initializer {
    __Ownable_init(_msgSender());
    __UUPSUpgradeable_init();
    config.goa = GoA(vault_);
  }

  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  // @notice The price is in points, so that 1 point = 0.01 USD
  function setPrice(uint32 price_) external virtual onlyOwner {
    // it is owner's responsibility to set a reasonable price
    config.price = price_;
    emit PriceSet(price_);
  }

  function setStableCoin(address stableCoin, bool active) external virtual onlyOwner {
    if (active) {
      // We check if less than 6 because TetherUSD has 6 decimals
      // It should revert if the stableCoin is not an ERC20
      if (ERC20(stableCoin).decimals() < 6) {
        revert UnsupportedStableCoin();
      }
      if (!config.stableCoins[stableCoin]) {
        config.stableCoins[stableCoin] = true;
        config.stableCoinsList.push(stableCoin);
        emit StableCoinSet(stableCoin, active);
      }
    } else if (config.stableCoins[stableCoin]) {
      delete config.stableCoins[stableCoin];
      // no risk of going out of cash because the factory will support just a couple of stable coins
      for (uint256 i = 0; i < config.stableCoinsList.length; i++) {
        if (config.stableCoinsList[i] == stableCoin) {
          config.stableCoinsList[i] = config.stableCoinsList[config.stableCoinsList.length - 1];
          config.stableCoinsList.pop();
          break;
        }
      }
      emit StableCoinSet(stableCoin, active);
    }
  }

  function finalPrice(address stableCoin) public view virtual returns (uint256) {
    if (!config.stableCoins[stableCoin]) revert UnsupportedStableCoin();
    return (config.price * (10 ** ERC20(stableCoin).decimals())) / 100;
  }

  function buy(address stableCoin, uint256 amount) external virtual nonReentrant {
    uint256 price = finalPrice(stableCoin) * amount;
    ERC20 token = ERC20(stableCoin);
    if (price > token.balanceOf(_msgSender())) revert InsufficientFunds();
    if (price > token.allowance(_msgSender(), address(this))) revert InsufficientAllowance();
    config.goa.safeMintAndActivate(_msgSender(), amount);
    token.safeTransferFrom(_msgSender(), address(this), price);
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
    return config.stableCoinsList;
  }
}
