// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
* @dev Struct for initialization parameters.
*/
struct ProductParams {
    uint startTime;      // Start time for deposits.
    uint endTime;        // End time (maturity).
    uint minDeposit;     // Minimum deposit amount.
    uint quotePeriod;    // Duration for which the quote is valid.
    address custodian;   // Custodian address.
    address oracle;      // Oracle address.
}