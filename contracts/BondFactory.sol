// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./dependencies/Ownable.sol"; // for admin control
import "./dependencies/ERC20.sol"; // For ERC20 Token

/**
 * @title ShareToken (Bond)
 * @dev ERC20 Token that can be minted and burned by the Vault contract.
 */
contract ShareToken is ERC20 {
    address public vault;

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    /**
     * @dev Constructor for ShareToken.
     * @param name_ The name of the bond token.
     * @param symbol_ The symbol of the bond token.
     * @param vault_ The address of the vault contract.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address vault_
    ) ERC20(name_, symbol_) {
        vault = vault_;
    }

    /**
     * @dev Mint tokens to an address.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external override onlyVault {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from an address.
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external override onlyVault {
        _burn(from, amount);
    }
}

/**
 * @title BondFactory
 * @dev Factory contract to create new bond tokens.
 */
contract BondFactory is Ownable {
    // Array to keep track of all bonds created
    address[] public allBonds;

    event BondCreated(address indexed bondAddress, string name, string symbol, address vault);

    /**
     * @dev Creates a new bond (ShareToken).
     * @param name The name of the bond token.
     * @param symbol The symbol of the bond token.
     * @param vault The address of the vault contract.
     * @return bondAddress The address of the newly created bond token.
     */
    function createBond(
        string memory name,
        string memory symbol,
        address vault
    ) external onlyOwner returns (address bondAddress) {
        ShareToken bond = new ShareToken(name, symbol, vault);
        bondAddress = address(bond);
        allBonds.push(bondAddress);
        emit BondCreated(bondAddress, name, symbol, vault);
    }

    /**
     * @dev Returns the total number of bonds created.
     * @return Total number of bonds.
     */
    function totalBonds() external view returns (uint256) {
        return allBonds.length;
    }

    /**
     * @dev Returns the bond address at a specific index.
     * @param index The index of the bond in the array.
     * @return The bond address.
     */
    function getBond(uint256 index) external view returns (address) {
        require(index < allBonds.length, "Index out of bounds");
        return allBonds[index];
    }
}
