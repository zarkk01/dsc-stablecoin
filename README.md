# Foundry Solidity Project

This project demonstrates a stablecoin system that is algorithmically controlled, backed by exogenous collateral (ETH and BTC), and pegged to the USD.

## Overview

The system uses a Decentralized Stable Coin (DSC) which follows ERC20 token standards. The DSC is minted and burned algorithmically to maintain its peg to the USD. The system is overcollateralized with ETH and BTC to ensure stability.

## Key Components

- **DecentralizedStableCoin (DSC)**: This is the stablecoin that is pegged to the USD. It is an ERC20 token that can be minted and burned which inherits from OpenZeppelin's ERC20Burnable and Owanable contracts.

- **DSCEngine**: This contract manages the minting and burning of DSC. It also handles the deposit and redemption of collateral.

- **Handler**: This contract is used for testing the system. It simulates user interactions with the system.

- **InvariantsTest**: This contract tests the invariants of the DSCEngine contract.

## Setup

1. Clone the repository
2. Compile the contracts with `forge build`
3. Run the tests with `forge test`
4. Deploy the contracts on a real network is not recommended, since the system is not production-ready and not audited.

## Deployment

You can see the deployed contract on the Sepolia Testnet at the following address: [0xCF4A0A901C3F7A4a173FC38C48bEc9a9bF7F5a20](https://sepolia.etherscan.io/address/0xCF4A0A901C3F7A4a173FC38C48bEc9a9bF7F5a20)

## Testing

The system includes a comprehensive suite of tests to ensure its correct operation. These tests simulate user interactions with the system, such as depositing collateral, minting and burning DSC, and redeeming collateral.

## Contributing

Contributions are welcome. Please submit a pull request or create an issue to discuss the changes you want to make.