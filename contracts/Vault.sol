// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // For reentrancy protection
import "@openzeppelin/contracts/access/Ownable.sol"; // For admin control
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol"; // Import ERC4626
import "@openzeppelin/contracts/utils/math/Math.sol"; // Import Math
import "./interfaces/IVault.sol"; // Interfaces and structs

/**
 * @title Vault
 * @dev A vault contract for managing a bond product.
 */
contract Vault is ERC4626, ReentrancyGuard, Ownable {
    using Math for uint256;
    /// @notice Decimals value (for shares and quotes)
    uint8 public constant DECIMALS = 18;
    /// @notice Invest token decimals
    uint8 public tokenDecimals;

    /// @notice Contract dev
    string public dev = "t.me/frankfourier";

    // Product properties
    /// @notice Custodian address
    address public _custodian;
    /// @notice Oracle address
    address public oracle;

    /// @notice Total deposits received
    uint private _totalDeposits;
    /// @notice Total amount available for redemption
    uint private _availableRedemption;
    /// @notice Current quote price
    uint private _currentQuote;

    /// @notice Start time for deposits
    uint public startTime;
    /// @notice End time (maturity)
    uint public endTime;
    /// @notice Quote expiration timestamp
    uint public quoteExpiration;
    /// @notice Duration for which the quote is valid
    uint public quotePeriod;
    /// @notice Minimum deposit amount
    uint public minDeposit;

    /// @notice Whether the product is initialized
    bool public initialized;
    /// @notice Whether the product is stopped
    bool public stopped;
    /// @notice Indicates if available redemption amount is set
    bool public availableRedemptionSet;

    /// @notice Event emitted when the product is initialized.
    event ProductInitialized(
        uint startTime,
        uint endTime
    );
    /// @notice Event emitted when the quote is set.
    event QuoteSet(uint amount);
    /// @notice Event emitted when the available redemption amount is set.
    event AvailableRedemptionSet(uint amount);
    /// @notice Event emitted when the custodian is set.
    event CustodianSet(address indexed newCustodian);
    /// @notice Event emitted when the contract is stopped.
    event ContractStopped(bool stopped);

    ////////// MODIFIERS ////////

    modifier whenNotStopped() {
        require(!stopped, "Contract is stopped");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, "Caller is not the oracle");
        _;
    }

    ////////// INITIALIZATION FUNCTIONS ////////

    /**
     * @dev Initializes the Vault contract with the specified asset, name, and symbol.
     * 
     * This constructor sets up the Vault contract by linking it to the specified asset, assigning a name and symbol to the Vault's ERC20 token, and ensuring that the asset's decimals do not exceed the maximum allowed (18).
     * 
     * @param asset_ The address of the ERC20 asset that this Vault will manage.
     * @param name_ The name of the ERC20 token that represents shares in this Vault.
     * @param symbol_ The symbol of the ERC20 token that represents shares in this Vault.
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
        // Fetch the token's decimals
        tokenDecimals = IERC20Metadata(asset()).decimals();

        // Ensure token decimals do not exceed 18
        require(tokenDecimals <= DECIMALS, "Token decimals cannot exceed 18");
    }

    /**
     * @dev Initialize the product.
     * @param params Struct containing initialization parameters.
     */
    function initializeProduct(ProductParams memory params) external onlyOwner {
        require(!initialized, "Product already initialized");

        oracle = params.oracle;
        startTime = params.startTime;
        endTime = params.endTime;
        minDeposit = params.minDeposit;
        quotePeriod = params.quotePeriod;
        _custodian = params.custodian;
        initialized = true;
        stopped = false;

        emit ProductInitialized(startTime, endTime);
    }

    ////////// READ FUNCTIONS ////////

    /**
     * @dev Returns the total amount of assets deposited.
     * @return Total deposited assets.
     */
    function totalAssets() public view override returns (uint) {
        return _totalDeposits;
    }

    /**
     * @dev Returns the available redemption amount if set.
     * @return Available redemption amount if set.
     */
    function availableRedemption() external view returns (uint) {
        require(availableRedemptionSet, "Available redemption not set");
        return _availableRedemption;
    }

    /**
     * @dev Returns the maturity timestamp.
     * @return Maturity timestamp.
     */
    function maturity() external view returns (uint) {
        return endTime;
    }

    /**
     * @dev Returns the custodian address.
     * @return Custodian address.
     */
    function custodianAccount() external view returns (address) {
        return _custodian;
    }

    ////////// QUOTE FUNCTIONS ////////

    /**
     * @dev Retrieves the current quote value. If the quote has expired, it returns zero.
     * 
     * This function checks the current block timestamp against the quote expiration timestamp. If the current timestamp is
     * less than or equal to the expiration timestamp, it returns the current quote value. Otherwise, it returns zero,
     * indicating that the quote has expired.
     * 
     * @return The current quote value if it is still valid, otherwise zero.
     */
    function quote() public view returns (uint) {
        if (block.timestamp <= quoteExpiration) {
            return _currentQuote;
        } else {
            return 0;
        }
    }

    /**
     * @dev Updates the current quote with a new value. This function can only be called by the oracle and when the contract is not stopped.
     * 
     * It first checks if the new quote amount is valid (greater than zero) and if the contract has not yet reached its maturity date.
     * Then, it verifies if there is a current quote that has not yet expired. If all conditions are met, it updates the current quote
     * with the new amount and sets a new expiration timestamp based on the current block timestamp and the quote period.
     * 
     * @param amount The new quote amount to be set.
     */
    function setQuote(uint amount) external onlyOracle whenNotStopped {
        require(amount > 0, "Invalid amount");
        require(block.timestamp < endTime, "Maturity reached, quote cannot be set anymore");

        if (_currentQuote != 0 && block.timestamp <= quoteExpiration) {
            revert("Quote still valid");
        }
        _currentQuote = amount;
        quoteExpiration = block.timestamp + quotePeriod;
        emit QuoteSet(amount);
    }

    ////////// DEPOSIT FUNCTIONS ////////

    /**
     * @dev Deposits assets into the vault in exchange for shares.
     * 
     * This function checks the deposit timing, amount, and quote validity before executing the deposit.
     * 
     * @param assets The amount of assets to deposit.
     * @param receiver The address to receive the minted shares.
     * @return The amount of shares minted.
     */
    function deposit(uint assets, address receiver) public virtual nonReentrant whenNotStopped override returns (uint) {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Invalid deposit timing");
        require(assets >= minDeposit, "Amount less than min deposit");
        require(block.timestamp <= quoteExpiration, "Quote expired");

        uint maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

     /**
     * @dev Enhanced deposit function with quote validation.
     * 
     * This function allows users to specify the expected quote to ensure it matches the current quote before proceeding with the deposit.
     * 
     * @param assets Amount of tokens to deposit.
     * @param expectedQuote The expected current quote, used for validation.
     * @param receiver The address to receive the minted shares.
     * @return The amount of shares minted.
     */
    function deposit(uint assets, uint expectedQuote, address receiver) public virtual nonReentrant whenNotStopped returns (uint) {
        // Validate deposit timing and amount
        require(block.timestamp >= startTime, "Not open yet");
        require(block.timestamp <= endTime, "Maturity reached");
        require(assets >= minDeposit, "Amount less than min deposit");
        // Validate quote
        require(_currentQuote == expectedQuote, "Quote changed");
        require(block.timestamp <= quoteExpiration, "Quote expired");

        // Check max deposit limit
        uint maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        // Calculate and mint shares
        uint shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    ////////// MINT FUNCTIONS ////////

    /**
     * @dev Mint function with basic validation.
     * 
     * This function allows users to mint shares with basic validation of timing and amount.
     * 
     * @param shares The amount of shares to mint.
     * @param receiver The address to receive the minted shares.
     * @return The amount of assets minted.
     */
    function mint(uint256 shares, address receiver) public virtual nonReentrant whenNotStopped override returns (uint) {
        require(block.timestamp >= startTime, "Not open yet");
        require(block.timestamp <= endTime, "Maturity reached");
        require(block.timestamp <= quoteExpiration, "Quote expired");

        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = previewMint(shares);
        require(assets >= minDeposit, "Amount less than min deposit");
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /**
     * @dev Mint function with quote validation.
     * 
     * This function allows users to specify the expected quote to ensure it matches the current quote before proceeding with the mint.
     * 
     * @param shares The amount of shares to mint.
     * @param expectedQuote The expected current quote, used for validation.
     * @param receiver The address to receive the minted shares.
     * @return The amount of assets minted.
     */
    function mint(uint256 shares, uint expectedQuote, address receiver) public virtual nonReentrant whenNotStopped returns (uint) {
        require(block.timestamp >= startTime, "Not open yet");
        require(block.timestamp <= endTime, "Maturity reached");
        require(_currentQuote == expectedQuote, "Quote changed");
        require(block.timestamp <= quoteExpiration, "Quote expired");

        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }

        uint256 assets = previewMint(shares);
        require(assets >= minDeposit, "Amount less than min deposit");
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    ////////// WITHDRAW FUNCTIONS ////////

    /**
     * @dev Withdraws assets from the vault by burning shares.
     * 
     * This function allows users to withdraw assets from the vault by burning their shares. It checks for maturity, available redemption, and total supply before proceeding.
     * 
     * @param assets The amount of assets to withdraw.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The address of the owner of the shares to be burned.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual nonReentrant override returns (uint) {
        require(block.timestamp >= endTime, "Maturity not reached");
        require(_availableRedemption > 0, "Redemption not set");
        require(totalSupply() > 0, "No shares available");

        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @dev Redeems shares for assets.
     * 
     * This function allows users to redeem their shares for assets. It checks for maturity, available redemption, and total supply before proceeding.
     * 
     * @param shares The amount of shares to redeem.
     * @param receiver The address to receive the redeemed assets.
     * @param owner The address of the owner of the shares to be redeemed.
     * @return The amount of assets redeemed.
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual nonReentrant override returns (uint256) {
        require(block.timestamp >= endTime, "Maturity not reached");
        require(_availableRedemption > 0, "Redemption not set");
        require(totalSupply() > 0, "No shares available");

        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    ////////// ADMIN FUNCTIONS ////////

    /**
     * @dev This function sets the stopped state of the contract. It can only be called by the owner of the contract.
     * 
     * @param _stopped A boolean value indicating the new stopped state of the contract. If true, the contract is stopped; otherwise, it is not stopped.
     */
    function setContractStopped(bool _stopped) external onlyOwner {
        stopped = _stopped;
        emit ContractStopped(_stopped);
    }

    /**
     * @dev Sets the total amount of assets available for redemption by users. This function can only be called by the owner of the contract.
     * 
     * This function updates the total amount of assets available for redemption by users. It first checks if the maturity time has been reached and if the available redemption amount has not been set before. 
     * Then, it transfers the specified amount of assets from the owner's address to the contract's address, effectively setting the available redemption amount. 
     * Finally, it emits an event to notify of the change.
     * 
     * @param amount The total amount of assets to be made available for redemption.
     */
    function setTotalRedemption(uint amount) external onlyOwner {
        require(block.timestamp >= endTime, "Maturity not reached");
        require(_availableRedemption == 0, "Already set");

        // Transfer tokens from admin to contract
        IERC20(asset()).transferFrom(msg.sender, address(this), amount);

        _availableRedemption = amount;
        availableRedemptionSet = true;
        emit AvailableRedemptionSet(amount);
    }

    /**
     * @dev Updates the address of the custodian responsible for managing the vault's assets. This function can only be called by the owner of the contract.
     * 
     * @param newCustodian The address of the new custodian.
     */
    function setCustodian(address newCustodian) external onlyOwner {
        _custodian = newCustodian;
        emit CustodianSet(newCustodian);
    }

    /**
     * @dev Updates the address of the oracle responsible for setting the quote. This function can only be called by the owner of the contract.
     * 
     * @param newOracle The address of the new oracle.
     */
    function setOracle(address newOracle) external onlyOwner {
        oracle = newOracle;
    }

    ////////// INTERNAL FUNCTIONS ////////

    /**
     * @dev Executes the common deposit/mint workflow.
     * 
     * This function verifies the allowance, transfers assets to the custodian, mints shares, updates total deposits, and emits a Deposit event.
     * 
     * @param caller The address initiating the deposit.
     * @param receiver The address to receive the minted shares.
     * @param assets The amount of assets to deposit.
     * @param shares The amount of shares to mint.
     */
    function _deposit(address caller, address receiver, uint assets, uint shares) internal virtual override {
        uint allowance = IERC20(asset()).allowance(caller, address(this));
        require(allowance >= assets, "Insufficient allowance");
        // Transfer tokens from sender to custodian
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, _custodian, assets);

        // Mint share tokens to sender
        _mint(receiver, shares);

        _totalDeposits += assets;
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Executes the common workflow for withdrawing/redeeming shares.
     * 
     * This function handles the logic for withdrawing assets from the vault by burning shares. It checks for allowance, burns shares, updates available redemption, transfers assets, and emits a Withdraw event.
     * 
     * @param caller The address initiating the withdrawal.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The address of the owner of the shares to be burned.
     * @param assets The amount of assets to be withdrawn.
     * @param shares The amount of shares to be burned.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);
        _availableRedemption -= assets;
        
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev Override the _decimalsOffset function to return the correct offset.
     * 
     * This function calculates the offset in the decimal representation between the underlying asset's decimals
     * and the vault decimals.
     * 
     * @return The calculated offset.
     */
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return DECIMALS - tokenDecimals;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     * @param assets The amount of assets to convert.
     * @param rounding The rounding direction to use.
     * @return The calculated amount of shares.
     */
    function _convertToShares(uint assets, Math.Rounding rounding) internal view virtual override returns (uint) {
        // Adjust amount to 18 decimals (shares have 18 decimals)
        uint adjustedAmount = assets * (10 ** (_decimalsOffset()));

        // Now calculate the shares to mint based on the adjusted amount
        return adjustedAmount.mulDiv(quote(), 10 ** DECIMALS, rounding);
    }

    /**
     * @dev This function converts a given amount of shares to assets, taking into account the rounding direction specified.
     * 
     * It first checks if the available redemption amount is greater than zero, ensuring that there are assets available for redemption.
     * Then, it calculates the equivalent asset amount for the given shares by dividing the available redemption amount by the total supply of shares,
     * applying the specified rounding direction to the result.
     * 
     * @param shares The amount of shares to convert to assets.
     * @param rounding The rounding direction to use for the conversion.
     * @return The calculated amount of assets equivalent to the given shares.
     */
    function _convertToAssets(uint shares, Math.Rounding rounding) internal view virtual override returns (uint) {
        require(_availableRedemption > 0, "AvailableRedemption must be greater than 0");
        return shares.mulDiv(_availableRedemption, totalSupply(), rounding);
    }

    ////////// HELPER FUNCTIONS ////////

    /**
     * @dev Preview mint amount based on shares.
     * @param shares Shares to mint.
     * @return Assets required for minting.
     */
    function previewMint(uint256 shares) public view virtual override returns (uint) {
        return shares.mulDiv(10 ** DECIMALS, quote(), Math.Rounding.Ceil) / 10 ** (_decimalsOffset());
    }

    /**
     * @dev Preview withdraw amount based on assets.
     * @param assets Assets to withdraw.
     * @return Shares to be withdrawn.
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint) {
        require(_availableRedemption > 0, "AvailableRedemption must be greater than 0");
        return assets.mulDiv(totalSupply(), _availableRedemption, Math.Rounding.Ceil);
    }
}
