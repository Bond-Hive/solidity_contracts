// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./dependencies/ReentrancyGuard.sol"; // For reentrancy protection
import "./dependencies/Ownable.sol"; // For admin control
import "./interfaces/IVault.sol"; // Interfaces and structs
import "./BondFactory.sol"; // Import the BondFactory

/**
 * @title Vault
 * @dev A vault contract for managing multiple bonds/products.
 */
contract Vault is ReentrancyGuard, Ownable {
    /// @notice Decimals value (for shares and quotes)
    uint public constant DECIMALS = 18;
    /// @notice Number of strategies
    uint public productsCounter;
    /// @notice Contract dev
    string public dev = "t.me/frankfourier";

    // Mapping from productId to Product
    mapping(uint => Product) public products;

    // Reference to the BondFactory
    BondFactory public bondFactory;

    // Events
    event ProductInitialized(uint indexed productId, address indexed bondAddress, uint startTime, uint endTime);
    event SharesMinted(uint indexed productId, address indexed to, uint amount);
    event SharesBurned(uint indexed productId, uint amount);
    event Deposit(uint indexed productId, address indexed from, uint amount, uint shares);
    event Withdraw(uint indexed productId, address indexed to, uint shares, uint amount);
    event QuoteSet(uint indexed productId, uint amount);
    event AvailableRedemptionSet(uint indexed productId, uint amount);
    event AdminChanged(uint indexed productId, address indexed newAdmin);
    event TreasurySet(uint indexed productId, address indexed newTreasury);
    event ContractStopped(uint indexed productId, bool stopped);

    // Modifiers
    modifier onlyProductAdmin(uint productId) {
        require(msg.sender == products[productId].admin, "Not product admin");
        _;
    }

    modifier whenNotStopped(uint productId) {
        require(!products[productId].stopped, "Contract is stopped");
        _;
    }

    modifier checkProductExistence(uint productId) {
        require(productsCounter > productId, "Product doesn't exist");
        _;
    }

    /**
     * @dev Constructor to set the BondFactory address.
     */
    constructor() {
        bondFactory = new BondFactory();
    }

    /**
     * @dev Initialize a new product.
     * @param params Struct containing initialization parameters.
     */
    function initializeProduct(
        ProductParams memory params
    ) external onlyOwner {
        uint productId = productsCounter;
        require(!products[productId].initialized, "Product already initialized");

        // Fetch the token's decimals
        uint8 tokenDecimals = IERC20Metadata(params.token).decimals();

        // Ensure token decimals do not exceed 18
        require(tokenDecimals <= DECIMALS, "Token decimals cannot exceed 18");

        // Deploy the ShareToken (bond) using BondFactory
        address bondAddress = bondFactory.createBond(params.bondName, params.bondSymbol, address(this));

        products[productId] = Product({
            token: params.token,
            tokenShare: bondAddress,
            admin: params.admin,
            startTime: params.startTime,
            endTime: params.endTime,
            totalShares: 0,
            totalDeposits: 0,
            availableRedemption: 0,
            currentQuote: 0,
            quoteExpiration: 0,
            quotePeriod: params.quotePeriod,
            treasury: params.treasury,
            minDeposit: params.minDeposit,
            initialized: true,
            stopped: false,
            tokenDecimals: tokenDecimals
        });

        productsCounter++;
        emit ProductInitialized(productId, bondAddress, params.startTime, params.endTime);
    }

    /**
     * @dev Set the contract's stopped state for a product.
     * @param productId Unique ID for the product.
     * @param _stopped Boolean indicating the new stopped state.
     */
    function setContractStopped(uint productId, bool _stopped) external onlyProductAdmin(productId) checkProductExistence(productId) {
        products[productId].stopped = _stopped;
        emit ContractStopped(productId, _stopped);
    }

    /**
     * @dev Get the current quote for a product.
     * @param productId Unique ID for the product.
     * @return The current quote if valid, otherwise zero.
     */
    function quote(uint productId) external view checkProductExistence(productId) returns (uint) {
        Product storage product = products[productId];
        if (block.timestamp <= product.quoteExpiration) {
            return product.currentQuote;
        } else {
            return 0;
        }
    }

    /**
     * @dev Set a new quote for a product.
     * @param productId Unique ID for the product.
     * @param amount The new quote amount.
     */
    function setQuote(uint productId, uint amount) external onlyProductAdmin(productId) checkProductExistence(productId) {
        require(amount > 0, "Invalid amount");
        Product storage product = products[productId];

        if (product.currentQuote != 0 && block.timestamp <= product.quoteExpiration) {
            revert("Quote still valid");
        }
        product.currentQuote = amount;
        product.quoteExpiration = block.timestamp + product.quotePeriod;
        emit QuoteSet(productId, amount);
    }

    /**
     * @dev Deposit tokens into the vault for a product in exchange for shares.
     * @param productId Unique ID for the product.
     * @param amount Amount of tokens to deposit.
     * @param expectedQuote The expected current quote.
     * @return The amount of shares minted.
     */
    function deposit(
        uint productId,
        uint amount,
        uint expectedQuote
    ) external nonReentrant whenNotStopped(productId) checkProductExistence(productId) returns (uint) {
        Product storage product = products[productId];
        require(block.timestamp >= product.startTime, "Not open yet");
        require(block.timestamp <= product.endTime, "Maturity reached");
        require(amount >= product.minDeposit, "Amount less than min deposit");
        require(product.currentQuote == expectedQuote, "Quote changed");
        require(block.timestamp <= product.quoteExpiration, "Quote expired");

        // Adjust amount to 18 decimals (shares have 18 decimals)
        uint adjustedAmount = amount * (10 ** (DECIMALS - product.tokenDecimals));

        // Now calculate the shares to mint based on the adjusted amount
        uint quantity = (adjustedAmount * product.currentQuote) / (10 ** DECIMALS);

        // Transfer tokens from sender to treasury
        IERC20(product.token).transferFrom(msg.sender, product.treasury, amount);

        // Mint share tokens to sender
        ShareToken(product.tokenShare).mint(msg.sender, quantity);
        product.totalShares += quantity;
        product.totalDeposits += amount;

        emit Deposit(productId, msg.sender, amount, quantity);
        emit SharesMinted(productId, msg.sender, quantity);

        return quantity;
    }

    /**
     * @dev Withdraw tokens from the vault for a product by burning shares.
     * @param productId Unique ID for the product.
     * @param amount Amount of shares to burn.
     * @return The amount of tokens withdrawn.
     */
    function withdraw(uint productId, uint amount) external nonReentrant checkProductExistence(productId) returns (uint) {
        Product storage product = products[productId];
        require(block.timestamp >= product.endTime, "Maturity not reached");
        require(product.availableRedemption > 0, "Redemption not set");
        require(product.totalShares > 0, "No shares available");

        // Transfer share tokens from sender to contract
        ShareToken shareToken = ShareToken(product.tokenShare);
        shareToken.transferFrom(msg.sender, address(this), amount);

        // Calculate the amount to withdraw
        uint assetAmount = (product.availableRedemption * amount) / product.totalShares;

        // Burn the shares
        shareToken.burn(address(this), amount);
        product.totalShares -= amount;

        // Update availableRedemption
        product.availableRedemption -= assetAmount;

        // Transfer tokens to sender
        IERC20(product.token).transfer(msg.sender, assetAmount);

        emit Withdraw(productId, msg.sender, amount, assetAmount);
        emit SharesBurned(productId, amount);

        return assetAmount;
    }

    /**
     * @dev Set the total amount available for redemption for a product.
     * @param productId Unique ID for the product.
     * @param amount Total amount available for redemption.
     */
    function setTotalRedemption(uint productId, uint amount) external onlyProductAdmin(productId) checkProductExistence(productId) {
        Product storage product = products[productId];
        require(block.timestamp >= product.endTime, "Maturity not reached");
        require(product.availableRedemption == 0, "Already set");

        // Transfer tokens from admin to contract
        IERC20(product.token).transferFrom(msg.sender, address(this), amount);

        product.availableRedemption = amount;
        emit AvailableRedemptionSet(productId, amount);
    }

    /**
     * @dev Change the treasury address for a product.
     * @param productId Unique ID for the product.
     * @param newTreasury The new treasury address.
     */
    function setTreasury(uint productId, address newTreasury) external onlyProductAdmin(productId) checkProductExistence(productId) {
        products[productId].treasury = newTreasury;
        emit TreasurySet(productId, newTreasury);
    }

    /**
     * @dev Change the admin address for a product.
     * @param productId Unique ID for the product.
     * @param newAdmin The new admin address.
     */
    function setAdmin(uint productId, address newAdmin) external onlyProductAdmin(productId) checkProductExistence(productId) {
        products[productId].admin = newAdmin;
        emit AdminChanged(productId, newAdmin);
    }

    // External read functions

    /**
     * @dev Get the total deposits for a product.
     * @param productId Unique ID for the product.
     * @return Total deposits.
     */
    function totalDeposit(uint productId) external view checkProductExistence(productId) returns (uint) {
        return products[productId].totalDeposits;
    }

    /**
     * @dev Get the available redemption amount for a product.
     * @param productId Unique ID for the product.
     * @return Available redemption amount.
     */
    function availableRedemption(uint productId) external view checkProductExistence(productId) returns (uint) {
        return products[productId].availableRedemption;
    }

    /**
     * @dev Get the total bonds (shares) for a product.
     * @param productId Unique ID for the product.
     * @return Total bonds.
     */
    function totalBonds(uint productId) external view checkProductExistence(productId) returns (uint) {
        return products[productId].totalShares;
    }

    /**
     * @dev Get the maturity time for a product.
     * @param productId Unique ID for the product.
     * @return Maturity timestamp.
     */
    function maturity(uint productId) external view checkProductExistence(productId) returns (uint) {
        return products[productId].endTime;
    }

    /**
     * @dev Get the admin address for a product.
     * @param productId Unique ID for the product.
     * @return Admin address.
     */
    function admin(uint productId) external view checkProductExistence(productId) returns (address) {
        return products[productId].admin;
    }

    /**
     * @dev Get the treasury address for a product.
     * @param productId Unique ID for the product.
     * @return Treasury address.
     */
    function treasuryAccount(uint productId) external view checkProductExistence(productId) returns (address) {
        return products[productId].treasury;
    }

    /**
     * @dev Get the bond token address for a product.
     * @param productId Unique ID for the product.
     * @return Bond token address.
     */
    function bondId(uint productId) external view checkProductExistence(productId) returns (address) {
        return products[productId].tokenShare;
    }
}
