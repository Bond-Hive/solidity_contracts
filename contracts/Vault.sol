// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // For reentrancy protection
import "@openzeppelin/contracts/access/Ownable.sol"; // For admin control
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol"; // Import ERC4626
import "@openzeppelin/contracts/utils/math/Math.sol"; // Import Math
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // Import SafeERC20 for safe token transfers
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

    // Total deposits received (internal use)
    uint private _totalDeposits;
    // Total amount available for redemption (internal use)
    uint private _availableRedemption;
    // Current quote price (internal use)
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

    /**
     * @notice Emitted when the product is initialized.
     * @param startTime The start time for deposits.
     * @param endTime The end time (maturity).
     */
    event ProductInitialized(
        uint startTime,
        uint endTime
    );

    /**
     * @notice Emitted when the quote is set.
     * @param amount The new quote amount.
     */
    event QuoteSet(uint amount);

    /**
     * @notice Emitted when the available redemption amount is set.
     * @param amount The total amount of available redemption.
     */
    event AvailableRedemptionSet(uint amount);

    /**
     * @notice Emitted when the custodian address is updated.
     * @param newCustodian The new custodian address.
     */
    event CustodianSet(address indexed newCustodian);

    /**
     * @notice Emitted when the contract's stopped state is updated.
     * @param stopped The new stopped state.
     */
    event ContractStopped(bool stopped);

    ////////// MODIFIERS ////////

    /**
     * @dev Modifier to ensure the contract is not stopped.
     */
    modifier whenNotStopped() {
        require(!stopped, "Contract is stopped");
        _;
    }

    /**
     * @dev Modifier to restrict function access to the designated oracle.
     */
    modifier onlyOracle() {
        require(msg.sender == oracle, "Caller is not the oracle");
        _;
    }

    ////////// CONSTRUCTOR ////////

    /**
     * @notice Constructor to initialize the Vault contract.
     * @param asset_ The address of the ERC20 asset that this Vault will manage.
     * @param name_ The name of the ERC20 token representing shares.
     * @param symbol_ The symbol of the ERC20 token representing shares.
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

    ////////// INITIALIZATION FUNCTION ////////

    /**
     * @notice Initializes the product.
     * @dev Can only be called by the owner and only once.
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
     * @notice Returns the total amount of assets deposited.
     * @return Total deposited assets.
     */
    function totalAssets() public view override returns (uint) {
        return _totalDeposits;
    }

    /**
     * @notice Returns the available redemption amount if set.
     * @return Available redemption amount.
     */
    function availableRedemption() external view returns (uint) {
        require(availableRedemptionSet, "Available redemption not set");
        return _availableRedemption;
    }

    /**
     * @notice Returns the maturity timestamp.
     * @return Maturity timestamp.
     */
    function maturity() external view returns (uint) {
        return endTime;
    }

    /**
     * @notice Returns the custodian address.
     * @return Custodian address.
     */
    function custodianAccount() external view returns (address) {
        return _custodian;
    }

    ////////// QUOTE FUNCTIONS ////////

    /**
     * @notice Retrieves the current quote value.
     * @dev Returns the current quote if still valid; otherwise, returns zero.
     * @return The current quote value if valid, or zero if expired.
     */
    function quote() public view returns (uint) {
        if (block.timestamp <= quoteExpiration) {
            return _currentQuote;
        } else {
            return 0;
        }
    }

    /**
     * @notice Updates the current quote with a new value.
     * @dev Can only be called by the oracle when the contract is not stopped and before maturity.
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
     * @notice Deposits assets into the vault in exchange for shares.
     * @dev Validates deposit timing, minimum amount, and quote validity before execution.
     * @param assets The amount of assets to deposit.
     * @param receiver The address to receive the minted shares.
     * @return The amount of shares minted.
     */
    function deposit(uint assets, address receiver) public virtual nonReentrant whenNotStopped override returns (uint) {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Invalid deposit timing");
        require(assets >= minDeposit, "Amount less than min deposit");
        require(block.timestamp <= quoteExpiration, "Quote expired");
        require(quote() > 0, "Quote not defined");

        uint maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    /**
     * @notice Deposits assets into the vault with quote validation.
     * @dev Allows users to specify an expected quote to ensure it matches the current quote before depositing.
     * @param assets Amount of tokens to deposit.
     * @param expectedQuote The expected current quote for validation.
     * @param receiver The address to receive the minted shares.
     * @return The amount of shares minted.
     */
    function deposit(uint assets, uint expectedQuote, address receiver) public virtual nonReentrant whenNotStopped returns (uint) {
        require(block.timestamp >= startTime, "Not open yet");
        require(block.timestamp <= endTime, "Maturity reached");
        require(assets >= minDeposit, "Amount less than min deposit");

        uint quoteValue = quote();
        require(quoteValue > 0, "Quote not defined");
        require(quoteValue == expectedQuote, "Quote changed");
        require(block.timestamp <= quoteExpiration, "Quote expired");

        uint maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    ////////// MINT FUNCTIONS ////////

    /**
     * @notice Mints shares by depositing the corresponding amount of assets.
     * @dev Validates timing, quote, and deposit minimum before minting.
     * @param shares The amount of shares to mint.
     * @param receiver The address to receive the minted shares.
     * @return The amount of assets deposited to mint the shares.
     */
    function mint(uint256 shares, address receiver) public virtual nonReentrant whenNotStopped override returns (uint) {
        require(block.timestamp >= startTime, "Not open yet");
        require(block.timestamp <= endTime, "Maturity reached");
        require(block.timestamp <= quoteExpiration, "Quote expired");
        require(quote() > 0, "Quote not defined");

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
     * @notice Mints shares with quote validation.
     * @dev Allows users to specify an expected quote to ensure it matches the current quote before minting.
     * @param shares The amount of shares to mint.
     * @param expectedQuote The expected current quote for validation.
     * @param receiver The address to receive the minted shares.
     * @return The amount of assets deposited to mint the shares.
     */
    function mint(uint256 shares, uint expectedQuote, address receiver) public virtual nonReentrant whenNotStopped returns (uint) {
        require(block.timestamp >= startTime, "Not open yet");
        require(block.timestamp <= endTime, "Maturity reached");

        uint quoteValue = quote();
        require(quoteValue > 0, "Quote not defined");
        require(quoteValue == expectedQuote, "Quote changed");
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
     * @notice Withdraws assets from the vault by burning shares.
     * @dev Can only be executed after maturity. Checks available redemption and share supply.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The owner of the shares to be burned.
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
     * @notice Redeems shares for assets.
     * @dev Can only be executed after maturity. Checks available redemption and share supply.
     * @param shares The amount of shares to redeem.
     * @param receiver The address to receive the redeemed assets.
     * @param owner The owner of the shares to be redeemed.
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
     * @notice Sets the stopped state of the contract.
     * @dev Can only be called by the owner.
     * @param _stopped Boolean indicating the new stopped state.
     */
    function setContractStopped(bool _stopped) external onlyOwner {
        stopped = _stopped;
        emit ContractStopped(_stopped);
    }

    /**
     * @notice Sets the total amount of assets available for redemption.
     * @dev Can only be called by the owner after maturity and if not already set. Transfers assets from the owner to the contract.
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
     * @notice Updates the custodian address.
     * @dev Can only be called by the owner.
     * @param newCustodian The address of the new custodian.
     */
    function setCustodian(address newCustodian) external onlyOwner {
        _custodian = newCustodian;
        emit CustodianSet(newCustodian);
    }

    /**
     * @notice Updates the oracle address.
     * @dev Can only be called by the owner.
     * @param newOracle The address of the new oracle.
     */
    function setOracle(address newOracle) external onlyOwner {
        oracle = newOracle;
    }

    ////////// INTERNAL FUNCTIONS ////////

    /**
     * @notice Executes the common deposit/mint workflow.
     * @dev Verifies allowance, transfers assets to the custodian, mints shares, updates total deposits, and emits a Deposit event.
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

        // Mint share tokens to receiver
        _mint(receiver, shares);

        _totalDeposits += assets;
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Executes the common workflow for withdrawing/redeeming shares.
     * @dev Handles allowance checking, burning shares, updating available redemption, transferring assets, and emitting a Withdraw event.
     * @param caller The address initiating the withdrawal.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The owner of the shares to be burned.
     * @param assets The amount of assets to withdraw.
     * @param shares The amount of shares to burn.
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
     * @notice Calculates the decimal offset between the underlying asset and the vault.
     * @dev Returns the difference between the constant DECIMALS and the token's decimals.
     * @return The calculated decimal offset.
     */
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return DECIMALS - tokenDecimals;
    }

    /**
     * @notice Converts a given amount of assets to shares.
     * @dev Adjusts for decimal differences and uses the current quote for conversion.
     * @param assets The amount of assets to convert.
     * @param rounding The rounding direction to use.
     * @return The calculated amount of shares.
     */
    function _convertToShares(uint assets, Math.Rounding rounding) internal view virtual override returns (uint) {
        // Adjust amount to 18 decimals (shares have 18 decimals)
        uint adjustedAmount = assets * (10 ** (_decimalsOffset()));

        // Check if the quote is defined
        require(quote() > 0, "Quote not defined");

        // Calculate the shares to mint based on the adjusted amount
        return adjustedAmount.mulDiv(quote(), 10 ** DECIMALS, rounding);
    }

    /**
     * @notice Converts a given amount of shares to assets.
     * @dev Uses the available redemption and total supply to determine the asset amount.
     * @param shares The amount of shares to convert.
     * @param rounding The rounding direction to use.
     * @return The calculated asset amount.
     */
    function _convertToAssets(uint shares, Math.Rounding rounding) internal view virtual override returns (uint) {
        require(_availableRedemption > 0, "AvailableRedemption must be greater than 0");
        return shares.mulDiv(_availableRedemption, totalSupply(), rounding);
    }

    ////////// HELPER FUNCTIONS ////////

    /**
     * @notice Previews the amount of assets required to mint a given number of shares.
     * @param shares The number of shares to mint.
     * @return The amount of assets required.
     */
    function previewMint(uint256 shares) public view virtual override returns (uint) {
        uint quoteValue = quote();
        require(quoteValue > 0, "Quote not defined");
        
        return shares.mulDiv(10 ** DECIMALS, quoteValue, Math.Rounding.Ceil) / 10 ** (_decimalsOffset());
    }

    /**
     * @notice Previews the number of shares that will be withdrawn for a given asset amount.
     * @param assets The amount of assets to withdraw.
     * @return The number of shares to be burned.
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint) {
        require(_availableRedemption > 0, "AvailableRedemption must be greater than 0");
        return assets.mulDiv(totalSupply(), _availableRedemption, Math.Rounding.Ceil);
    }
}
