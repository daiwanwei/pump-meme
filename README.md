# PumpMeme: Decentralized Meme Launchpad
PumpMeme is an innovative platform built on Uniswap V4, designed to empower creators and communities to launch and trade meme assets effortlessly. With a unique virtual curve pricing mechanism and automatic deployment to Uniswap V2 pools, PumpMeme provides an engaging, efficient, and incentivized trading experience.

## Features
- Pre-launch Trading: Buy and sell meme assets freely before they officially launch.
- Dynamic Pricing: Meme prices are determined by a virtual curve based on trading activity.
- Auto-Launch Mechanism: Meme assets automatically deploy to Uniswap V2 pools when purchase volume and transaction thresholds are met.
- Incentivized Trading: A portion of funds is donated to the most active Uniswap V4 pool to encourage liquidity and participation.
## How It Works
### Pre-launch Stage:

Meme assets are available for buying and selling.
Prices adjust dynamically via the virtual curve mechanism.
### Launch Trigger:

When the defined trading volume and transaction count thresholds are met, the platform automatically migrates the meme asset to a Uniswap V2 pool.
### Incentives Distribution:

To boost activity, a portion of funds is donated to the Uniswap V4 pool with the highest trading volume.
## Tech Stack
### Blockchain Protocols:
- Uniswap V4
- Uniswap V2: For post-launch liquidity pools.
### Smart Contracts:
Developed in Solidity to manage trading, pricing, and fund distribution.

## Installation
Clone the repository:

```bash
git clone https://github.com/daiwanwei/pump-meme.git
cd pump-meme
```

## Set up

*requires [foundry](https://book.getfoundry.sh)*

```
forge install
forge test --fork-url <your-mainnet-rpc-url>
```