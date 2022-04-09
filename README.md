# ERC721K

ERC721K is a maximally efficient, minimalist ERC-721 implementation. Inspired by [solmate/ERC721](https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)'s minimalist architecture and forked from [ERC721A](https://github.com/chiru-labs/ERC721A), the contract seeks to reduce ERC721 gas costs as much as possible.

### Gas

With ERC721K's gas costs being up to 30% cheaper than that of ERC721A's already astonishingly well optimized contract, it may be the most optimized ERC721 contract ever written. See compared gas costs below.

| Number Minted | ERC721Enumerable | ERC721A | ERC721K |
| ------------- | ---------------- | ------- | ------- |
| 1             | 154,814          | 68,473  | 48,561  |
| 2             | 270,339          | 70,238  | 50,326  |
| 3             | 384,864          | 72,003  | 52,091  |
| 4             | 501,389          | 73,768  | 53,856  |
| 5             | 616,914          | 75,533  | 55,621  |

### Security

Though **this contract has not been professionally audited**, it has a strong [test suite](https://github.com/kadenzipfel/ERC721K/blob/main/src/test/ERC721K.t.sol) forked from [solmate](https://github.com/Rari-Capital/solmate/blob/main/src/test/ERC721.t.sol).

![tests](tests.png)

### Contributions

I intend to keep this repository active and to continually improve upon the code. If you see any possible improvement, please submit a pull request.

### Disclaimer

This contract has not been professionally audited. By using this contract in any way you assume all risks and liability.
