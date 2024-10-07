// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC-20 standard.
 */
interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/**
* @dev Product struct to hold product-specific data.
*/
struct Product {
    address token;             // Underlying ERC20 token address
    address tokenShare;        // Bond token (ShareToken) address
    address admin;             // Admin address for the product
    uint startTime;            // Start time for deposits
    uint endTime;              // End time (maturity)
    uint totalShares;          // Total shares issued
    uint totalDeposits;        // Total deposits received
    uint availableRedemption;  // Total amount available for redemption
    uint currentQuote;         // Current quote price
    uint quoteExpiration;      // Quote expiration timestamp
    uint quotePeriod;          // Duration for which the quote is valid
    address treasury;          // Treasury address
    uint minDeposit;           // Minimum deposit amount
    bool initialized;          // Whether the product is initialized
    bool stopped;              // Whether the product is stopped
    uint tokenDecimals;        // Invest token decimals
}

/**
* @dev Struct for initialization parameters.
*/
struct ProductParams {
    address token;       // The bond address.
    address admin;       // Admin address for the product.
    uint startTime;      // Start time for deposits.
    uint endTime;        // End time (maturity).
    uint quotePeriod;    // Duration for which the quote is valid.
    address treasury;    // Treasury address.
    uint minDeposit;     // Minimum deposit amount.
    string bondName;     // Name of the bond token.
    string bondSymbol;   // Symbol of the bond token.
}