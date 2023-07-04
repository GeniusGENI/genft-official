// SPDX-License-Identifier: UNLICENSED
// Genius is NOT LICENSED FOR COPYING.
// This Genius Edition Contract is NOT LICENSED FOR COPYING.
// Genius (C) 2023. All Rights Reserved.
pragma solidity 0.8.4;

import "./EditionAbstract.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";


interface IDaiPermit {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

interface IGenius {
    function oaGrantor() external view returns (address);

    function PHI() external view returns (uint256);
}

interface IStability {
    function existingCollaterals(address colToken) external view returns (bool);

    function activeCollaterals(address colToken) external view returns (bool);

    function PHI() external view returns (uint256);
}

interface IGenftController {
    struct Edition {
        address editionAddress;
        uint56 id;
        uint40 startTime;
    }

    function currentEdition() external view
        returns (IGenftController.Edition memory);

    function PHI_PRECISION() external view returns (uint256);
}

interface ICalendar {
    function getCurrentGeniusDay() external view returns (uint256);
}


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
//    error ErrorQuantityLimitReached();

    /**
     * Edition custom Events
     */
    event MintUltimatePacks(
        address indexed to,
        uint256 tokenId,
        uint256 quantity
    );

    event MintBoosterPacks(
        address indexed to,
        uint256 tokenId,
        uint256 quantity
    );

    event UnpackUltimate(
        address indexed to,
        uint256 quantity,
        uint256[] tokens,
        uint8[] rarities,
        uint8[] varieties
    );

    event UnpackBooster(
        address indexed to,
        uint256 quantity,
        uint256[] tokens,
        uint8[] rarities,
        uint8[] varieties
    );

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

    // these numbers are all based on
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

    // deadline for permit
    uint256 deadline =
        0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // how many NFTs does an ultimate yield?
    uint256 constant ULTIMATE_YIELD = 16;
    uint256 constant BOOSTER_YIELD = 4;
    bytes32 internal constant MERKLE_ROOT =
        0xcad71776a60b1a4ca80bfa5452bfc50beeb645b7f64e97f5c464ef45a41d548d;

    address public stabilityAddress;
    address public immutable royaltyAddress;
    address public calendarAddress;

    IGenius geniContract;
    IStability stabilityContract;
    ICalendar calendarContract;
    IGenftController genftContract;
    EditionAbstract public immutable genftV1Contract;

    // Once the upgrade is applied, this flag will prevent the contract from
    // being upgraded again.
    bool public appliedUpgrade = false;

    /**
     * paymentToken: the ERC20 token contract address for the token used to
     *      receive payment from the end user for minting packs.  This can also
     *      be the native token by setting this value to address(0).
     * feeForUltimate: collateral amount cost to mint 1 "ULTIMATE PACK" NFT,
     *      this is in the smallest unit for the token.
     * feeForBooster: collateral amount cost to mint 1 "BOOSTER PACK" NFT, this
     *      is in the smallest unit for the token, considering the precision.
     */
    struct MintSetting {
        uint256 feeForUltimate;
        uint256 feeForBooster;
    }

    // Maps the token address to the MintSetting
    mapping(address => MintSetting) public mintSettings;

    // Maps account address and blockchain block number to true/false, whether
    // the end user has already unpacked during this block.  This variable is
    // intended to prevent the end user from unpacking more than 1 booster or
    // ultimate pack per block so that the unpacked results are truly random.
    mapping(address => mapping(uint256 => bool)) private oneUnpackPerBlock;

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

    constructor(
        address _geniAddress,
        address _genftAddress,
        address _stabilityAddress,
        address _calendarAddress,
        address _royaltyAddress,
        // The prior Genius Editions v1 ERC-1155 contract
        address _genftV1Address,
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
            _stabilityAddress == address(0) ||
            _calendarAddress == address(0) ||
            _royaltyAddress == address(0) ||
            _genftV1Address == address(0)
        ) {
            revert ErrorNullAddress();
        }

        // Genius core contracts
        geniAddress = _geniAddress;
        geniContract = IGenius(_geniAddress);
        genftAddress = _genftAddress;
        genftContract = IGenftController(_genftAddress);
        stabilityAddress = _stabilityAddress;
        stabilityContract = IStability(_stabilityAddress);
        calendarAddress = _calendarAddress;
        calendarContract = ICalendar(_calendarAddress);

        // GENFT (independent from Genius) contracts
        royaltyAddress = _royaltyAddress;
        genftV1Contract = EditionAbstract(_genftV1Address);

        _setTokenURI(
            BOOSTER_TOKEN_ID,
            "booster.json"
        );

        _setTokenURI(
            ULTIMATE_TOKEN_ID,
            "ultimate.json"
        );

        _setURIs();
    }

    /**
     * @dev  Check for EVIDENCE that the contract address is a Genius contract.
     */
    function _checkForGenius(address contractAddressToCheck) private {
        try IGenius(contractAddressToCheck).PHI() returns (uint256 phi) {
            if (phi == 0) {
                revert ErrorInvalidGenius();
            }
        } catch {
            revert ErrorInvalidGenius();
        }
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
        address _stabilityAddress,
        address _calendarAddress
    ) external onlyGrantor {
        // STEP 0: enforce that this function can only be called once.
        if (appliedUpgrade) {
            revert ErrorAlreadyUpgraded();
        }

        // STEP 1: verify all contracts.  They must have Genius-specific
        // functionality to pass verification.

        _checkForGenius(_geniAddress);
        _checkForGenius(_stabilityAddress);

        try ICalendar(_calendarAddress).getCurrentGeniusDay()
        returns (uint256 currentGeniusDay)
        {
            if (currentGeniusDay == 0) {
                revert ErrorInvalidGenius();
            }
        } catch {
            revert ErrorInvalidGenius();
        }

        try IGenftController(_genftControllerAddress).PHI_PRECISION()
        returns (uint256 phiPrecision)
        {
            if (phiPrecision == 0) {
                revert ErrorInvalidGenius();
            }
        } catch {
            revert ErrorInvalidGenius();
        }

        // When upgrading, these contracts *must* have a new contract address
        if (
            _geniAddress == geniAddress ||
            _genftControllerAddress == genftAddress ||
            _stabilityAddress == stabilityAddress
        ) {
            revert ErrorInvalidGenius();
        }

        // STEP 2: update the core Genius contracts to their upgraded version
        geniAddress = _geniAddress;
        geniContract = IGenius(_geniAddress);
        genftAddress = _genftControllerAddress;
        genftContract = IGenftController(_genftControllerAddress);
        stabilityAddress = _stabilityAddress;
        stabilityContract = IStability(_stabilityAddress);
        calendarAddress = _calendarAddress;
        calendarContract = ICalendar(_calendarAddress);

        // Switch the flag to 'true' so that the Grantor is locked out from
        // upgrading the contract addresses again in the future.
        appliedUpgrade = true;
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
     * @dev Users can purchase First Edition v2 GENFT Packs for as long as
     *      Edition v2 is the latest edition.  If Edition v2 is not the latest,
     *      users can still purchase from it ONLY for the first 365 Genius days.
     */
    modifier canPurchase(address paymentToken) {
        if (
            block.timestamp < LAUNCH_TIMESTAMP + 60 days
            && paymentToken != geniAddress
        ) {
            revert ErrorPobOnly();
        }

        if (
            genftContract.currentEdition().editionAddress != address(this)
            && calendarContract.getCurrentGeniusDay() > 365
        ) {
            revert ErrorEditionExpired();
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
        return _mintRand(to, rand1, rand2);
    }

    /**
     * @notice  mint ERC1155 token
     * @dev  private function, should be overriden in the implementation contract
     * should be called only by Gnft contract
     *
     * @param  to  receiver of the token
     * @param  rand1  random number 1
     * @param  rand2  random number 2
     */
    function _mintRand(
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

        if (0 == tokenToRarity[tokenId]) {
            tokenToRarity[tokenId] = rarity;
            tokenToVariety[tokenId] = variety;
        }
        _mint(to, tokenId, 1, "0x00");

        // NOTE: The examples below show how uri will be generated for opeansea
        // compatability.
        //
        // URI Example 1:
        // "ipfs://JGkARStQ5yBXgyfG2ZH3Jby8w6BgQmTRCQF5TrfB2hPjrD/Reserved.json"
        //
        // URI Example 2:
        // "ipfs://JGkARStQ5yBXgyfG2ZH3Jby8w6BgQmTRCQF5TrfB2hPjrD/0_1.json"
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
     * @notice  generates token id for unpacking BOOSTER token from rx and ry
     * @dev  private function
     *
     * @param   rand1  random number 1
     * @param   rand2  random number 2
     * @param   cardIndex  booster card index
     * @return  token id must be a number > 0
     */
    function _genTokenIdForBoosterUnpack(
        uint256 rand1,
        uint256 rand2,
        uint256 cardIndex
    )
        private
        view
        returns (
            uint256,
            uint8,
            uint8
        )
    {
        uint8 rarity;

        if (cardIndex == 0) {
            // Guaranteed to be Common.
            rarity = RARITY_COMMON;
        } else if (cardIndex == 1) {
            // normal possibilities for token minting.
            return _genTokenId(rand1, rand2);
        } else if (cardIndex == 2) {
            // Guaranteed to be Uncommon
            rarity = RARITY_UNCOMMON;
        } else if (cardIndex == 3) {
            // Scale down to 100,000 so the new percentages of minting an Amped
            // or Rare/Mythic is minted.
            rand1 %= 100000;

            if (rand1 < 3444) {
                // there is a 3.444% chance for an Amped Mythic
                rarity = RARITY_MYTHIC_AMPED;
            } else if (rand1 < 9017) {
                // there is a 5.573% chance for a Mythic: 9.017 - 3.444 = 5.573
                rarity = RARITY_MYTHIC;
            } else if (rand1 < 14590) {
                // 5.573% chance for an Amped Rare.
                rarity = RARITY_RARE_AMPED;
            } else if (rand1 < 38197) {
                // 23.607% chance for a Rare.
                rarity = RARITY_RARE;
            } else if (rand1 < 61804) {
                // 23.607% chance for an Amped Uncommon.
                rarity = RARITY_UNCOMMON_AMPED;
            } else {
                // The remainder (~38.2% chance) is for an Amped Common.
                rarity = RARITY_COMMON_AMPED;
            }
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
     * @notice  generates token id for unpacking ULTIMATE token from rx and ry
     * @dev  private function
     * @param   rand1  random number 1
     * @param   rand2  random number 2
     * @param   cardIndex ultimate card index
     * @return  token id must be a number > 0
     */
    function _genTokenIdForUltimateUnpack(
        uint256 rand1,
        uint256 rand2,
        uint256 cardIndex
    )
        private
        view
        returns (
            uint256,
            uint8,
            uint8
        )
    {
        uint8 rarity;
        if (cardIndex < 4) {
            // Guaranteed to be Common.
            rarity = RARITY_COMMON;
        } else if (cardIndex < 9) {
            // normal possibilities for token minting.
            return _genTokenId(rand1, rand2);
        } else if (cardIndex < 11) {
            // Guaranteed to be Uncommon.
            rarity = RARITY_UNCOMMON;
        } else if (cardIndex < 14) {
            // Guaranteed to be Uncommon or an Amped (Un)Common.
            // Scale down to 100,000 so percentages can be specified.
            rand1 %= 100000;

            if (rand1 < 10557) {
                // 10.557% chance for Amped Uncommon.
                rarity = RARITY_UNCOMMON;
            } else if (rand1 < 27639) {
                // 17.082% chance for Amped Common.
                rarity = RARITY_COMMON_AMPED;
            } else {
                // The remainder (~72.4% chance) is for an Uncommon.
                rarity = RARITY_UNCOMMON;
            }
        } else if (cardIndex == 14) {
            // Card 14 is guaranteed to be Amped; Common or Uncommon only.
            rand1 %= 100000;

            if (rand1 < 61803) {
                // 61.803% chance for an Amped Common.
                rarity = RARITY_COMMON_AMPED;
            } else {
                rarity = RARITY_UNCOMMON_AMPED;
            }
        } else {
            // The last card is guaranteed to be at least a Rare, and it could be Amped.
            rand1 %= 100000;

            if (rand1 < 9017) {
                // 9.017% Amped Mythic
                rarity = RARITY_MYTHIC_AMPED;
            } else if (rand1 < 23607) {
                // 14.59% Mythic
                rarity = RARITY_MYTHIC;
            } else if (rand1 < 38197) {
                // 14.59% Amped Rare
                rarity = RARITY_RARE_AMPED;
            } else {
                // The remainder (~61.8%) will be Rare.
                rarity = RARITY_RARE;
            }
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
     * @notice  burn token
     * @dev  burn tokn
     *
     * @param  from  account
     * @param  tokenId  token id
     * @param  amount  the quantity of the token IDs to burn.
     */
    function burn(
        address from,
        uint256 tokenId,
        uint256 amount
    ) external {
        _burn(from, tokenId, amount);
    }

    /**
     * @notice  define user mint setting
     * @dev  called only by oaGrantor
     * @param  colToken  payment token
     * @param  amount1  collateral amount cost to mint 1 "ULTIMATE PACK" NFT
     * @param  amount2  collateral amount cost to mint 1 "BOOSTER PACK" NFT
     */
    function defineUserMints(
        address colToken,
        uint256 amount1,
        uint256 amount2
    ) external onlyGrantor {
        // We are only allowed to define a user mint if 1) it is an existing
        // collateral in the Stability Pool and 2) it is an active collateral
        // currently accepted for the Stability Pool.
        if (
            !stabilityContract.existingCollaterals(colToken) ||
            !stabilityContract.activeCollaterals(colToken) ||
            amount1 == 0 ||
            amount2 == 0
        ) {
            revert ErrorInvalidSetting();
        }

        // create the new Mint Setting.
        MintSetting memory setting = MintSetting({
            feeForUltimate: amount1,
            feeForBooster: amount2
        });

        // if the setting already exists, then their value will be overwritten,
        // and that's ok :)
        mintSettings[colToken] = setting;
    }

    /**
     * @dev  remove mint setting for the payment token, called by only oaGrantor
     * @param  paymentToken  token address to be removed
     */
    function removeUserMint(address paymentToken)
        external
        onlyGrantor
    {
        if (mintSettings[paymentToken].feeForBooster == 0) {
            revert ErrorMintSettingDoesNotExist();
        }
        delete mintSettings[paymentToken];
    }

    /**
     * @dev  mint "ULTIMATE PACK" NFT with quantity
     * @param  paymentToken  token address for payout
     * @param  quantity  amount of token
     */
    function userMintUltimate(address paymentToken, uint256 quantity)
        external
        payable
        canPurchase(paymentToken)
    {
        if (mintSettings[paymentToken].feeForBooster == 0) {
            revert ErrorMintSettingDoesNotExist();
        }
        MintSetting memory setting = mintSettings[paymentToken];

        unchecked {
        // NOTE: start payment procedure
        uint256 totalFee = setting.feeForUltimate * quantity;

        if (paymentToken == address(0)) {
            // native token payment
            if (msg.value < totalFee) {
                revert ErrorInsufficientDeposit();
            }

            (bool success, ) = payable(royaltyAddress).call{
                value: msg.value
            }("");
            if (!success) {
                revert ErrorUnknown();
            }
        } else {
            // other ERC20 token payment
            IERC20(paymentToken).safeTransferFrom(
                msg.sender,
                royaltyAddress,
                totalFee
            );
        }
        // end payment procedure

        _mint(msg.sender, ULTIMATE_TOKEN_ID, quantity, "0x00");
        emit MintUltimatePacks(msg.sender, ULTIMATE_TOKEN_ID, quantity);
        } // end unchecked
    }

    /**
     * @dev mint "ULTIMATE PACK" NFT with quantity
     * @param paymentToken token address for payout
     * @param quantity amount of token
     * @param v signature value
     * @param r signature value
     * @param s signature value
     */

    // NOTE: "Standard" Permit.
    function userMintUltimatePermit(
        address paymentToken,
        uint256 quantity,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable canPurchase(paymentToken) {
        if (mintSettings[paymentToken].feeForBooster == 0) {
            revert ErrorMintSettingDoesNotExist();
        }
        MintSetting memory setting = mintSettings[paymentToken];

        unchecked {
        // NOTE: start payment procedure
        uint256 totalFee = setting.feeForUltimate * quantity;

        if (paymentToken == address(0)) {
            // native token payment
            if (msg.value < totalFee) {
                revert ErrorInsufficientDeposit();
            }
            (bool success, ) = payable(royaltyAddress).call{
                value: msg.value
            }("");
            if (!success) {
                revert ErrorUnknown();
            }
        } else {
            IERC20Permit(paymentToken).permit(
                msg.sender,
                address(this),
                totalFee,
                deadline,
                v,
                r,
                s
            );

            // ERC20 tokens other than Genius
            IERC20(paymentToken).safeTransferFrom(
                msg.sender,
                royaltyAddress,
                totalFee
            );
        }
        // end payment procedure

        // NOTE: start minting tokens
        _mint(msg.sender, ULTIMATE_TOKEN_ID, quantity, "0x00");
        emit MintUltimatePacks(msg.sender, ULTIMATE_TOKEN_ID, quantity);
        }   // end unchecked
    }

    /**
     * @dev    mint "ULTIMATE PACK" NFT with quantity with Dai permit
     * @param  paymentToken  token address for payout
     * @param  quantity  amount of token
     */
    function userMintUltimateDaiPermit(
        address paymentToken,
        uint256 quantity,
        uint256 nonce,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external canPurchase(paymentToken) {
        if (mintSettings[paymentToken].feeForBooster == 0) {
            revert ErrorMintSettingDoesNotExist();
        }
        MintSetting memory setting = mintSettings[paymentToken];

        unchecked {
        // NOTE: start payment procedure
        uint256 totalFee = setting.feeForBooster * quantity;
        // address holder, address spender, uint256 nonce, uint256 expiry,
        //        bool allowed, uint8 v, bytes32 r, bytes32 s
        IDaiPermit(paymentToken).permit(
            msg.sender,
            address(this),
            nonce,
            deadline,
            allowed,
            v,
            r,
            s
        );

        IERC20(paymentToken).safeTransferFrom(
            msg.sender,
            royaltyAddress,
            totalFee
        );

        _mint(msg.sender, ULTIMATE_TOKEN_ID, quantity, "0x00");
        emit MintUltimatePacks(msg.sender, ULTIMATE_TOKEN_ID, quantity);
        }   // end unchecked
    }

    /**
     * @dev    allows the user to unpack multiple ULTIMATE PACKS at once
     * @param  quantity  the amount for unpacking
     */
    function unpackUltimate(uint256 quantity) external {
        if (oneUnpackPerBlock[msg.sender][block.number]) {
            revert MustWaitAnotherBlock();
        }
        oneUnpackPerBlock[msg.sender][block.number] = true;

        // _burn will be reverted if he has insufficient quantity.
        // no need to catch it up
        _burn(msg.sender, ULTIMATE_TOKEN_ID, quantity);

        uint256[] memory tokens = new uint256[](ULTIMATE_YIELD * quantity);
        uint8[] memory rarities = new uint8[](ULTIMATE_YIELD * quantity);
        uint8[] memory varieties = new uint8[](ULTIMATE_YIELD * quantity);

        unchecked {
        for (uint256 i = 0; i < quantity; i++) {
            for (uint256 j = 0; j < ULTIMATE_YIELD; j++) {
                uint256 rRand = _random(msg.sender, 400999 + (i * quantity * ULTIMATE_YIELD + j));
                uint256 vRand = _random(msg.sender, 400999 + (i * quantity * ULTIMATE_YIELD + j + ULTIMATE_YIELD));
                (uint256 tokenId, uint8 rarity, uint8 variety) = _genTokenIdForUltimateUnpack(rRand, vRand, j);

                _mint(msg.sender, tokenId, 1, "0x00");
                tokens[i * ULTIMATE_YIELD + j] = tokenId;
                rarities[i * ULTIMATE_YIELD + j] = rarity;
                varieties[i * ULTIMATE_YIELD + j] = variety;
            }
        }

        emit UnpackUltimate(
            msg.sender,
            quantity,
            tokens,
            rarities,
            varieties
        );
        } // end unchecked
    }

    /**
     * @dev    mint "BOOSTER PACK" NFT with quantity
     * @param  paymentToken  token address for payout
     * @param  quantity  amount of token
     */
    function userMintBooster(address paymentToken, uint256 quantity)
        external
        payable
        canPurchase(paymentToken)
    {
        if (mintSettings[paymentToken].feeForBooster == 0) {
            revert ErrorMintSettingDoesNotExist();
        }
        MintSetting memory setting = mintSettings[paymentToken];

        unchecked {
        //NOTE: start payment procedure
        uint256 totalFee = setting.feeForBooster * quantity;
        if (paymentToken == address(0)) {
            // native token payment
            if (msg.value < totalFee) {
                revert ErrorInsufficientDeposit();
            }
            (bool success, ) = payable(royaltyAddress).call{
                value: msg.value
            }("");
            if (!success) {
                revert ErrorUnknown();
            }
        } else {
            // other ERC20 token payment
            IERC20(paymentToken).safeTransferFrom(
                msg.sender,
                royaltyAddress,
                totalFee
            );
        }
        // end payment procedure

        // NOTE: start minting tokens
        _mint(msg.sender, BOOSTER_TOKEN_ID, quantity, "0x00");
        emit MintBoosterPacks(msg.sender, BOOSTER_TOKEN_ID, quantity);
        } // end unchecked
    }

    /**
     * @dev    mint "BOOSTER PACK" NFT with quantity
     * @param  paymentToken  token address for payout
     * @param  quantity  amount of token
     */
    function userMintBoosterPermit(
        address paymentToken,
        uint256 quantity,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable canPurchase(paymentToken) {
        if (mintSettings[paymentToken].feeForBooster == 0) {
            revert ErrorMintSettingDoesNotExist();
        }
        MintSetting memory setting = mintSettings[paymentToken];

        unchecked {
        uint256 totalFee = setting.feeForBooster * quantity;

        //NOTE: start payment procedure
        if (paymentToken == address(0)) {
            // native token payment
            if (msg.value < totalFee) {
                revert ErrorInsufficientDeposit();
            }
            (bool success, ) = payable(royaltyAddress).call{
                value: msg.value
            }("");
            if (!success) {
                revert ErrorUnknown();
            }
        } else {
            IERC20Permit(paymentToken).permit(
                msg.sender,
                address(this),
                totalFee,
                deadline,
                v,
                r,
                s
            );
            // other ERC20 token payment
            IERC20(paymentToken).safeTransferFrom(
                msg.sender,
                royaltyAddress,
                totalFee
            );
        }
        // end payment procedure

        // NOTE: start minting tokens
        _mint(msg.sender, BOOSTER_TOKEN_ID, quantity, "0x00");
        emit MintBoosterPacks(msg.sender, BOOSTER_TOKEN_ID, quantity);
        } // end unchecked
    }

    /**
     * @dev    mint "BOOSTER PACK" NFT with quantity with Dai permit
     * @param  paymentToken  token address for payout
     * @param  quantity  amount of token
     */
    function userMintBoosterDaiPermit(
        address paymentToken,
        uint256 quantity,
        uint256 nonce,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external canPurchase(paymentToken) {
        if (mintSettings[paymentToken].feeForBooster == 0) {
            revert ErrorMintSettingDoesNotExist();
        }
        MintSetting memory setting = mintSettings[paymentToken];

        //NOTE: start payment procedure
        uint256 totalFee = setting.feeForBooster * quantity;

        // address holder, address spender, uint256 nonce, uint256 expiry,
        //        bool allowed, uint8 v, bytes32 r, bytes32 s
        IDaiPermit(paymentToken).permit(
            msg.sender,
            address(this),
            nonce,
            deadline,
            allowed,
            v,
            r,
            s
        );

        IERC20(paymentToken).safeTransferFrom(
            msg.sender,
            royaltyAddress,
            totalFee
        );

        _mint(msg.sender, BOOSTER_TOKEN_ID, quantity, "0x00");
        emit MintBoosterPacks(msg.sender, BOOSTER_TOKEN_ID, quantity);
    }

    /**
     * @dev    allows the user to unpack multiple BOOSTER PACKS at once
     * @param  quantity  the amount for unpacking
     */
    function unpackBooster(uint256 quantity) external {
        if (oneUnpackPerBlock[msg.sender][block.number]) {
            revert MustWaitAnotherBlock();
        }
        oneUnpackPerBlock[msg.sender][block.number] = true;

        // _burn will be reverted if he has sufficient quantity.
        // no need to catch it up
        _burn(msg.sender, BOOSTER_TOKEN_ID, quantity);

        // each booster will yield 4 GENFTs
        uint256[] memory tokens = new uint256[](BOOSTER_YIELD * quantity);
        uint8[] memory rarities = new uint8[](BOOSTER_YIELD * quantity);
        uint8[] memory varieties = new uint8[](BOOSTER_YIELD * quantity);

        unchecked {
        for (uint256 i = 0; i < quantity; i++) {
            for (uint256 j = 0; j < BOOSTER_YIELD; j++) {
                uint256 rRand = _random(msg.sender, 5500999 + (i * quantity * BOOSTER_YIELD + j));
                uint256 vRand = _random(msg.sender, 5500999 + (i * quantity * BOOSTER_YIELD + j + BOOSTER_YIELD));
                (uint256 tokenId, uint8 rarity, uint8 variety) = _genTokenIdForBoosterUnpack(rRand, vRand, j);

                _mint(msg.sender, tokenId, 1, "0x00");
                tokens[i * BOOSTER_YIELD + j] = tokenId;
                rarities[i * BOOSTER_YIELD + j] = rarity;
                varieties[i * BOOSTER_YIELD + j] = variety;
            }
        }

        emit UnpackBooster(
            msg.sender,
            quantity,
            tokens,
            rarities,
            varieties
        );
        } // end unchecked
    }

    function convert() external nonReentrant {
        // check if user is a holder of Edition 001 v1 NFTs
        uint256[] memory tokenIds = genftV1Contract.tokensByAccount(msg.sender);
        if (tokenIds.length == 0) {
            revert ErrorNotHolder();
        }

        // create an account array with the same address for batch process
        address[] memory accounts = new address[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            accounts[i] = msg.sender;
        }

        // getting balances for token Ids.
        uint256[] memory amounts = genftV1Contract.balanceOfBatch(
            accounts,
            tokenIds
        );

        // transfer the old GENFTs to the new contract edition001 v2.
        genftV1Contract.safeBatchTransferFrom(
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

        (uint256 tokenId, uint8 r, uint8 v) = _mintRand(
            _recipient,
            _random(_recipient, 8000000),
            _random(_recipient, 9000000)
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
    ) private returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(destination, amount));
        return MerkleProof.verify(merkleProof, MERKLE_ROOT, node);
    }

}
