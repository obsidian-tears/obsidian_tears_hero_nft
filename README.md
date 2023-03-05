# obsidian_tears_nft

This repo is responsible for holding the data of **Hero NFTs** of Obsidian Tears and handling any logic related to them.


### How to set environment
Please see "src/obsidian_tears_nft/env.mo" and change network variable.


### How to mint in local or staging
Your identity needs to be same as _minter (see Env.getAdminPrincipal()) and then execute a query like below:
```dfx canister call obsidian_tears_nft _mintAndTransferDevHero {Account Id to transfer to (not Principal!)}```