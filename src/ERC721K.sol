// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

error ERC721__ApprovalCallerNotOwnerNorApproved(address caller);
error ERC721__ApproveToCaller();
error ERC721__ApprovalToCurrentOwner();
error ERC721__BalanceQueryForZeroAddress();
error ERC721__InvalidMintParams();
error ERC721__OwnerQueryForNonexistentToken(uint256 tokenId);
error ERC721__TransferCallerNotOwnerNorApproved(address caller);
error ERC721__TransferFromIncorrectOwner(address from, address owner);
error ERC721__TransferToNonERC721ReceiverImplementer(address receiver);
error ERC721__TransferToZeroAddress();

/**
 * @notice Maximally optimized, minimalist ERC-721 implementation.
 *
 * @dev Assumes serials are sequentially minted starting at 1 (e.g. 1, 2, 3..),
 * and that an owner cannot have more than 2**64 - 1 (max value of uint64) of supply.
 * 
 * @author https://github.com/kadenzipfel - fork of https://github.com/chiru-labs/ERC721A, 
 * inspired by https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol.
 */
abstract contract ERC721K {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Mask of an entry in packed address data.
    uint256 private constant BITMASK_ADDRESS_DATA_ENTRY = (1 << 64) - 1;

    // The bit position of `numberMinted` in packed address data.
    uint256 private constant BITPOS_NUMBER_MINTED = 64;

    // The bit position of `numberBurned` in packed address data.
    uint256 private constant BITPOS_NUMBER_BURNED = 128;

    // The bit position of `aux` in packed address data.
    uint256 private constant BITPOS_AUX = 192;

    // Mask of all 256 bits in packed address data except the 64 bits for `aux`.
    uint256 private constant BITMASK_AUX_COMPLEMENT = (1 << 192) - 1;

    // The bit position of `startTimestamp` in packed ownership.
    uint256 private constant BITPOS_START_TIMESTAMP = 160;

    // The bit mask of the `burned` bit in packed ownership.
    uint256 private constant BITMASK_BURNED = 1 << 224;

    // The bit position of the `nextInitialized` bit in packed ownership.
    uint256 private constant BITPOS_NEXT_INITIALIZED = 225;

    // The bit mask of the `nextInitialized` bit in packed ownership.
    uint256 private constant BITMASK_NEXT_INITIALIZED = 1 << 225;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    // Token name
    string public name;

    // Token symbol
    string public symbol;

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                             ERC721 STORAGE
    //////////////////////////////////////////////////////////////*/    

    // The tokenId of the next token to be minted.
    uint256 internal _currentIndex = 1;

    // The number of tokens burned.
    uint256 internal _burnCounter;

    // Mapping from token ID to ownership details
    // An empty struct value does not necessarily mean the token is unowned.
    // See `_packedOwnershipOf` implementation for details.
    //
    // Bits Layout:
    // - [0..159]   `addr`
    // - [160..223] `startTimestamp`
    // - [224]      `burned`
    // - [225]      `nextInitialized`
    mapping(uint256 => uint256) private _packedOwnerships;

    // Mapping owner address to address data.
    //
    // Bits Layout:
    // - [0..63]    `balance`
    // - [64..127]  `numberMinted`
    // - [128..191] `numberBurned`
    // - [192..255] `aux`
    mapping(address => uint256) private _packedAddressData;

    // Mapping from token ID to approved address
    mapping(uint256 => address) public getApproved;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Burned tokens are calculated here, use _totalMinted() if you want to count just minted tokens.
     */
    function totalSupply() public view returns (uint256) {
        // Counter underflow is impossible as _burnCounter cannot be incremented
        // more than _currentIndex - 1 times
        unchecked {
            return _currentIndex - _burnCounter - 1;
        }
    }

    /**
     * @dev Returns the number of tokens in `owner`'s account.
     */
    function balanceOf(address owner) public view returns (uint256) {
        if (_isZero(owner)) revert ERC721__BalanceQueryForZeroAddress();
        return _packedAddressData[owner] & BITMASK_ADDRESS_DATA_ENTRY;
    }

    /**
     * @dev Returns the owner of the `tokenId` token.
     */
    function ownerOf(uint256 tokenId) public view returns (address) {
        return address(uint160(_packedOwnershipOf(tokenId)));
    }

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) public {
        address owner = address(uint160(_packedOwnershipOf(tokenId)));
        if (to == owner) revert ERC721__ApprovalToCurrentOwner();

        if (msg.sender != owner) if (!isApprovedForAll[owner][msg.sender]) {
            revert ERC721__ApprovalCallerNotOwnerNorApproved(msg.sender);
        }

        _approve(to, tokenId, owner);
    }

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) public virtual {
        if (operator == msg.sender) revert ERC721__ApproveToCaller();

        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        _transfer(from, to, tokenId);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        safeTransferFrom(from, to, tokenId, '');
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual {
        _transfer(from, to, tokenId);
        if (to.code.length != 0) if (ERC721TokenReceiver(to).onERC721Received(msg.sender, from, tokenId, _data) !=
                ERC721TokenReceiver.onERC721Received.selector) {
            revert ERC721__TransferToNonERC721ReceiverImplementer(to);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return  
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * Returns the total amount of tokens minted in the contract.
     */
    function _totalMinted() internal view returns (uint256) {
        // Counter underflow is impossible as _currentIndex does not decrement,
        // and it is initialized to 1
        unchecked {
            return _currentIndex - 1;
        }
    }

    /**
     * Returns the packed ownership data of `tokenId`.
     */
    function _packedOwnershipOf(uint256 tokenId) private view returns (uint256) {
        uint256 curr = tokenId;

        if (_isZero(curr)) revert ERC721__OwnerQueryForNonexistentToken(curr);

        unchecked {
            if (curr < _currentIndex) {
                uint256 packed = _packedOwnerships[curr];
                // If not burned.
                if (_isZero(packed & BITMASK_BURNED)) {
                    // Invariant:
                    // There will always be an ownership that has an address and is not burned
                    // before an ownership that does not have an address and is not burned.
                    // Hence, curr will not underflow.
                    //
                    // We can directly compare the packed value.
                    // If the address is zero, packed is zero.
                    while (_isZero(packed)) {
                        packed = _packedOwnerships[--curr];
                    }
                    return packed;
                }
            }
        }
        revert ERC721__OwnerQueryForNonexistentToken(tokenId);
    }

    /**
     * @dev Initializes the ownership slot minted at `index` for efficiency purposes.
     */
    function _initializeOwnershipAt(uint256 index) internal {
        if (_isZero(_packedOwnerships[index])) {
            _packedOwnerships[index] = _packedOwnershipOf(index);
        }
    }

    function _safeMint(address to, uint256 quantity) internal {
        _safeMint(to, quantity, '');
    }

    /**
     * @dev Safely mints `quantity` tokens and transfers them to `to`.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called for each safe transfer.
     * - `quantity` must be greater than 0.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(
        address to,
        uint256 quantity,
        bytes memory _data
    ) internal {
        _mint(to, quantity);

        unchecked {
            if (to.code.length != 0) {
                uint256 end = _currentIndex;
                if (ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), end - 1, _data) !=
                ERC721TokenReceiver.onERC721Received.selector) {
                    revert ERC721__TransferToNonERC721ReceiverImplementer(to);
                }
                // Reentrancy protection.
                if (_currentIndex != end) revert();
            }
        }
    }

    /**
     * @dev Mints `quantity` tokens and transfers them to `to`.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `quantity` must be greater than 0.
     *
     * Emits a {Transfer} event.
     */
    function _mint(
        address to,
        uint256 quantity
    ) internal {
        uint256 startTokenId = _currentIndex;

        if (_isOneZero(to, quantity)) revert ERC721__InvalidMintParams();

        // Overflows are incredibly unrealistic.
        // balance or numberMinted overflow if current value of either + quantity > 1.8e19 (2**64) - 1
        // updatedIndex overflows if _currentIndex + quantity > 1.2e77 (2**256) - 1
        unchecked {
            // Updates:
            // - `balance += quantity`.
            // - `numberMinted += quantity`.
            //
            // We can directly add to the balance and number minted.
            _packedAddressData[to] += quantity * ((1 << BITPOS_NUMBER_MINTED) | 1);

            // Updates:
            // - `address` to the owner.
            // - `startTimestamp` to the timestamp of minting.
            // - `burned` to `false`.
            // - `nextInitialized` to `quantity == 1`.
            _packedOwnerships[startTokenId] = _packMintOwnershipData(to, quantity);

            uint256 offset;
            do {
                emit Transfer(address(0), to, startTokenId + offset++);
            } while (offset < quantity);

            _currentIndex = startTokenId + quantity;
        }
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) private {
        uint256 prevOwnershipPacked = _packedOwnershipOf(tokenId);

        if (address(uint160(prevOwnershipPacked)) != from) revert ERC721__TransferFromIncorrectOwner(from, address(uint160(prevOwnershipPacked)));

        address approvedAddress = getApproved[tokenId];

        bool isApprovedOrOwner = (msg.sender == from ||
            approvedAddress == msg.sender) ||
            isApprovedForAll[from][msg.sender];

        if (!isApprovedOrOwner) revert ERC721__TransferCallerNotOwnerNorApproved(msg.sender);
        if (_isZero(to)) revert ERC721__TransferToZeroAddress();

        // Clear approvals from the previous owner
        if (!_isZero(approvedAddress)) {
            delete getApproved[tokenId];
        }

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        // Counter overflow is incredibly unrealistic as tokenId would have to be 2**256.
        unchecked {
            // We can directly increment and decrement the balances.
            --_packedAddressData[from]; // Updates: `balance -= 1`.
            ++_packedAddressData[to]; // Updates: `balance += 1`.

            // Updates:
            // - `address` to the next owner.
            // - `startTimestamp` to the timestamp of transfering.
            // - `burned` to `false`.
            // - `nextInitialized` to `true`.
            _packedOwnerships[tokenId] = _packTransferOwnershipData(to);

            // If the next slot may not have been initialized (i.e. `nextInitialized == false`) .
            if (_isZero(prevOwnershipPacked & BITMASK_NEXT_INITIALIZED)) {
                // If the next slot's address is zero and not burned (i.e. packed value is zero).
                if (_isZero(_packedOwnerships[tokenId + 1])) {
                    // If the next slot is within bounds.
                    if (tokenId + 1 != _currentIndex) {
                        // Initialize the next slot to maintain correctness for `ownerOf(tokenId + 1)`.
                        _packedOwnerships[tokenId + 1] = prevOwnershipPacked;
                    }
                }
            }
        }

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev This is equivalent to _burn(tokenId, false)
     */
    function _burn(uint256 tokenId) internal virtual {
        _burn(tokenId, false);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId, bool approvalCheck) internal virtual {
        uint256 prevOwnershipPacked = _packedOwnershipOf(tokenId);

        address from = address(uint160(prevOwnershipPacked));

        address approvedAddress = getApproved[tokenId];

        if (approvalCheck) {
            bool isApprovedOrOwner = (msg.sender == from ||
                approvedAddress == msg.sender) ||
                isApprovedForAll[from][msg.sender];

            if (!isApprovedOrOwner) revert ERC721__TransferCallerNotOwnerNorApproved(msg.sender);
        }

        // Clear approvals from the previous owner
        if (!_isZero(approvedAddress)) {
            delete getApproved[tokenId];
        }

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        // Counter overflow is incredibly unrealistic as tokenId would have to be 2**256.
        unchecked {
            // Updates:
            // - `balance -= 1`.
            // - `numberBurned += 1`.
            //
            // We can directly decrement the balance, and increment the number burned.
            // This is equivalent to `packed -= 1; packed += 1 << BITPOS_NUMBER_BURNED;`.
            _packedAddressData[from] += (1 << BITPOS_NUMBER_BURNED) - 1;

            // Updates:
            // - `address` to the last owner.
            // - `startTimestamp` to the timestamp of burning.
            // - `burned` to `true`.
            // - `nextInitialized` to `true`.
            _packedOwnerships[tokenId] = _packBurnOwnershipData(from);

            // If the next slot may not have been initialized (i.e. `nextInitialized == false`) .
            if (_isZero(prevOwnershipPacked & BITMASK_NEXT_INITIALIZED)) {
                // If the next slot's address is zero and not burned (i.e. packed value is zero).
                if (_isZero(_packedOwnerships[tokenId + 1])) {
                    // If the next slot is within bounds.
                    if (tokenId + 1 != _currentIndex) {
                        // Initialize the next slot to maintain correctness for `ownerOf(tokenId + 1)`.
                        _packedOwnerships[tokenId + 1] = prevOwnershipPacked;
                    }
                }
            }
        }

        emit Transfer(from, address(0), tokenId);

        // Overflow not possible, as _burnCounter cannot be exceed _currentIndex times.
        unchecked {
            _burnCounter++;
        }
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(
        address to,
        uint256 tokenId,
        address owner
    ) private {
        getApproved[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                            ASSEMBLY TOOLS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Checks if val == 0
     */
    function _isZero(uint256 val) private pure returns (bool isZero) {
        assembly {
            isZero := iszero(val)
        }
    }

    /**
     * @dev Checks if val == 0
     */
    function _isZero(address val) private pure returns (bool isZero) {
        assembly {
            isZero := iszero(val)
        }
    }

    /**
     * @dev Checks if at least one value is 0
     */
    function _isOneZero(address addr, uint num) private pure returns (bool result) {
        assembly {
            result := or(iszero(addr), iszero(num))
        }
    }

    /**
     * @dev Packs ownership data into single uint
     */
    function _packMintOwnershipData(address to, uint256 quantity) private view returns (uint256 packedData) {
        assembly {
            packedData := or(
                to, 
                or(
                    shl(
                        BITPOS_START_TIMESTAMP, 
                        timestamp()
                    ), 
                    shl(
                        BITPOS_NEXT_INITIALIZED, 
                        eq(quantity, 1)
                    )
                )
            )
        }
    }

    /**
     * @dev Packs ownership data into single uint
     */
    function _packTransferOwnershipData(address to) private view returns (uint256 packedData) {
        assembly {
            packedData := or(
                to, 
                or(
                    shl(
                        BITPOS_START_TIMESTAMP, 
                        timestamp()
                    ), 
                    BITMASK_NEXT_INITIALIZED
                )
            )
        }
    }

    /**
     * @dev Packs ownership data into single uint
     */
    function _packBurnOwnershipData(address from) private view returns (uint256 packedData) {
        assembly {
            packedData := or(
                from, 
                or(
                    shl(
                        BITPOS_START_TIMESTAMP, 
                        timestamp()
                    ), 
                    or (
                        BITMASK_BURNED,
                        BITMASK_NEXT_INITIALIZED
                    )
                )
            )
        }
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
interface ERC721TokenReceiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4);
}