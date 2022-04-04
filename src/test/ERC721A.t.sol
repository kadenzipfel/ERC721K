// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "../ERC721A.sol";

interface CheatCodes {
  function prank(address) external;
}

contract MockERC721A is ERC721A {
    constructor(string memory _name, string memory _symbol) ERC721A(_name, _symbol) {}

    function mint(address to, uint256 quantity, bytes memory _data, bool safe) external {
        _mint(to, quantity, _data, safe);
    }
}

contract ERC721ATest is DSTest {
    MockERC721A token;
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);

    function setUp() public {
        token = new MockERC721A("Token", "TKN");
    }

    function testMintOne() public {
        token.mint(address(0xBEEF), 1, '', false);
    }

    function testMintTen() public {
        token.mint(address(0xBEEF), 10, '', false);
    }

    function testSafeMintOne() public {
        token.mint(address(0xBEEF), 1, '', true);
    }

    function testSafeMintTen() public {
        token.mint(address(0xBEEF), 10, '', true);
    }
}
