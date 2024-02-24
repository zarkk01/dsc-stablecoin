# DSC Foundry Solidity Project

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

You can see the deployed contract on the Sepolia Testnet at the following address: [0x848AAC46600B29F65Ab1ed32D6EBa08a1580Ce4c](https://sepolia.etherscan.io/address/0x848AAC46600B29F65Ab1ed32D6EBa08a1580Ce4c)
You can interact (mint, burn, deposit, redeem) with DSC using DSCEngine contract deployed at [OxbBB217768d1A2e1105ef867551B4e932B83e4DD3](https://sepolia.etherscan.io/address/OxbBB217768d1A2e1105ef867551B4e932B83e4DD3)

## Interaction

Having foundry installed you can interact with DSC using "cast" command. Don't forget to set up your .env file on root directory with your API key from [Alchemy](https://www.alchemy.com) and your private key.

## Testing

The system includes a comprehensive suite of tests to ensure its correct operation. These tests simulate user interactions with the system, such as depositing collateral, minting and burning DSC, and redeeming collateral.

## Contributing

Contributions are welcome. Please submit a pull request or create an issue to discuss the changes you want to make.
