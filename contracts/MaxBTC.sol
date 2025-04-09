// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // For reentrancy protection
import "@openzeppelin/contracts/access/Ownable.sol"; // For admin control
import "@openzeppelin/contracts/utils/math/Math.sol"; // Import Math
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // Import SafeERC20 for safe token transfers
import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // Import ERC20 for token creation
import "./interfaces/IMaxBTC.sol"; // Interfaces and structs

/**
 * @title MaxBTC
 * @dev A perpetual yield-bearing vault contract for managing MaxBTC product with multiple assets.
 */
contract MaxBTC is ERC20, ReentrancyGuard, Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    /// @notice Decimals value (for MaxBTC and quotes)
    uint8 public constant DECIMALS = 18;

    /// @notice Contract dev
    string public dev = "t.me/frankfourier";

    // Product properties
    /// @notice Custodian address
    address public _custodian; // TODO custodians this needs to be set for each ERC20 and even allow multiple custodians to be set for each asset
    /// @notice Oracle address
    address public oracle; // TODO this needs to be set for each ERC20 asset probably so allow multiple oracles to be set for each asset, so also this should be per asset

     // Supported assets
    /// @notice List of supported asset addresses
    address[] public supportedAssets;
    /// @notice Mapping to check if an asset is supported
    mapping(address => bool) public isAssetSupported;
    /// @notice Mapping of asset address to its decimals
    mapping(address => uint8) public assetDecimals;
    /// @notice Mapping of asset address to minimum deposit amount
    mapping(address => uint256) public minDeposit;

    // Quote system
    /// @notice Duration for which quotes are valid
    uint public quotePeriod; // TODO also this needs to be a mapping
    /// @notice Mapping of asset address to current quote
    mapping(address => uint256) private _currentQuotes;
    /// @notice Mapping of asset address to quote expiration timestamp
    mapping(address => uint256) public quoteExpirations;

    // Total deposits by asset
    /// @notice Mapping of asset address to total deposits
    mapping(address => uint256) private _totalDeposits;

    /// @notice Whether the product is initialized
    bool public initialized;
    /// @notice Whether the product is stopped
    bool public stopped;

    /**
     * @notice Emitted when the product is initialized.
     */
    event ProductInitialized();

    /**
     * @notice Emitted when a new asset is added.
     * @param asset The address of the added asset.
     * @param minDepositAmount The minimum deposit amount for this asset.
     */
    event AssetAdded(address indexed asset, uint256 minDepositAmount);

    /**
     * @notice Emitted when a deposit is made.
     * @param asset The address of the deposited asset.
     * @param caller The address that initiated the deposit.
     * @param receiver The address that received the MaxBTC tokens.
     * @param assets The amount of assets deposited.
     * @param shares The amount of MaxBTC tokens minted.
     */
    event Deposit(address indexed asset, address indexed caller, address indexed receiver, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when a withdrawal is made.
     * @param asset The address of the withdrawn asset.
     * @param caller The address that initiated the withdrawal.
     * @param receiver The address that received the assets.
     * @param owner The address that owned the MaxBTC tokens.
     * @param assets The amount of assets withdrawn.
     * @param shares The amount of MaxBTC tokens burned.
     */
    event Withdraw(address indexed asset, address indexed caller, address indexed receiver, address owner, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when the quote is set for an asset.
     * @param asset The address of the asset.
     * @param amount The new quote amount.
     */
    event QuoteSet(address indexed asset, uint amount);

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

    /**
     * @dev Modifier to ensure the asset is supported.
     */
    modifier onlySupportedAsset(address asset) {
        require(isAssetSupported[asset], "Asset not supported");
        _;
    }

    ////////// CONSTRUCTOR ////////

    /**
     * @notice Constructor to initialize the MaxBTC contract.
     * @param name_ The name of the ERC20 token representing MaxBTC.
     * @param symbol_ The symbol of the ERC20 token representing MaxBTC.
     */
    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        // Set default decimals to 18
        _setupDecimals(DECIMALS);
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

    ////////// ASSET MANAGEMENT ////////

    /**
     * @notice Adds a new supported asset.
     * @dev Can only be called by the owner.
     * @param asset The address of the asset to add.
     * @param minDepositAmount The minimum deposit amount for this asset.
     */
    function addAsset(address asset, uint256 minDepositAmount) external onlyOwner {
        require(!isAssetSupported[asset], "Asset already supported");
        require(asset != address(0), "Invalid asset address");
        
        uint8 decimals = IERC20Metadata(asset).decimals();
        require(decimals <= DECIMALS, "Asset decimals cannot exceed 18");
        
        supportedAssets.push(asset);
        isAssetSupported[asset] = true;
        assetDecimals[asset] = decimals;
        minDeposit[asset] = minDepositAmount;
        
        emit AssetAdded(asset, minDepositAmount);
    }

    /**
     * @notice Returns the list of supported assets.
     * @return Array of supported asset addresses.
     */
    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    ////////// READ FUNCTIONS ////////

    /**
     * @notice Returns the total amount of a specific asset deposited.
     * @param asset The address of the asset.
     * @return Total deposited amount of the asset.
     */
    function totalAssets(address asset) public view onlySupportedAsset(asset) returns (uint) {
        return _totalDeposits[asset];
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
     * @notice Retrieves the current quote value for a specific asset.
     * @dev Returns the current quote if still valid; otherwise, returns zero.
     * @param asset The address of the asset.
     * @return The current quote value if valid, or zero if expired.
     */
    function quote(address asset) public view onlySupportedAsset(asset) returns (uint) {
        if (block.timestamp <= quoteExpirations[asset]) {
            return _currentQuotes[asset];
        } else {
            return 0;
        }
    }

    /**
     * @notice Updates the current quote with a new value for a specific asset.
     * @dev Can only be called by the oracle when the contract is not stopped.
     * @param asset The address of the asset.
     * @param amount The new quote amount to be set.
     */
    function setQuote(address asset, uint amount) external onlyOracle whenNotStopped onlySupportedAsset(asset) {
        require(amount > 0, "Invalid amount");

        if (_currentQuotes[asset] != 0 && block.timestamp <= quoteExpirations[asset]) {
            revert("Quote still valid");
        }
        _currentQuotes[asset] = amount;
        quoteExpirations[asset] = block.timestamp + quotePeriod;
        emit QuoteSet(asset, amount);
    }

    ////////// DEPOSIT FUNCTIONS ////////

    /**
     * @notice Deposits assets into the vault in exchange for MaxBTC tokens.
     * @dev Validates deposit timing, minimum amount, and quote validity before execution.
     * @param assets The amount of assets to deposit.
     * @param receiver The address to receive the minted MaxBTC.
     * @return The amount of MaxBTC minted.
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

        uint amount = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, amount);

        return amount;
    }

    /**
     * @notice Deposits assets into the vault with quote validation.
     * @dev Allows users to specify an expected quote to ensure it matches the current quote before depositing.
     * @param assets Amount of tokens to deposit.
     * @param expectedQuote The expected current quote for validation.
     * @param receiver The address to receive the minted MaxBTC.
     * @return The amount of MaxBTC minted.
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

        uint amount = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, amount);

        return amount;
    }

    ////////// MINT FUNCTIONS ////////

    /**
     * @notice Mints MaxBTC by depositing the corresponding amount of assets.
     * @dev Validates timing, quote, and deposit minimum before minting.
     * @param amount The amount of MaxBTC to mint.
     * @param receiver The address to receive the minted MaxBTC.
     * @return The amount of assets deposited to mint MaxBTC tokens.
     */
    function mint(uint256 amount, address receiver) public virtual nonReentrant whenNotStopped override returns (uint) {
        require(block.timestamp >= startTime, "Not open yet");
        require(block.timestamp <= endTime, "Maturity reached");
        require(block.timestamp <= quoteExpiration, "Quote expired");
        require(quote() > 0, "Quote not defined");

        uint256 maxAmount = maxMint(receiver);
        if (amount > maxAmount) {
            revert ERC4626ExceededMaxMint(receiver, amount, maxAmount);
        }

        uint256 assets = previewMint(amount);
        require(assets >= minDeposit, "Amount less than min deposit");
        _deposit(_msgSender(), receiver, assets, amount);

        return assets;
    }

    /**
     * @notice Mints MaxBTC tokens with quote validation.
     * @dev Allows users to specify an expected quote to ensure it matches the current quote before minting.
     * @param amount The amount of MaxBTC tokens to mint.
     * @param expectedQuote The expected current quote for validation.
     * @param receiver The address to receive the minted MaxBTC tokens.
     * @return The amount of assets deposited to mint the MaxBTC tokens.
     */
    function mint(uint256 amount, uint expectedQuote, address receiver) public virtual nonReentrant whenNotStopped returns (uint) {
        require(block.timestamp >= startTime, "Not open yet");
        require(block.timestamp <= endTime, "Maturity reached");

        uint quoteValue = quote();
        require(quoteValue > 0, "Quote not defined");
        require(quoteValue == expectedQuote, "Quote changed");
        require(block.timestamp <= quoteExpiration, "Quote expired");

        uint256 maxAmount = maxMint(receiver);
        if (amount > maxAmount) {
            revert ERC4626ExceededMaxMint(receiver, amount, maxAmount);
        }

        uint256 assets = previewMint(amount);
        require(assets >= minDeposit, "Amount less than min deposit");
        _deposit(_msgSender(), receiver, assets, amount);

        return assets;
    }

    ////////// WITHDRAW FUNCTIONS ////////

    /**
     * @notice Withdraws assets from the vault by burning tokens.
     * @dev Can only be executed after maturity. Checks available redemption and share supply.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The owner of the MaxBTC tokens to be burned.
     * @return The amount of MaxBTC tokens burned.
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual nonReentrant override returns (uint) {
        require(block.timestamp >= endTime, "Maturity not reached");
        require(_availableRedemption > 0, "Redemption not set");
        require(totalSupply() > 0, "No MaxBTC tokens available");

        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 amount = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, amount);

        return amount;
    }

    /**
     * @notice Redeems MaxBTC tokens for assets.
     * @dev Can only be executed after maturity. Checks available redemption and share supply.
     * @param amount The amount of MaxBTC tokens to redeem.
     * @param receiver The address to receive the redeemed assets.
     * @param owner The owner of the MaxBTC tokens to be redeemed.
     * @return The amount of assets redeemed.
     */
    function redeem(uint256 amount, address receiver, address owner) public virtual nonReentrant override returns (uint256) {
        require(block.timestamp >= endTime, "Maturity not reached");
        require(_availableRedemption > 0, "Redemption not set");
        require(totalSupply() > 0, "No MaxBTC tokens available");

        uint256 maxAmount = maxRedeem(owner);
        if (amount > maxAmount) {
            revert ERC4626ExceededMaxRedeem(owner, amount, maxAmount);
        }

        uint256 assets = previewRedeem(amount);
        _withdraw(_msgSender(), receiver, owner, assets, amount);

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
     * @notice Updates the minimum deposit amount for an asset.
     * @dev Can only be called by the owner.
     * @param asset The address of the asset.
     * @param amount The new minimum deposit amount.
     */
    function setMinDeposit(address asset, uint256 amount) external onlyOwner onlySupportedAsset(asset) {
        minDeposit[asset] = amount;
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
     * @dev Verifies allowance, transfers assets to the custodian, mints MaxBTC tokens, updates total deposits, and emits a Deposit event.
     * @param caller The address initiating the deposit.
     * @param receiver The address to receive the minted MaxBTC tokens.
     * @param assets The amount of assets to deposit.
     * @param amount The amount of MaxBTC tokens to mint.
     */
    function _deposit(address caller, address receiver, uint assets, uint amount) internal virtual override {
        uint allowance = IERC20(asset()).allowance(caller, address(this));
        require(allowance >= assets, "Insufficient allowance");
        // Transfer tokens from sender to custodian
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, _custodian, assets);

        // Mint share tokens to receiver
        _mint(receiver, amount);

        _totalDeposits += assets;
        emit Deposit(caller, receiver, assets, amount);
    }

    /**
     * @notice Executes the common workflow for withdrawing/redeeming MaxBTC tokens.
     * @dev Handles allowance checking, burning MaxBTC tokens, updating available redemption, transferring assets, and emitting a Withdraw event.
     * @param caller The address initiating the withdrawal.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The owner of the MaxBTC tokens to be burned.
     * @param assets The amount of assets to withdraw.
     * @param amount The amount of MaxBTC tokens to burn.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 amount
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, amount);
        }

        _burn(owner, amount);
        _availableRedemption -= assets;
        
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);
                IERC20(asset).safeTransferFrom(caller, _custodian, assets);


        emit Withdraw(caller, receiver, owner, assets, amount);
    }

    /**
     * @notice Calculates the decimal offset between the underlying asset and MaxBTC tokens.
     * @dev Returns the difference between the constant DECIMALS and the token's decimals.
     * @return The calculated decimal offset.
     */
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return DECIMALS - tokenDecimals;
    }

    /**
     * @notice Calculates the decimal offset between an asset and MaxBTC tokens.
     * @param asset The address of the asset.
     * @return The calculated decimal offset.
     */
    function _getDecimalsOffset(address asset) internal view returns (uint8) {
        return DECIMALS - assetDecimals[asset];
    }

    /**
     * @notice Converts a given amount of assets to MaxBTC tokens.
     * @dev Adjusts for decimal differences and uses the current quote for conversion.
     * @param assets The amount of assets to convert.
     * @param rounding The rounding direction to use.
     * @return The calculated amount of MaxBTC tokens.
     */
    function _convertToShares(uint assets, Math.Rounding rounding) internal view virtual override returns (uint) {
        // Adjust amount to 18 decimals (MaxBTC tokens have 18 decimals)
        uint adjustedAmount = assets * (10 ** (_decimalsOffset()));

        // Check if the quote is defined
        require(quote() > 0, "Quote not defined");

        // Calculate the MaxBTC tokens to mint based on the adjusted amount
        return adjustedAmount.mulDiv(quote(), 10 ** DECIMALS, rounding);
    }

    /**
     * @notice Converts a given amount of MaxBTC tokens to assets.
     * @dev Uses the available redemption and total supply to determine the asset amount.
     * @param amount The amount of MaxBTC tokens to convert.
     * @param rounding The rounding direction to use.
     * @return The calculated asset amount.
     */
    function _convertToAssets(uint amount, Math.Rounding rounding) internal view virtual override returns (uint) {
        require(_availableRedemption > 0, "AvailableRedemption must be greater than 0");
        return amount.mulDiv(_availableRedemption, totalSupply(), rounding);
    }

    function _convertToAssets(address asset, uint shares) internal view returns (uint) {
        // Check if the quote is defined
        uint quoteValue = quote(asset);
        require(quoteValue > 0, "Quote not defined");

        // Calculate the asset amount based on the shares
        uint adjustedAmount = shares * (10 ** DECIMALS) / quoteValue;
        
        // Adjust back to asset decimals
        return adjustedAmount / (10 ** (_getDecimalsOffset(asset)));
    }

    ////////// HELPER FUNCTIONS ////////

    /**
     * @notice Previews the amount of assets required to mint a given number of MaxBTC tokens.
     * @param amount The number of MaxBTC tokens to mint.
     * @return The amount of assets required.
     */
    function previewMint(uint256 amount) public view virtual override returns (uint) {
        uint quoteValue = quote();
        require(quoteValue > 0, "Quote not defined");
        
        return amount.mulDiv(10 ** DECIMALS, quoteValue, Math.Rounding.Ceil) / 10 ** (_decimalsOffset());
    }

    /**
     * @notice Previews the number of MaxBTC tokens that will be withdrawn for a given asset amount.
     * @param assets The amount of assets to withdraw.
     * @return The number of MaxBTC tokens to be burned.
     */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint) {
        require(_availableRedemption > 0, "AvailableRedemption must be greater than 0");
        return assets.mulDiv(totalSupply(), _availableRedemption, Math.Rounding.Ceil);
    }
}
