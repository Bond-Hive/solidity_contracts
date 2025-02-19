
# BondHive Smart Contract

Welcome to the official Solidity smart contract repository for **BondHive**, a decentralized platform offering on-chain bonds built on Ethereum. This repository contains the core smart contracts that manage the bond issuance, purchasing, and redemption processes in a trustless and transparent manner.

BondHive enables users to issue, purchase, and claim fixed yield bonds on the Ethereum blockchain, ensuring security and decentralization.

This contract adheres to the ERC4626 standard to provide a smooth user experience and compatibility within the EVM ecosystem, ensuring compliance with established standards. The exchange rate in this contract is fixed and cannot be manipulated, as it is determined by an external quote provided by an oracle. The goal is to have a fully decentralized oracle to minimize trust issues; however, if that is not achieved, a trust assumption must be made.

## Overview

BondHive empowers users to:

- **Issue bonds**: Create bonds with predefined terms such as fixed interest rates and maturity dates.
- **Purchase bonds**: Allow investors to buy bonds and receive fixed returns at the end of the bond term.
- **Claim yields**: Bondholders can redeem their principal and accumulated interest upon bond maturity.

## Key Features

- **Fixed Yield Bonds**: Each bond guarantees a fixed interest rate, offering predictable and secure returns.
- **Quote Management**: The quote must be available in the smart contract before a user can deposit. It has a limited validity period, meaning it must be updated once expired before allowing further deposits. Users can utilize the `previewDeposit` function at any time to assess how many bonds they will receive based on a specific USDC amount deposited. The quote can be verified by users as it fetches Binance Spot and delivery futures prices for the underlying bond pair.
- **Asset Management**: Since assets are held in a custodian wallet and some are invested, the actual amount of deposited assets is used instead of the current balance to measure the total assets amount.
- **Decentralized and Trustless**: Bond issuance and redemption are fully handled by smart contracts, eliminating intermediaries and enhancing security.
- **On-Chain Transactions**: All bond data and transactions are stored on the Ethereum blockchain, ensuring transparency and immutability.
- **Open-Source Codebase**: Our contracts are open for public review and contribution.

## Getting Started

### Prerequisites
- Solidity ^0.8.x
- Node.js and npm
- Hardhat or Truffle for contract deployment and testing

### Installation

Clone the repo and install dependencies:

\`\`\`bash
git clone https://github.com/BondHive/bondhive-solidity.git
cd bondhive-solidity
npm install
\`\`\`

### Compilation & Deployment

Compile the smart contracts:

\`\`\`bash
npx hardhat compile
\`\`\`

Deploy to your preferred network (make sure you configure the networks in \`hardhat.config.js\`):

\`\`\`bash
npx hardhat run scripts/deploy.js --network <network_name>
\`\`\`

### Testing

Run the tests to ensure everything is working correctly:

\`\`\`bash
npx hardhat test
\`\`\`

---

## Contributing

We welcome contributions from the community. Please feel free to open issues or submit pull requests.

---

## License

This project is licensed under the MIT License.
