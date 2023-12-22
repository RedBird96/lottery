# <h1 align="center"> Lottery Contract </h1>

![Github Actions](https://github.com/freezyex/LotteryContract-Foundry/workflows/test/badge.svg)
[![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
## DISCLAIMER
_This is my first time I use Foundry, so it is very likely that many things can be improved.  
These smart contracts are being provided as is. They have not been audited and as such there can be no assurance they will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk.
Feel free to contribute to the repo!_

## How does it work?
The contract uses a PRNG function to pick a winner from an array of players, as VRF wasn't necessary for the purpose of this project.  
To gurantee a 100% fairness, the admin must compute the [Keccak256](https://emn178.github.io/online-tools/keccak_256.html) hash of a random string off-chain and set it at the creation of each lottery. 
Once the hash for that lottery is set, it can't be changed. To provide more randomness, the admin can call the ``pickWinner()`` whenever he wants.
 

## Getting Started

```sh
forge init
forge build
forge test
```

## Development

This project uses [Foundry](https://getfoundry.sh). See the [book](https://book.getfoundry.sh/getting-started/installation.html) for instructions on how to install and use Foundry.
