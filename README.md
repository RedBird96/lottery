# <h1 align="center"> Lottery Contract </h1>

## How does it work?
The contract uses a PRNG function to pick a winner from an array of players

To gurantee a 100% fairness, the admin must compute the [Keccak256](https://emn178.github.io/online-tools/keccak_256.html) hash of a random string off-chain and set it at the creation of each lottery. 
Once the hash for that lottery is set, it can't be changed. To provide more randomness, the admin can call the ``pickWinner()`` whenever he wants.
 

## Getting Started

```sh
forge init
forge build
forge test
```

## Development

```sh
forge script LotteryScript -s "deployTest()" --force --broadcast --verify
```