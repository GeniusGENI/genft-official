// SPDX-License-Identifier: UNLICENSED
// Genius is NOT LICENSED FOR COPYING.
// This Genius Edition Contract is NOT LICENSED FOR COPYING.
// Genius (C) 2023. All Rights Reserved.
pragma solidity 0.8.4;

import "../GeniusAccessor.sol";
import "./EditionAbstract.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";


contract Edition001V2 is EditionAbstract, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * Edition custom errors
     */
    error ErrorMintSettingDoesNotExist();
    error ErrorInvalidSetting();
    error ErrorInsufficientDeposit();
    error ErrorUnknown();
    error ErrorEditionExpired();
    error ErrorPobOnly();
    error MustWaitAnotherBlock();
    error ErrorNotHolder();
    error ErrorMerkleOrAlreadyClaimed();
    error ErrorInvalidGenius();
    error ErrorAlreadyUpgraded();
    error ErrorUnauthorized();

    event Convert(
        address indexed account,
        uint256[] tokenIds,
        uint256[] amounts
    );

    /**
     * Rarity Constants
     */

    // PHI^-3
    uint256 public constant PHI_NPOW_3 = 236067977499789696409173668;
    // PHI^-6
    uint256 public constant PHI_NPOW_6 = 55728090000841214363305325;
    // PHI^-7 = 0.034441853748633026659628846753295530364019337474917
    uint256 private constant PHI_NPOW_7 = 34441853748633026659628846;
    // PHI^-10 = 0.0081306187557833487477241098899035253829951106830425
    uint256 private constant PHI_NPOW_10 = 8130618755783348747724109;
    // PHI^-11 = 0.0050249987406414902082282585417924771075170027128947
    uint256 private constant PHI_NPOW_11 = 5024998740641490208228258;
    uint256 internal constant PHI_PRECISION = 10**27;

    // rarity from token id
    mapping(uint256 => uint8) public tokenToRarity;
    // variety from token id
    mapping(uint256 => uint8) public tokenToVariety;

    // These numbers are all based on PHI ratio rarity, and the most rare rarity
    // classes are defined, first.
    uint256 public constant MAX_MYTHIC_AMPED = PHI_NPOW_11;
    uint256 public constant MAX_MYTHIC = MAX_MYTHIC_AMPED + PHI_NPOW_10;
    uint256 public constant MAX_RARE_AMPED = MAX_MYTHIC + PHI_NPOW_10;
    uint256 public constant MAX_RARE = MAX_RARE_AMPED + PHI_NPOW_7;
    uint256 public constant MAX_UNCOMMON_AMPED = MAX_RARE + PHI_NPOW_7;
    uint256 public constant MAX_COMMON_AMPED = MAX_UNCOMMON_AMPED + PHI_NPOW_6;
    uint256 public constant MAX_UNCOMMON = MAX_COMMON_AMPED + PHI_NPOW_3;

    // Rarities: maximum of 256 different rarities (8 bits)
    uint8 private constant RARITY_COMMON = 0;
    uint8 private constant RARITY_UNCOMMON = 1;
    uint8 private constant RARITY_COMMON_AMPED = 2;
    uint8 private constant RARITY_UNCOMMON_AMPED = 3;
    uint8 private constant RARITY_RARE = 4;
    uint8 private constant RARITY_RARE_AMPED = 5;
    uint8 private constant RARITY_MYTHIC = 6;
    uint8 private constant RARITY_MYTHIC_AMPED = 7;

    // Varieties: maximum of 256 different varieties (8 bits) per rarity.
    uint256[] public VARIETIES = [
        // common (0)
        15,
        // uncommon (1)
        9,
        // common foil (2)
        15,
        // uncommon foil (3)
        9,
        // rare (4)
        6,
        // rare foil (5)
        6,
        // mythic (6)
        2,
        // mythic foil (7)
        2
    ];

    uint256 public constant ULTIMATE_TOKEN_ID = 2**255 - 1;
    uint256 public constant BOOSTER_TOKEN_ID = 2**255 - 2;

    bytes32 internal constant MERKLE_ROOT =
        0xcad71776a60b1a4ca80bfa5452bfc50beeb645b7f64e97f5c464ef45a41d548d;

    address public geniAddress;
    address public packAddress;

    IGenius geniContract;
    EditionAbstract public immutable editionsV1;

    // Once the upgrade is applied, this flag will prevent the contract from
    // being upgraded again.
    bool public contractLocked = false;

    // Tracks the account addresses that have received the Booster Pack reward
    // for converting the old Edition 001 GENFTs to the new version.  This will
    // remain public so that the DAPP is able to communicate to the end user
    // whether or not they are eligible to receive a free Booster Pack :)
    mapping(address => bool) public userReceivedConvertReward;

    // Tracks whether or not the account address has already claimed their free
    // GENFT reward.  Only Genius Sacrifice Participants get a free claim.  This
    // remains public so the DAPP can communicate to the end user whether or not
    // they are eligible.
    mapping(address => bool) public claimedFreeNft;
    // Future Consideration: for future GENFTs, allow the end user to mint a
    // free GENFT if they own any of the prior GENFTs! :)

    constructor(
        address _geniAddress,
        address _genftAddress,
        // The prior Genius Editions v1 ERC-1155 contract
        address _editionAddress,
        address _minersAddress,
        address _royaltyAddress,
        string memory _baseUri
    )
        EditionAbstract(
            "Genius Collectibles First Edition",
            "GENFT-001",
            "2",
            _baseUri
        )
    {
        if (_geniAddress == address(0) ||
            _genftAddress == address(0) ||
            _royaltyAddress == address(0) ||
            _minersAddress == address(0) ||
            _editionAddress == address(0)
        ) {
            revert ErrorNullAddress();
        }

        // Genius core contracts
        geniAddress = _geniAddress;
        genftAddress = _genftAddress;
        minersAddress = _minersAddress;
        geniContract = IGenius(_geniAddress);

        // GENFT (independent from Genius) contracts
        royaltyAddress = _royaltyAddress;
        editionsV1 = EditionAbstract(_editionAddress);

        _setTokenURI(
            BOOSTER_TOKEN_ID,
            "booster.json"
        );

        _setTokenURI(
            ULTIMATE_TOKEN_ID,
            "ultimate.json"
        );

        _setURIs();
        // NOTE: The examples below show how URIs are generated for opeansea
        // compatability.
        //
        // URI Example 1:
        // "ipfs://JGkARStQ5yBXgyfG2ZH3Jby8w6BgQmTRCQF5TrfB2hPjrD/Reserved.json"
        //
        // URI Example 2:
        // "ipfs://JGkARStQ5yBXgyfG2ZH3Jby8w6BgQmTRCQF5TrfB2hPjrD/0_1.json"
    }

    /**
     * @notice  public facing, shielded, and only Genius Grantor can set this
     * @notice  Pack contract address must be set before the Packs can be minted
     */
    function setPackAddress(address _packAddress) external onlyGrantor {
        if (_packAddress == address(0)) revert ErrorNullAddress();
        if (packAddress != address(0)) revert ErrorUnauthorized();
        packAddress = _packAddress;
    }

    /**
     * @dev  Mints a specific GENFT based on its token ID, with data "0x00"
     * @param  beneficiary  the account that receives the specific GENFT
     * @param  tokenId  the specific GENFT ID (will not be randomly generated)
     * @param  quantity  the amount of packs the beneficiary will receive
     */
    function mintById(
        address beneficiary,
        uint256 tokenId,
        uint256 quantity
    ) external {
        console.log("inside mint by id");
        if (msg.sender != packAddress) {
            console.log("msg.sender not pack address??");
            revert ErrorUnauthorized();
        }
        console.log("about to mint...");
        _mint(beneficiary, tokenId, quantity, "0x00");
        console.log("MINTED :D");
    }

    /**
     * @dev  Gives 'burn' access for packs, which are burned when 'unpacked'
     * @param  account  the account that will have its packs burned
     * @param  packId  the ID of the pack to burn
     * @param  quantity  the quantity of packs to burn
     */
    function packBurn(
        address account,
        uint256 packId,
        uint256 quantity
    ) external {
        if (msg.sender != packAddress) {
            revert ErrorUnauthorized();
        }
        _burn(account, packId, quantity);
    }

    /**
     * @dev  Check for EVIDENCE that the contract address is a Genius contract.
     */
    function _checkForGenius(address contractAddressToCheck) private {
        try IGenius(contractAddressToCheck).PHI() returns (uint256 phi) {
            if (phi == 0) {
                revert ErrorInvalidGenius();
            }
        }
        catch {
            revert ErrorInvalidGenius();
        }
    }

    /**
     * @dev  locks contract's ability to be upgraded by the Grantor.
     */
    function lockContract() external onlyGrantor {
        contractLocked = true;
    }

    /**
     * @dev  Allows the Grantor one chance to change/update the contract
     *       addresses.  This will be only for a future upgrade.
     * @param  _geniAddress  Genius ERC20 contract
     * @param  _genftControllerAddress  The GENFT Controller contract
     * @param  _stabilityAddress  Genius "Stability Pool" (Collateral Vault)
     *                            contract.
     */
    function upgrade(
        address _geniAddress,
        address _genftControllerAddress,
        address _minersAddress
    ) external {
        // STEP 0: enforce that this function can only be called once.
        if (contractLocked) {
            revert ErrorAlreadyUpgraded();
        }

        // STEP 1: only the Genius Grantor (of the current Genius contract) can
        // call this.
        // NOTE: the modifier 'onlyGrantor' was removed from the function
        // declaration so that the function scope can be audited easier with
        // other GENFT 'upgrade' functionality.
        if (msg.sender != geniContract.oaGrantor()) {
            revert ErrorNotAllowed();
        }

        // STEP 2: verify all contracts.  They must have Genius-specific
        // functionality to pass verification.

        _checkForGenius(_geniAddress);
        _checkForGenius(_minersAddress);
        _checkForGenius(_genftControllerAddress);

        // When upgrading, these contracts *must* have a new contract address
        if (
            _geniAddress == geniAddress ||
            _genftControllerAddress == genftAddress ||
            _minersAddress == minersAddress
        ) {
            revert ErrorInvalidGenius();
        }

        // STEP 3: update the core Genius contracts to their upgraded version
        geniAddress = _geniAddress;
        genftAddress = _genftControllerAddress;
        minersAddress = _minersAddress;
        geniContract = IGenius(_geniAddress);
    }

    /**
     * @dev wrapper to only allow the Genius Grantor to have access.
     */
    modifier onlyGrantor() {
        if (msg.sender != geniContract.oaGrantor()) {
            revert ErrorNotAllowed();
        }
        _;
    }

    /**
     * @dev set metadata for all NFTs, private function
     */
    function _setURIs() private {
        unchecked {
        for (uint8 rarity = 0; rarity < 8; rarity++) {
            for (uint256 variety = 0; variety < VARIETIES[rarity]; variety++) {
                uint256 tokenId = ((uint256(rarity) << 8) | variety) + 1;

                _setTokenURI(
                    tokenId,
                    string(abi.encodePacked(
                        Strings.toString(rarity),
                        "_",
                        Strings.toString(variety),
                        ".json"
                    ))
                );
            } // end for variety
        } // end for rarity
        } // end unchecked
    }

    /**
     * @notice  mint ERC1155 token
     * @dev  virtual function, should be overriden in the implementation contract
     * should be called only by Gnft contract
     *
     * @param  to  receiver of the token
     * @param  quantity  of the token.  NOTE: this was redundant, and the value
     *                   1 will always be assumed to be the value passed through
     *                   to this function.
     * @param  rand1  random number 1
     * @param  rand2  random number 2
     */
    function mint(
        address to,
        // NOTE: Dai, quantity is always 1.  If we will never have the "mint"
        // function mint more than 1 quantity, then can we just remove this
        // parameter?
        //
        // "quantity" is always 1; however, this parameter remains here because
        // the Genius NFT Controller passes a value to this parameter.
        uint256 quantity,
        uint256 rand1,
        uint256 rand2
    )
        public
        override
        returns (
            uint256,
            uint8,
            uint8
        )
    {
        if (msg.sender != genftAddress) {
            revert ErrorNotAllowed();
        }
        // Quantity is always 1, and therefore it will not be passed to this
        // function for efficiency.
        return _genftMint(to, rand1, rand2);
    }

    /**
     * @notice  mints a GENFT ERC1155 token
     * @dev  private function, should be overriden in the implementation contract
     * should be called only by Gnft contract
     *
     * @param  to  receiver of the token
     * @param  rand1  random number 1
     * @param  rand2  random number 2
     */
    function _genftMint(
        address to,
        uint256 rand1,
        uint256 rand2
    )
        private
        returns (
            uint256,
            uint8,
            uint8
        )
    {
        // STEP 1: generate the token ID
        (uint256 tokenId, uint8 rarity, uint8 variety) = _genTokenId(
            rand1,
            rand2
        );
        // save for easy rarity/variety lookup by token ID
        if (0 == tokenToRarity[tokenId]) {
            tokenToRarity[tokenId] = rarity;
            tokenToVariety[tokenId] = variety;
        }
        _mint(to, tokenId, 1, "0x00");

        emit Mint(to, tokenId, 1, rarity, variety);
        return (tokenId, rarity, variety);
    }

    /**
     * @notice  generates token id from rx and ry
     * @dev  private function
     *
     * @param   rand1  random for rarity
     * @param   rand2  random for variety
     * @return  token  id must be a number > 0
     */
    function _genTokenId(uint256 rand1, uint256 rand2)
        private
        view
        returns (
            uint256,
            uint8,
            uint8
        )
    {
        // scale down between 0 to 1 (in phi precision)
        rand1 %= PHI_PRECISION;
        uint8 rarity;

        // NOTE: these could be put into a Rarity import
        if (rand1 < MAX_MYTHIC_AMPED) {
            rarity = RARITY_MYTHIC_AMPED;
        } else if (rand1 < MAX_MYTHIC) {
            rarity = RARITY_MYTHIC;
        } else if (rand1 < MAX_RARE_AMPED) {
            rarity = RARITY_RARE_AMPED;
        } else if (rand1 < MAX_RARE) {
            rarity = RARITY_RARE;
        } else if (rand1 < MAX_UNCOMMON_AMPED) {
            rarity = RARITY_UNCOMMON_AMPED;
        } else if (rand1 < MAX_COMMON_AMPED) {
            rarity = RARITY_COMMON_AMPED;
        } else if (rand1 < MAX_UNCOMMON) {
            rarity = RARITY_UNCOMMON;
        } else {
            rarity = RARITY_COMMON;
        }

        // STEP 2: determine which variety of the rarity card will be selected.
        uint8 variety = uint8(rand2 % VARIETIES[rarity]);
        unchecked {
        // STEP 3: calculate the TokenId. It can't be zero
        uint256 tokenId = ((uint256(rarity) << 8) | variety) + 1;
        return (tokenId, rarity, variety);
        } // end unchecked
    }

    /**
     * @dev  converts the end user's First Edition GENFTs to the latest version
     */
    function convert() external nonReentrant {
        // check if user is a holder of Edition 001 v1 NFTs
        uint256[] memory tokenIds = editionsV1.tokensByAccount(msg.sender);
        if (tokenIds.length == 0) {
            revert ErrorNotHolder();
        }

        // create an account array with the same address for batch process
        address[] memory accounts = new address[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; ) {
            accounts[i] = msg.sender;
            unchecked { i++; }
        }

        // getting balances for token Ids.
        uint256[] memory amounts = editionsV1.balanceOfBatch(
            accounts,
            tokenIds
        );

        // Transfer the old GENFTs to the new contract edition001 v2.
        editionsV1.safeBatchTransferFrom(
            msg.sender,
            address(this),
            tokenIds,
            amounts,
            "0x00"
        );

        // minting new tokens with the same token ids and amounts
        _mintBatch(msg.sender, tokenIds, amounts, "0x00");

        // mint booster pack if this is the user's first time converting.
        if (!userReceivedConvertReward[msg.sender]) {
            _mint(msg.sender, BOOSTER_TOKEN_ID, 1, "0x00");
            userReceivedConvertReward[msg.sender] = true;
        }
        emit Convert(msg.sender, tokenIds, amounts);
    }

    /**
     * @notice  claim the sacrifice participant's free Genius NFT.
     * @dev  called by only owner
     *
     * @param  _recipient address of a new edition
     * @param  _sacGrantAmount  the amount of Genitos granted as a result of the
     *                          end user's sacrifice.
     * @param  _merkleProof array of hashes up the merkleTree
     */
    function claimFreeNft(
        address _recipient,
        uint256 _sacGrantAmount,
        bytes32[] calldata _merkleProof
    ) external nonReentrant returns (uint256) {
        if (!claimedFreeNft[_recipient] ||
            !verifyMerkleProof(_recipient, _sacGrantAmount, _merkleProof))
        {
            revert ErrorMerkleOrAlreadyClaimed();
        }
        claimedFreeNft[_recipient] = true;

        (uint256 tokenId, , ) = _genftMint(
            _recipient,
            geniusRandom(_recipient, 8000000),
            geniusRandom(_recipient, 9000000)
        );
        return tokenId;
    }

    /**
     * @dev Claims GENFT
     * @param destination is the claimant, based on off chain data
     * @param amount claimant's amount of GENFT to mint
     * @param merkleProof array of hashes up the merkleTree
     */
    function verifyMerkleProof(
        address destination,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) private view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(destination, amount));
        return MerkleProof.verify(merkleProof, MERKLE_ROOT, node);
    }

}
