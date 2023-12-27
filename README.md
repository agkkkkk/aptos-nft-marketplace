# NFT Marketplace


## Features

- [x] List Tokens
- [x] Delist Tokens
- [x] Buy listed tokens
- [x] Initialize token auction
- [x] Bid for tokens
- [x] Cancel auction
- [x] Claim auctioned token

## Getting Started

NOTE: To run the program tou need to have aptos CLI installed.

### Installation

1. Clone the repository

```bash
git clone https://github.com/agkkkkk/aptos-nft-marketplace.git
```
2. Go to the project directory and initialize aptos account and update ```Move.toml```

```bash
cd aptos-nft-marketplace
aptos init
```

3. Compile the module:

```bash
aptos move compile --named-addresses marketplace=<MARKETPLACE-ADDRESS>,owner=<OWNER-ADDRESS>,treasury=<TREASURY-ADDRESS>
```

4. Publish module

```bash
aptos move publish --named-addresses marketplace=<MARKETPLACE-ADDRESS>,owner=<OWNER-ADDRESS>,treasury=<TREASURY-ADDRESS>
```
Example:
```bash
aptos move publish --named-addresses marketplace=0x5d862ec05d9a74478f08a0143d8de3d108c307f61d4f7f1411384553f6c27d55,owner=0xd4f2987ce525ae600629615e95933b38167bf7bfafa265c572acdca1c095fdad, treasury=0x0392550f2cc8f687db3518f54c1b7b201d3ba00d3199f11d1ea6a3c336778e5f
```

5. Run Function

FUNCTION-ID:- <module_address>::<module_name>::<function_name>

```bash
aptos move run --funtion-id <FUNCTION-ID> --args <ARG>
```
