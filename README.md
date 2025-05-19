# IDO-Pools-Foundry

## Overview

A sophisticated Initial DEX Offering (IDO) platform built with Foundry, featuring an upgradeable architecture using the Transparent Proxy pattern. This project implements a comprehensive system for token sales with tiered participation, customizable allocation multipliers, and robust administrative controls.

## What is an IDO?

An Initial DEX Offering (IDO) is a fundraising method in which a project launches a new token through a decentralized liquidity exchange. This platform enhances the traditional IDO model by introducing:

- **Hierarchical organization** with MetaIDOs grouping multiple IDO rounds
- **Rank-based participation** with customizable eligibility requirements
- **Multiplier system** for allocation amounts based on user characteristics
- **Timelock mechanisms** for administrative actions

## Architecture

The project employs a modular, upgradeable architecture:

```
StandardIDOPool (Upgradeable Entry Point)
├── IDOPoolAbstract (Core Implementation)
│   ├── IDOStorage (State Variables)
│   ├── IDOPoolView (Read-Only Functions)
│   ├── BlastYieldAbstract (Yield Management)
│   └── IDOStructs (Data Structures)
└── MultiplierContract (External Dependency)
```

### Key Components

- **StandardIDOPool**: Thin upgradeable contract inheriting all functionality from abstracts
- **IDOPoolAbstract**: Core business logic for IDO creation, participation and claiming
- **MultiplierContract**: Manages user levels, ranks, and multipliers based on staked amounts
- **MetaIDO**: Logical grouping of IDO rounds with shared registration period
- **IDO Rounds**: Individual token sales with specific parameters and configurations

## Features

- **Upgradeability**: Transparent proxy pattern allows for contract upgrades while preserving state
- **Tiered Participation**: Configure rank-based eligibility requirements for each IDO round
- **Allocation System**: Dynamic allocation limits based on user multipliers
- **Administrative Controls**: Comprehensive admin functions with timelock safety mechanisms
- **Registration Management**: Customizable registration windows with admin override capabilities
- **Token Management**: Support for both standard buy tokens and yield-generating (FY) tokens
- **Blast Integration**: Native support for Blast protocol yield generation

## Installation and Setup

This project uses Foundry for development and testing. To get started:

```bash
# Clone the repository
git clone https://github.com/yourusername/Ido-Pools-Foundry.git
cd Ido-Pools-Foundry

# Install dependencies
forge install

# Compile contracts
forge build

# Run tests
forge test
```

### Deployment

The project includes deployment scripts for both initial deployment and upgrades:

```bash
# Initial deployment
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>

# Upgrade existing implementation
forge script script/Upgrade.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Testing

The project features a comprehensive test suite covering various aspects of functionality:
See the README.md in the test folder for more information.

- **Admin Tests**: Verifies administrative functions and access control
- **User Tests**: Tests participant interactions like registration and contribution
- **View Tests**: Validates data retrieval and calculation functions
- **Advanced Tests**: Edge cases, gas optimization, and stress testing
- **Failure Tests**: Ensures proper error handling and input validation
