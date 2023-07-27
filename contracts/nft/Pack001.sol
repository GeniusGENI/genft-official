// SPDX-License-Identifier: UNLICENSED
// Genius is NOT LICENSED FOR COPYING.
// Genius (C) 2023. All Rights Reserved.
pragma solidity 0.8.4;

import "../GeniusAccessor.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

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

interface IEdition {
    function mintById(
        address beneficiary,
        uint256 tokenId,
        uint256 quantity
    ) external;

    function packBurn(
        address account,
        uint256 packId,
        uint256 quantity
    ) external;
}


contract Pack001 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ErrorAlreadyUpgraded();
    error ErrorEditionExpired();
    error ErrorInsufficientDeposit();
    error ErrorInvalidGenius();
    error ErrorInvalidSetting();
    error ErrorMintSettingDoesNotExist();
    error ErrorNullAddress();
    error ErrorNotAllowed();
    error ErrorPobOnly();
    error ErrorUnknown();
    error MustWaitAnotherBlock();

    /**
     * Constants
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

    // deadline for permit
    uint256 constant deadline =
        0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // how many NFTs does an ultimate yield?
    uint256 constant ULTIMATE_YIELD = 16;
    uint256 constant BOOSTER_YIELD = 4;

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

    address public calendarAddress;
    address public genftControllerAddress;
    address public geniAddress;
    // NOTE: this is the Collateral Vault and Stability Pool
    address public cvAddress;
    // This is the edition that these packs belong to
    address public immutable editionAddress;
    address public immutable royaltyAddress;

    ICalendar calendarContract;
    IGenftController genftController;
    IGenius geniContract;
    ICollateralVault cvContract;
    IEdition immutable editionContract;

    // Once the upgrade is applied, this flag will prevent the contract from
    // being upgraded again.
    bool public contractLocked;
    uint256 public immutable LAUNCH_TIMESTAMP;

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
    mapping(address => uint256) private oneUnpackPerBlock;

    constructor(
        address _calendarAddress,
        address _cvAddress,
        // This Pack belongs to what edition?
        address _editionAddress,
        address _genftController,
        address _geniAddress,
        address _royaltyAddress
    ) {
        LAUNCH_TIMESTAMP = block.timestamp;

        if (
            _calendarAddress == address(0) ||
            _cvAddress == address(0) ||
            _editionAddress == address(0) ||
            _genftController == address(0) ||
            _geniAddress == address(0) ||
            _royaltyAddress == address(0)
        ) {
            revert ErrorNullAddress();
        }

        calendarAddress = _calendarAddress;
        cvAddress = _cvAddress;
        editionAddress = _editionAddress;
        genftControllerAddress = _genftController;
        geniAddress = _geniAddress;
        royaltyAddress = _royaltyAddress;

        calendarContract = ICalendar(_calendarAddress);
        cvContract = ICollateralVault(_cvAddress);
        editionContract = IEdition(_editionAddress);
        genftController = IGenftController(_genftController);
        geniContract = IGenius(_geniAddress);
    }

    /**
     * @dev  Check for EVIDENCE that the contract address is a Genius contract.
     */
    function _checkForGenius(address contractAddressToCheck) private view {
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
     * @param  _calendarAddress  Genius Calendar contract
     * @param  _genftController  The GENFT Controller contract address
     * @param  _geniAddress  Genius ERC20 contract
     */
    function upgrade(
        address _calendarAddress,
        address _genftController,
        address _geniAddress
    ) external onlyGrantor {
        // STEP 1: enforce that this function can only be called once.
        if (contractLocked) {
            revert ErrorAlreadyUpgraded();
        }

        // STEP 1: verify all contracts.  They must have Genius-specific
        // functionality to pass verification.
        //
        // Also, none of the new contract addresses can be equal to the prior
        // contract addresses.  Mixing old contracts with new contracts will
        // simply not function properly will the upgrade.
        _checkForGenius(_calendarAddress);
        _checkForGenius(_genftController);
        _checkForGenius(_geniAddress);

        // STEP 2: When upgrading, these contracts *must* have a new contract
        // address.
        if (
            _calendarAddress == calendarAddress ||
            _geniAddress == geniAddress ||
            _genftController == genftControllerAddress
        ) {
            revert ErrorInvalidGenius();
        }

        // STEP 3: update contracts to their upgraded version
        calendarAddress = _calendarAddress;
        genftControllerAddress = _genftController;
        geniAddress = _geniAddress;

        calendarContract = ICalendar(_calendarAddress);
        genftController = IGenftController(_genftController);
        geniContract = IGenius(_geniAddress);
    }

    /**
     * @dev Users can purchase First Edition v2 GENFT Packs for as long as
     *      Edition v2 is the latest edition.  If Edition v2 is not the latest,
     *      users can still purchase from it ONLY for the first 365 Genius days.
     */
    modifier canPurchase(address paymentToken) {
        // After Edition 001 / Pack 001, developers can simply use the first
        // condition's line to determine the first edition:
        address currentEdition = editionAddress;
        if (contractLocked) {
            currentEdition = genftController.currentEditionAddress();
        }
        else {
            currentEdition = genftController.currentEdition().editionAddress;
        }

        // Has the edition properly expired?  This Edition is only allowed to be
        // distributed while there is no newer edition AND we are beyond the
        // first 365 days of Genius.
        if (
            currentEdition != editionAddress &&
            calendarContract.getCurrentGeniusDay() > 365
        ) {
            revert ErrorEditionExpired();
        }

        // If Genius is UPGRADED (contract locked), then do not force end users
        // to do a Proof of Benevolence for pack purchasing.  Users will then be
        // allowed to purchase via methods other than POB.
        if (contractLocked) {
            _;
        }
        else if (
            // At this point, only GENI token may be used to purchase packs for
            // the first 60 days of the new Edition launch.
            block.timestamp < LAUNCH_TIMESTAMP + 60 days
            && paymentToken != geniAddress
        ) {
            revert ErrorPobOnly();
        }
        else {
            _;
        }
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
        rand1 %= 10**27;
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
            !cvContract.existingCollaterals(colToken) ||
            !cvContract.activeCollaterals(colToken) ||
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
    function removeUserMint(address paymentToken) external onlyGrantor {
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

        // NOTE: start payment procedure
        uint256 totalFee = setting.feeForUltimate * quantity;
        unchecked {

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

        editionContract.mintById(msg.sender, ULTIMATE_TOKEN_ID, quantity);
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

        // NOTE: start payment procedure
        uint256 totalFee = setting.feeForUltimate * quantity;
        unchecked {

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
        editionContract.mintById(msg.sender, ULTIMATE_TOKEN_ID, quantity);
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

        // NOTE: start payment procedure
        uint256 totalFee = setting.feeForBooster * quantity;
        unchecked {

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

        editionContract.mintById(msg.sender, ULTIMATE_TOKEN_ID, quantity);
        emit MintUltimatePacks(msg.sender, ULTIMATE_TOKEN_ID, quantity);
        } // end unchecked
    }

    /**
     * @dev    allows the user to unpack multiple ULTIMATE PACKS at once
     * @param  quantity  the amount for unpacking
     */
    function unpackUltimate(uint256 quantity) external nonReentrant {
        if (oneUnpackPerBlock[msg.sender] == block.number) {
            revert MustWaitAnotherBlock();
        }
        oneUnpackPerBlock[msg.sender] = block.number;

        // _burn will be reverted if he has insufficient quantity.
        // no need to catch it up
        editionContract.packBurn(msg.sender, ULTIMATE_TOKEN_ID, quantity);

        uint256[] memory tokens = new uint256[](ULTIMATE_YIELD * quantity);
        uint8[] memory rarities = new uint8[](ULTIMATE_YIELD * quantity);
        uint8[] memory varieties = new uint8[](ULTIMATE_YIELD * quantity);

        unchecked {
        for (uint256 i = 0; i < quantity; i++) {
            for (uint256 j = 0; j < ULTIMATE_YIELD; j++) {
                uint256 rRand = geniusRandom(msg.sender,
                    400999 + (i * quantity * ULTIMATE_YIELD + j));
                uint256 vRand = geniusRandom(msg.sender, 400999 + (
                    i * quantity * ULTIMATE_YIELD + j + ULTIMATE_YIELD));
                (uint256 tokenId, uint8 rarity, uint8 variety)
                    = _genTokenIdForUltimateUnpack(rRand, vRand, j);

                editionContract.mintById(msg.sender, tokenId, 1);
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

        //NOTE: start payment procedure
        uint256 totalFee = setting.feeForBooster * quantity;
        unchecked {

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
        editionContract.mintById(msg.sender, BOOSTER_TOKEN_ID, quantity);
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

        //NOTE: start payment procedure
        uint256 totalFee = setting.feeForBooster * quantity;
        unchecked {

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
        editionContract.mintById(msg.sender, BOOSTER_TOKEN_ID, quantity);
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
        unchecked {

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

        editionContract.mintById(msg.sender, BOOSTER_TOKEN_ID, quantity);
        emit MintBoosterPacks(msg.sender, BOOSTER_TOKEN_ID, quantity);
        } // end unchecked
    }

    /**
     * @dev    allows the user to unpack multiple BOOSTER PACKS at once
     * @param  quantity  the amount for unpacking
     */
    function unpackBooster(uint256 quantity) external nonReentrant {
        if (oneUnpackPerBlock[msg.sender] == block.number) {
            revert MustWaitAnotherBlock();
        }
        oneUnpackPerBlock[msg.sender] = block.number;

        // _burn will be reverted if he has sufficient quantity.
        // no need to catch it up
        editionContract.packBurn(msg.sender, BOOSTER_TOKEN_ID, quantity);

        // each booster will yield 4 GENFTs
        uint256[] memory tokens = new uint256[](BOOSTER_YIELD * quantity);
        uint8[] memory rarities = new uint8[](BOOSTER_YIELD * quantity);
        uint8[] memory varieties = new uint8[](BOOSTER_YIELD * quantity);

        unchecked {
        for (uint256 i = 0; i < quantity; i++) {
            for (uint256 j = 0; j < BOOSTER_YIELD; j++) {
                uint256 rRand = geniusRandom(msg.sender, 5500999 + (i * quantity * BOOSTER_YIELD + j));
                uint256 vRand = geniusRandom(msg.sender, 5500999 + (i * quantity * BOOSTER_YIELD + j + BOOSTER_YIELD));
                (uint256 tokenId, uint8 rarity, uint8 variety) = _genTokenIdForBoosterUnpack(rRand, vRand, j);

                editionContract.mintById(msg.sender, tokenId, 1);
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

}
