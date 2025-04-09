# MaxBTC

A perpetual yield-bearing vault for Bitcoin exposure on Ethereum.

## Overview

MaxBTC is a smart contract that functions as a yield-bearing vault, allowing users to deposit BTC supported assets and receive MaxBTC tokens in return. These tokens represent a claim on the underlying assets plus any yield generated through the custodial management of the deposited funds.

## Key Features

- **Multi-Asset Support**: Deposit WBTC (WBTC, cbBTC, etc.)
- **Yield Generation**: Exposure to Bitcoin with additional yield potential
- **Time-Based Maturity**: Defined deposit period and maturity for redemptions
- **Oracle Price Feeds**: Fair conversion rates through trusted oracle data
- **Flexible Redemption**: Redeem MaxBTC tokens for underlying assets after maturity

## Contract Architecture

The MaxBTC contract is built on Ethereum using Solidity 0.8.28 and implements several OpenZeppelin contracts:

- **ERC20**: For the MaxBTC token functionality
- **ReentrancyGuard**: To prevent reentrancy attacks
- **Ownable**: For administrative control
- **Math**: For safe mathematical operations
- **SafeERC20**: For safe token transfers

## Usage

### For Users

#### Depositing Assets

Users can deposit supported assets to receive MaxBTC tokens:

```solidity
// Standard deposit
function deposit(uint assets, address receiver) public returns (uint)

// Deposit with quote validation
function deposit(uint assets, uint expectedQuote, address receiver) public returns (uint)
```

#### Minting MaxBTC Tokens

Users can mint a specific amount of MaxBTC tokens:

```solidity
// Standard mint
function mint(uint256 amount, address receiver) public returns (uint)

// Mint with quote validation
function mint(uint256 amount, uint expectedQuote, address receiver) public returns (uint)
```

#### Redeeming After Maturity

After the maturity date, users can redeem their MaxBTC tokens:

```solidity
// Withdraw a specific amount of assets
function withdraw(uint256 assets, address receiver, address owner) public returns (uint)

// Redeem a specific amount of MaxBTC tokens
function redeem(uint256 amount, address receiver, address owner) public returns (uint256)
```

### For Administrators

```solidity
// Initialize the product
function initializeProduct(ProductParams memory params) external onlyOwner

// Add a supported asset
function addAsset(address asset, uint256 minDepositAmount) external onlyOwner

// Set the custodian address
function setCustodian(address newCustodian) external onlyOwner

// Set the oracle address
function setOracle(address newOracle) external onlyOwner

// Emergency stop functionality
function setContractStopped(bool _stopped) external onlyOwner
```

### For Oracle

```solidity
// Set the quote for an asset
function setQuote(address asset, uint amount) external onlyOracle
```

## Product Flow

1. **Initialization**:
   - Contract owner initializes the product with parameters (start time, end time, etc.)
   - Owner adds supported assets with minimum deposit amounts

2. **Deposit Phase** (before maturity):
   - Oracle sets quotes for supported assets
   - Users deposit assets and receive MaxBTC tokens
   - Assets are transferred to the custodian for management

3. **Maturity Phase** (after end time):
   - Available redemption amount is set
   - Users can redeem their MaxBTC tokens for assets
   - Redemption is proportional to user's share of total supply

## Events

- `ProductInitialized`: When the product is initialized
- `AssetAdded`: When a new asset is added
- `QuoteSet`: When a new quote is set for an asset
- `Deposit`: When a user deposits assets
- `Withdraw`: When a user withdraws assets
- `AvailableRedemptionSet`: When the redemption amount is updated
- `CustodianSet`: When the custodian address is changed
- `ContractStopped`: When the contract's stopped state changes

## Security Features

- **Reentrancy Protection**: Guards against reentrancy attacks
- **Access Control**: Owner and oracle-restricted functions
- **Quote Validation**: Users can validate quotes before transacting
- **Minimum Deposit**: Prevents dust attacks
- **Emergency Stop**: Contract can be paused in emergency situations

## Contract Interface

```solidity
struct ProductParams {
    uint startTime;      // Start time for deposits
    uint endTime;        // End time (maturity)
    uint minDeposit;     // Minimum deposit amount
    uint quotePeriod;    // Duration for which the quote is valid
    address custodian;   // Custodian address
    address oracle;      // Oracle address
}
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
