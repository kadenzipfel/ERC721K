// SPDX-License-Identifier: AGPL-3.0-only
// Fork of: https://github.com/Rari-Capital/solmate/blob/main/src/test/ERC721.t.sol
pragma solidity 0.8.10;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {DSInvariantTest} from "solmate/test/utils/DSInvariantTest.sol";

import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

import "../ERC721K.sol";

interface CheatCodes {
  function prank(address) external;
  function expectRevert(bytes calldata) external;
}

contract MockERC721K is ERC721K {
    constructor(string memory _name, string memory _symbol) ERC721K(_name, _symbol) {}

    function mint(address to, uint256 quantity) public virtual {
        _mint(to, quantity, '', false);
    }

    function burn(uint256 tokenId) public virtual {
        _burn(tokenId);
    }

    function safeMint(address to, uint256 quantity) public virtual {
        _safeMint(to, quantity);
    }

    function safeMint(
        address to,
        uint256 quantity,
        bytes memory data
    ) public virtual {
        _safeMint(to, quantity, data);
    }
}

contract ERC721KUser is ERC721TokenReceiver {
    ERC721K token;

    constructor(ERC721K _token) {
        token = _token;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }

    function approve(address spender, uint256 tokenId) public virtual {
        token.approve(spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        token.setApprovalForAll(operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        token.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        token.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public {
        token.safeTransferFrom(from, to, tokenId, data);
    }
}

contract ERC721Recipient is ERC721TokenReceiver {
    address public operator;
    address public from;
    uint256 public id;
    bytes public data;

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _id,
        bytes calldata _data
    ) public virtual override returns (bytes4) {
        operator = _operator;
        from = _from;
        id = _id;
        data = _data;

        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

contract RevertingERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        revert(string(abi.encodePacked(ERC721TokenReceiver.onERC721Received.selector)));
    }
}

contract WrongReturnDataERC721Recipient is ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public virtual override returns (bytes4) {
        return 0xCAFEBEEF;
    }
}

contract NonERC721Recipient {}

contract ERC721Test is DSTestPlus {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    MockERC721K token;

    function setUp() public {
        token = new MockERC721K("Token", "TKN");
    }

    function invariantMetadata() public {
        assertEq(token.name(), "Token");
        assertEq(token.symbol(), "TKN");
    }

    function testMint() public {
        token.mint(address(0xBEEF), 1);

        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.ownerOf(1), address(0xBEEF));
    }

    function testMintMany() public {
        token.mint(address(0xBEEF), 10);

        assertEq(token.balanceOf(address(0xBEEF)), 10);
        for (uint256 i = 1; i < 11; i++) {
            assertEq(token.ownerOf(i), address(0xBEEF));
        }
    }

    function testBurn() public {
        token.mint(address(0xBEEF), 1);
        token.burn(1);

        assertEq(token.balanceOf(address(0xBEEF)), 0);
        cheats.expectRevert(abi.encodeWithSignature("OwnerQueryForNonexistentToken()"));
        token.ownerOf(1);
    }

    function testApprove() public {
        token.mint(address(this), 1);

        token.approve(address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0xBEEF));
    }

    function testApproveBurn() public {
        token.mint(address(this), 1);

        token.approve(address(0xBEEF), 1);

        token.burn(1);

        assertEq(token.balanceOf(address(this)), 0);
        cheats.expectRevert(abi.encodeWithSignature("OwnerQueryForNonexistentToken()"));
        token.ownerOf(1);
        cheats.expectRevert(abi.encodeWithSignature("ApprovalQueryForNonexistentToken()"));
        token.getApproved(1);
    }

    function testApproveAll() public {
        token.setApprovalForAll(address(0xBEEF), true);

        assertTrue(token.isApprovedForAll(address(this), address(0xBEEF)));
    }

    function testTransferFrom() public {
        ERC721KUser from = new ERC721KUser(token);

        token.mint(address(from), 1);

        from.approve(address(this), 1);

        token.transferFrom(address(from), address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(address(from)), 0);
    }

    function testTransferFromSelf() public {
        token.mint(address(this), 1);

        token.transferFrom(address(this), address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferFromApproveAll() public {
        ERC721KUser from = new ERC721KUser(token);

        token.mint(address(from), 1);

        from.setApprovalForAll(address(this), true);

        token.transferFrom(address(from), address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(address(from)), 0);
    }

    function testSafeTransferFromToEOA() public {
        ERC721KUser from = new ERC721KUser(token);

        token.mint(address(from), 1);

        from.setApprovalForAll(address(this), true);

        token.safeTransferFrom(address(from), address(0xBEEF), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(address(from)), 0);
    }

    function testSafeTransferFromToERC721Recipient() public {
        ERC721KUser from = new ERC721KUser(token);
        ERC721Recipient recipient = new ERC721Recipient();

        token.mint(address(from), 1);

        from.setApprovalForAll(address(this), true);

        token.safeTransferFrom(address(from), address(recipient), 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(address(from)), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), address(from));
        assertEq(recipient.id(), 1);
        assertBytesEq(recipient.data(), "");
    }

    function testSafeTransferFromToERC721RecipientWithData() public {
        ERC721KUser from = new ERC721KUser(token);
        ERC721Recipient recipient = new ERC721Recipient();

        token.mint(address(from), 1);

        from.setApprovalForAll(address(this), true);

        token.safeTransferFrom(address(from), address(recipient), 1, "testing 123");

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(address(from)), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), address(from));
        assertEq(recipient.id(), 1);
        assertBytesEq(recipient.data(), "testing 123");
    }

    function testSafeMintToEOA() public {
        token.safeMint(address(0xBEEF), 1);

        assertEq(token.ownerOf(1), address(address(0xBEEF)));
        assertEq(token.balanceOf(address(address(0xBEEF))), 1);
    }
    
    function testSafeMintManyToEOA() public {
        token.safeMint(address(0xBEEF), 10);

        assertEq(token.balanceOf(address(address(0xBEEF))), 10);
        for (uint256 i = 1; i <= 10; i++) {
            assertEq(token.ownerOf(i), address(address(0xBEEF)));
        }
    }

    function testSafeMintToERC721Recipient() public {
        ERC721Recipient to = new ERC721Recipient();

        token.safeMint(address(to), 1);

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertBytesEq(to.data(), "");
    }

    function testSafeMintManyToERC721Recipient() public {
        ERC721Recipient to = new ERC721Recipient();

        token.safeMint(address(to), 10);

        assertEq(token.balanceOf(address(to)), 10);
        for (uint256 i = 1; i <= 10; i++) {
            assertEq(token.ownerOf(i), address(to));
        }

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 10);
        assertBytesEq(to.data(), "");
    }

    function testSafeMintToERC721RecipientWithData() public {
        ERC721Recipient to = new ERC721Recipient();

        token.safeMint(address(to), 1, "testing 123");

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertBytesEq(to.data(), "testing 123");
    }

    function testSafeMintManyToERC721RecipientWithData() public {
        ERC721Recipient to = new ERC721Recipient();

        token.safeMint(address(to), 10, "testing 123");

        assertEq(token.balanceOf(address(to)), 10);
        for (uint256 i = 1; i <= 10; i++) {
            assertEq(token.ownerOf(i), address(to));
        }

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 10);
        assertBytesEq(to.data(), "testing 123");
    }

    function testFailMintToZero() public {
        token.mint(address(0), 1);
    }

    function testFailBurnUnMinted() public {
        token.burn(1);
    }

    function testFailDoubleBurn() public {
        token.mint(address(0xBEEF), 1);

        token.burn(1);
        token.burn(1);
    }

    function testFailApproveUnMinted() public {
        token.approve(address(0xBEEF), 1);
    }

    function testFailApproveUnAuthorized() public {
        token.mint(address(0xCAFE), 1);

        token.approve(address(0xBEEF), 1);
    }

    function testFailTransferFromUnOwned() public {
        token.transferFrom(address(0xFEED), address(0xBEEF), 1);
    }

    function testFailTransferFromWrongFrom() public {
        token.mint(address(0xCAFE), 1);

        token.transferFrom(address(0xFEED), address(0xBEEF), 1);
    }

    function testFailTransferFromToZero() public {
        token.mint(address(this), 1);

        token.transferFrom(address(this), address(0), 1);
    }

    function testFailTransferFromNotOwner() public {
        token.mint(address(0xFEED), 1);

        token.transferFrom(address(0xFEED), address(0xBEEF), 1);
    }

    function testFailSafeTransferFromToNonERC721Recipient() public {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new NonERC721Recipient()), 1);
    }

    function testFailSafeTransferFromToNonERC721RecipientWithData() public {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new NonERC721Recipient()), 1, "testing 123");
    }

    function testFailSafeTransferFromToRevertingERC721Recipient() public {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new RevertingERC721Recipient()), 1);
    }

    function testFailSafeTransferFromToRevertingERC721RecipientWithData() public {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new RevertingERC721Recipient()), 1, "testing 123");
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnData() public {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new WrongReturnDataERC721Recipient()), 1);
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnDataWithData() public {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new WrongReturnDataERC721Recipient()), 1, "testing 123");
    }

    function testFailSafeMintToNonERC721Recipient() public {
        token.safeMint(address(new NonERC721Recipient()), 1);
    }

    function testFailSafeMintToNonERC721RecipientWithData() public {
        token.safeMint(address(new NonERC721Recipient()), 1, "testing 123");
    }

    function testFailSafeMintToRevertingERC721Recipient() public {
        token.safeMint(address(new RevertingERC721Recipient()), 1);
    }

    function testFailSafeMintToRevertingERC721RecipientWithData() public {
        token.safeMint(address(new RevertingERC721Recipient()), 1, "testing 123");
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnData() public {
        token.safeMint(address(new WrongReturnDataERC721Recipient()), 1);
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnDataWithData() public {
        token.safeMint(address(new WrongReturnDataERC721Recipient()), 1, "testing 123");
    }

    function testMetadata(string memory name, string memory symbol) public {
        MockERC721K tkn = new MockERC721K(name, symbol);

        assertEq(tkn.name(), name);
        assertEq(tkn.symbol(), symbol);
    }

    function testMint(address to) public {
        if (to == address(0)) to = address(0xBEEF);

        token.mint(to, 1);

        assertEq(token.balanceOf(to), 1);
        assertEq(token.ownerOf(1), to);
    }

    function testMintMany(address to) public {
        if (to == address(0)) to = address(0xBEEF);

        token.mint(to, 10);

        assertEq(token.balanceOf(to), 10);
        for (uint256 i = 1; i <= 10; i++) {
            assertEq(token.ownerOf(i), to);
        }
    }

    function testBurn(address to) public {
        if (to == address(0)) to = address(0xBEEF);

        token.mint(to, 1);
        token.burn(1);

        assertEq(token.balanceOf(to), 0);
        cheats.expectRevert(abi.encodeWithSignature("OwnerQueryForNonexistentToken()"));
        token.ownerOf(1);
    }

    function testApprove(address to) public {
        if (to == address(0)) to = address(0xBEEF);

        token.mint(address(this), 1);

        token.approve(to, 1);

        assertEq(token.getApproved(1), to);
    }

    function testApproveBurn(address to) public {
        token.mint(address(this), 1);

        token.approve(address(to), 1);

        token.burn(1);

        assertEq(token.balanceOf(address(this)), 0);
        cheats.expectRevert(abi.encodeWithSignature("OwnerQueryForNonexistentToken()"));
        token.ownerOf(1);
        cheats.expectRevert(abi.encodeWithSignature("ApprovalQueryForNonexistentToken()"));
        token.getApproved(1);
    }

    function testApproveAll(address to, bool approved) public {
        token.setApprovalForAll(to, approved);

        assertBoolEq(token.isApprovedForAll(address(this), to), approved);
    }

    function testTransferFrom(address to) public {
        ERC721KUser from = new ERC721KUser(token);

        if (to == address(0) || to == address(from)) to = address(0xBEEF);

        token.mint(address(from), 1);

        from.approve(address(this), 1);

        token.transferFrom(address(from), to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(address(from)), 0);
    }

    function testTransferFromSelf(address to) public {
        if (to == address(0) || to == address(this)) to = address(0xBEEF);

        token.mint(address(this), 1);

        token.transferFrom(address(this), to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferFromApproveAll(address to) public {
        if (to == address(0) || to == address(this)) to = address(0xBEEF);

        ERC721KUser from = new ERC721KUser(token);

        token.mint(address(from), 1);

        from.setApprovalForAll(address(this), true);

        token.transferFrom(address(from), to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(address(from)), 0);
    }

    function testSafeTransferFromToEOA(address to) public {
        ERC721KUser from = new ERC721KUser(token);

        if (to == address(0) || to == address(this)) to = address(0xBEEF);

        if (uint256(uint160(to)) <= 18 || to.code.length > 0) return;

        token.mint(address(from), 1);

        from.setApprovalForAll(address(this), true);

        token.safeTransferFrom(address(from), to, 1);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), to);
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(address(from)), 0);
    }

    function testSafeTransferFromToERC721RecipientWithData(bytes calldata data) public {
        ERC721KUser from = new ERC721KUser(token);
        ERC721Recipient recipient = new ERC721Recipient();

        token.mint(address(from), 1);

        from.setApprovalForAll(address(this), true);

        token.safeTransferFrom(address(from), address(recipient), 1, data);

        assertEq(token.getApproved(1), address(0));
        assertEq(token.ownerOf(1), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(address(from)), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), address(from));
        assertEq(recipient.id(), 1);
        assertBytesEq(recipient.data(), data);
    }

    function testSafeMintToEOA(address to) public {
        if (to == address(0)) to = address(0xBEEF);

        if (uint256(uint160(to)) <= 18 || to.code.length > 0) return;

        token.safeMint(to, 1);

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);
    }

    function testSafeMintManyToEOA(address to) public {
        if (to == address(0)) to = address(0xBEEF);

        if (uint256(uint160(to)) <= 18 || to.code.length > 0) return;

        token.safeMint(to, 10);

        assertEq(token.balanceOf(address(to)), 10);
        for (uint256 i = 1; i <= 10; i++) {
            assertEq(token.ownerOf(i), address(to));
        }
    }

    function testSafeMintToERC721RecipientWithData(bytes calldata data) public {
        ERC721Recipient to = new ERC721Recipient();

        token.safeMint(address(to), 1, data);

        assertEq(token.ownerOf(1), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1);
        assertBytesEq(to.data(), data);
    }

    function testSafeMintManyToERC721RecipientWithData(bytes calldata data) public {
        ERC721Recipient to = new ERC721Recipient();

        token.safeMint(address(to), 10, data);

        for (uint256 i = 1; i <= 10; i++) {
            assertEq(token.ownerOf(i), address(to));
        }

        assertEq(token.balanceOf(address(to)), 10);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 10);
        assertBytesEq(to.data(), data);
    }

    function testFailMintManyToZero(uint64 quantity) public {
        token.safeMint(address(0), quantity);
    }

    function testFailBurnUnMinted(uint256 id) public {
        token.burn(id);
    }

    function testFailDoubleBurn(address to) public {
        if (to == address(0)) to = address(0xBEEF);

        token.mint(to, 1);

        token.burn(1);
        token.burn(1);
    }

    function testFailApproveUnMinted(uint256 id, address to) public {
        token.approve(to, id);
    }

    function testFailApproveUnAuthorized(
        address owner,
        address to
    ) public {
        if (owner == address(0) || owner == address(this)) owner = address(0xBEEF);

        token.mint(owner, 1);

        token.approve(to, 1);
    }

    function testFailTransferFromUnOwned(
        address from,
        address to,
        uint256 id
    ) public {
        token.transferFrom(from, to, id);
    }

    function testFailTransferFromWrongFrom(
        address owner,
        address from,
        address to
    ) public {
        if (owner == address(0)) to = address(0xBEEF);
        if (from == owner) revert();

        token.mint(owner, 1);

        token.transferFrom(from, to, 1);
    }

    function testFailTransferFromNotOwner(
        address from,
        address to
    ) public {
        if (from == address(this)) from = address(0xBEEF);

        token.mint(from, 1);

        token.transferFrom(from, to, 1);
    }

    function testFailSafeTransferFromToNonERC721RecipientWithData(bytes calldata data) public {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new NonERC721Recipient()), 1, data);
    }

    function testFailSafeTransferFromToRevertingERC721RecipientWithData(bytes calldata data) public {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new RevertingERC721Recipient()), 1, data);
    }

    function testFailSafeTransferFromToERC721RecipientWithWrongReturnDataWithData(bytes calldata data)
        public
    {
        token.mint(address(this), 1);

        token.safeTransferFrom(address(this), address(new WrongReturnDataERC721Recipient()), 1, data);
    }

    function testFailSafeMintManyToNonERC721Recipient(uint64 quantity) public {
        token.safeMint(address(new NonERC721Recipient()), quantity);
    }

    function testFailSafeMintToNonERC721RecipientWithData(bytes calldata data) public {
        token.safeMint(address(new NonERC721Recipient()), 1, data);
    }

    function testFailSafeMintManyToNonERC721RecipientWithData(bytes calldata data, uint64 quantity) public {
        token.safeMint(address(new NonERC721Recipient()), quantity, data);
    }
    
    function testFailSafeMintManyToRevertingERC721Recipient(uint64 quantity) public {
        token.safeMint(address(new RevertingERC721Recipient()), quantity);
    }

    function testFailSafeMintToRevertingERC721RecipientWithData(bytes calldata data) public {
        token.safeMint(address(new RevertingERC721Recipient()), 1, data);
    }

    function testFailSafeMintManyToRevertingERC721RecipientWithData(bytes calldata data, uint64 quantity) public {
        token.safeMint(address(new RevertingERC721Recipient()), quantity, data);
    }

    function testFailSafeMintManyToERC721RecipientWithWrongReturnData(uint64 quantity) public {
        token.safeMint(address(new WrongReturnDataERC721Recipient()), quantity);
    }

    function testFailSafeMintToERC721RecipientWithWrongReturnDataWithData(bytes calldata data) public {
        token.safeMint(address(new WrongReturnDataERC721Recipient()), 1, data);
    }

    function testFailSafeMintManyToERC721RecipientWithWrongReturnDataWithData(bytes calldata data, uint64 quantity) public {
        token.safeMint(address(new WrongReturnDataERC721Recipient()), quantity, data);
    }
}