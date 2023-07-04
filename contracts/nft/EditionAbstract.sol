// SPDX-License-Identifier: UNLICENSED
// Genius is NOT LICENSED FOR COPYING.
// This Genius Edition Abstract Contract is NOT LICENSED FOR COPYING.
// Genius (C) 2022-2023. All Rights Reserved.
pragma solidity 0.8.4;
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import "./erc1155enu/token/ERC1155/base/ERC1155Base.sol";
import "./erc1155enu/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import "./erc1155enu/token/ERC1155/metadata/ERC1155Metadata.sol";
import {IERC165, ERC165, ERC165Storage} from "./erc1155enu/introspection/ERC165.sol";

abstract contract EditionAbstract is
    EIP712,
    ERC165,
    ERC1155Base,
    ERC1155Metadata,
    ERC1155Enumerable,
    IERC1155Receiver
{
    using Strings for uint256;
    using ERC165Storage for ERC165Storage.Layout;
    error ErrorNotAllowed();
    error ErrorNullAddress();

    // Events
    /**
     * @dev    emit when calling mint function, only by Gnft contract
     * @param  to  account to mint nft
     * @param  tokenId  token id, must a number > 0
     * @param  quantity  amount of the token minted
     * @param  rarity  An index of how "rare" the GENFT is versus other GENFTs
     * @param  variety  Index of the GENFT's variety under the rarity category
     */
    event Mint(
        address indexed to,
        uint256 tokenId,
        uint256 quantity,
        uint8 rarity,
        uint8 variety
    );

    /**
     * Common Edition Constants
     */
    uint256 public constant ULTIMATE_TOKEN_ID = 2**255 - 1;
    uint256 public constant BOOSTER_TOKEN_ID = 2**255 - 2;
    uint256 public immutable LAUNCH_TIMESTAMP;

    /**
     * Common Edition Variables
     */
    uint256 internal constant PHI_PRECISION = 10**27;
    string _name;
    string _symbol;
    string _version;
    address public genftAddress;
    address public geniAddress;
    string private _baseUri;
    address private _owner;

    // rarity from token id
    mapping(uint256 => uint8) public tokenToRarity;
    // variety from token id
    mapping(uint256 => uint8) public tokenToVariety;
    // expired time
    uint256 public expired;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory version_,
        string memory baseUri_
    ) EIP712(name_, version_) {
        _name = name_;
        _symbol = symbol_;
        _version = version_;

        // NOTE: baseURI format is as following:
        // Format: "ipfs://CID/"
        // Example: "ipfs://JGkARStQ5yBXgyfG2ZH3Jby8w6BgQmTRCQF5TrfB2hPjrD/"
        _setBaseURI(baseUri_);
        _baseUri = baseUri_;
        _owner = msg.sender;

        ERC165Storage.layout().setSupportedInterface(
            type(IERC165).interfaceId,
            true
        );
        ERC165Storage.layout().setSupportedInterface(
            type(IERC1155).interfaceId,
            true
        );
        LAUNCH_TIMESTAMP = block.timestamp;
    }

    /**
     * @dev     adds a contractURI virtual method to ERC1155 contract that
     * @return  URL for the storefront-level metadata for the edition contract.
     */
    function contractURI() external pure virtual returns (string memory) {
        return "ipfs://$PRODUCTION_CID/storefront.json";
    }

    /**
     * @notice  name revealed on NFT market places
     * @dev     public function
     * @return  name of the GENFT
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @notice  symbol revealed on NFT market places
     * @dev     public function
     * @return  the GENFT symbol
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev     version used for EIP712
     * @return  GENFT version
     */
    function version() public view returns (string memory) {
        return _version;
    }

    /**
     * @dev     the number of edition version
     * @return  GENFT Edition version -- same thing as version() but GENFT
     */
    function editionVersion() public view virtual returns (string memory) {
        return _version;
    }

    /**
     * @dev     getter to base URI
     * @return  baseURI.
     */
    function baseURI() external view returns (string memory) {
        return _baseUri;
    }

    /**
     * @notice  update base uri
     * @dev     called by owner, changing new CID on IPFS
     * @param   baseUri_  base URI in the format: ipfs://CID/
     */
    function setBaseURI(string memory baseUri_) external {
        if (msg.sender != _owner) {
            revert ErrorNotAllowed();
        }
        _setBaseURI(baseUri_);
        _baseUri = baseUri_;
    }

    /**
     * @notice  mint ERC1155 token
     * @dev     virtual function, overridden in the Genius Edition NFT contract
     * @param  to  receiver of the token
     * @param  quantity  of the token, and this value will always be 1
     * @param  rarityRand  random for rarity index
     * @param  varietyRand  random for variety index
     */
    function mint(
        address to,
        uint256 quantity,
        uint256 rarityRand,
        uint256 varietyRand
    )
        public
        virtual
        returns (
            uint256,
            uint8,
            uint8
        )
    {}

    /**
     * @dev    set expired time, called only by Genft
     * @param  _expired  expired time
     */
    function setExpired(uint256 _expired) external virtual {
        if (msg.sender != genftAddress) {
            revert ErrorNotAllowed();
        }
         expired = _expired;
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning, as well as batched variants.
     *
     * The same hook is called on both single and batched variants. For single
     * transfers, the length of the `id` and `amount` arrays will be 1.
     *
     * Calling conditions (for each `id` and `amount` pair):
     *
     * - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * of token type `id` will be  transferred to `to`.
     * - When `from` is zero, `amount` tokens of token type `id` will be minted
     * for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens of token type `id`
     * will be burned.
     * - `from` and `to` are never both zero.
     * - `ids` and `amounts` have the same, non-zero length.
     *
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155BaseInternal, ERC1155EnumerableInternal) {
        ERC1155EnumerableInternal._beforeTokenTransfer(
            operator,
            from,
            to,
            ids,
            amounts,
            data
        );
    }

    /**
     * @dev   Calculates a secure-ish random 256-bit number for GENFTs.
     *        These are the motivations and purposes behind each parameter to
     *        calculate the random number:
     *
     *        1. salt: each function that initially invokes the first
     *           _probability / _random functions will originate with its own
     *           unique 'salt'.  This is to ensure that when multiple functions
     *           are called by the EOA within the same transaction, the EOA will
     *           have equally-random chances to yield a completely different
     *           GENFT.  The block timestamp is added to salt to make it more
     *           difficult for an end user to predict which GENFT they'll mint.
     *
     *        2. blockhash: the only EOAs that can reasonably use this to their
     *           advantage without adding significant costs for the transaction,
     *           such as the capital required to create a miner with a weight of
     *           1 or greater, are EOAs that run the function to "claim" their
     *           sacrifie tokens and EOAs that run the function to summarize
     *           a Genius Calendar period.  That is because these functions have
     *           a 100% chance to mint a GENFT.
     *
     *           However, the "claim" function can only be run once per EOA that
     *           participated in the Genius Sacrifice Event.  Therefore, this
     *           will not be useful for the EOA, even if they have the ability
     *           to influence the block hash.  See: https://sacrifice.to
     *
     *           In regards to the Calendar summarize functions, the EOA cannot
     *           waste time figuring out their best chances because if they are
     *           not the first EOA to run the function, then they lose the
     *           ability to run the function for the day/period.
     *
     *           For every other function, the EOA is prevented from spamming
     *           these functions not only from the blockchain's gas fee, but
     *           spam is additional prevented because every other function
     *           has one of the following qualities:
     *              a. It is a "first-come, first-to-benefit" function, e.g. the
     *                 functions to claimAuction, releaseShares, etc.
     *              b. The function is necessary for "cleaning up" or updating
     *                 Genius' environment, active shares, etc., and therefore,
     *                 the EOA should be rewarded as they wish.
     *              c. The EOA had to have input something of value to the
     *                 network, i.e. they had to put up a significant, non-dust
     *                 amount of GENI capital, which ultimately benefitted the
     *                 Genius end users.
     *
     *           Therefore, if it is worth it for the EOA to exert the position-
     *           ing and effort to influence random numbers for their purpose,
     *           then this action is also not guaranteed, and its repeated
     *           action is designed to benefit the Genius end user.  Since the
     *           purpose of GENFTs is purely as collectibles and *not* for
     *           significant financial value, it is perfectly acceptable for
     *           EOAs to "game" the possibilities of yielding the GENFT that
     *           they desire.
     *
     *        3. account: used so that different EOAs running the same GENFT
     *           minting functions within the same block will not generate the
     *           same GENFTs.  Likewise, if different accounts are unpacking
     *           booster/ultimate packs within the same transaction, this will
     *           ensure that the end users do not unpack the same GENFTs.
     *
     *        Finally, it should be noted that the GENFT controller prevents
     *        EOAs from minting GENFTs with the same randomization salt or
     *        unpacking to mint multiple GENFTs within the same block.  This is
     *        done to prevent the end user from duplicating multiple copies of
     *        the same GENFTs.
     *
     * @param  account  address used to generate a random number
     * @param  salt  when multiple random numbers are necessary, this is used
     *               to add some randomness.  This is important because within
     *               a single transaction, the random number will be exactly
     *               the same without this _salt.
     */
    function _random(
        address account,
        uint256 salt
    ) internal view virtual returns (uint256) {
        unchecked {
        return uint256(
            keccak256(
                abi.encodePacked(
                    salt + block.timestamp,
                    blockhash(block.number),
                    account
                )
            )
        );
        } // end unchecked
    }

    /**
     * @dev  Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30,000 gas.
     */
    function supportsInterface(bytes4 interfaceId)
        public view virtual override(ERC165, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC1155Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev  Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     *
     * NOTE: To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     *
     * @ operator The address which initiated the transfer (i.e. msg.sender)
     * @ from The address which previously owned the token
     * @ id The ID of the token being transferred
     * @ value The amount of tokens being transferred
     * @ data Additional data with no specified format
     * @return  `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev  Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated.
     *
     * NOTE: To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     *
     * @ The address which initiated the batch transfer (i.e. msg.sender)
     * @ from The address which previously owned the token
     * @ ids An array containing ids of each token being transferred (order and length must match values array)
     * @ values An array containing amounts of each token being transferred (order and length must match ids array)
     * @ data Additional data with no specified format
     * @return  `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
