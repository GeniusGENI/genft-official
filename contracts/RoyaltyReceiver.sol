// SPDX-License-Identifier: UNLICENSED
// Genius is NOT LICENSED FOR COPYING.
// This Royalty Receiver Contract is NOT LICENSED FOR COPYING.
// (C) 2023. All Rights Reserved.
pragma solidity 0.8.4;

import "./GeniusAccessor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";


struct Miner {
    bool policy;
    bool auctioned;
    bool exodus;
    uint16 startDay;
    uint16 promiseDays;
    uint16 lemClaimDay;
    uint88 rewardShares;
    uint96 penaltyDelta;
    bool nonTransferable;
    uint40 ended;
    uint64 principal;
    uint96 debtIssueRate;
}

interface IMiners {
    // The locked contract version for POB.  For the unlocked version, use the
    // dynamic calling method (function signature).
    function proofOfBenevolence(
        uint256 tokenAmount,
        address callbackContract,
        uint256 params,
        bool mintNft
    ) external;

    function minerStore(address owner, uint256 minerIndex)
        external view returns(Miner memory miner);
}

interface IStability {
    function issueGeniusDebt(
        address collateralToken,
        uint256 collateralAmount,
        uint256 promiseDays,
        bool mintNft
    ) external payable;

    function maxSystemDebt(uint256 supply) external view returns (uint256);

    function totalIssuedGenitos() external view returns (uint256);

    function issueRate(address token) external view returns (uint256);

    function maxTxDebt(uint256 supply) external view returns (uint256);

    function claimRefund() external;

    function expireOwnRefund() external;
}

interface IPenalty {
    function minerWeight(uint256 _principal) external view returns (uint256);
}

interface IGenftAbstract {
    function burn(address account, uint256 id, uint256 amount) external;

    function burnBatch(
        address account,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external;
}


contract RoyaltyReceiver is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Errors
    error ErrorTransfer();
    error ErrorNotAllowed();
    error ErrorNullAddress();
    error ErrorZeroBalance();
    error ErrorApproval();
    error ErrorIssuedGenitosInvalid();
    error ErrorNotEnoughWeight();
    error ErrorInvalidGenius();
    error ErrorAlreadyUpgraded();
    error ErrorNoMinersToEnd();
    error ErrorInvalidEdition();
    error ErrorNoSubscription();
    error ErrorExpiredSubscription();
    error ErrorBurnAmountInvalid();

    // Events
    event Log(string funcCode);
    event TokenTransferred(IERC20 token, address to, uint256 amount);

    // Constants
    string public constant RECEIVE_CODE = "receive";
    string public constant FALLBACK_CODE = "fallback";
    uint256 internal constant PHI = 1618033988749894848204586834;
    uint256 internal constant PHI_10_PERC = 161803398874989484820458683;
    uint256 internal constant PHI_NPOW_4 = 145898033750315455386239496;
    uint256 internal constant PHI_PRECISION = 1000000000000000000000000000;

    // Same as Penalty Counter Precision: 10 ** 12
    uint256 internal constant WEIGHT_PRECISION = 10**12;
    uint256 internal constant MAX_GENITO_PRINCIPAL = 4444000000000000000;
    // GENIUS PRECISION
    uint256 internal constant GENIUS_PRECISION = 10**9;
    uint256 internal constant MAX_ISSUED_GENITOS = 2**254 - 1;

    // Variables
    uint256 public nextMinerToEnd;
    uint256 public totalMiners;

    address public calendarAddress;
    address public currentEditionCache;
    address public genftControllerAddress;
    address public geniAddress;
    address public minersAddress;
    address public penaltyAddress;
    address public stabilityAddress;

    ICalendar public calendarContract;
    IGenftController public genftControllerContract;
    IGenius public geniContract;
    IMiners public minersContract;
    IStability public stabilityContract;

    /**
     * RRC Subscriber: these users can claim the revenue opportunities.
     * address  the subscriber's account (msg.sender)
     * uint40  when their subscription expires
     */
    mapping(address => uint40) public subscription;
    // The (default) cost to subscribe to this contract's revenue features.
    uint256 public subWeeklyBurnCost = 2;
    uint256 public subMonthlyBurnCost = 7;

    // deadline for permit
    uint256 deadline =
        0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 maxFee =
        0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // Once the upgrade is applied, this flag will prevent the contract from
    // being upgraded again.
    bool public contractLocked;

    /**
     * @dev Fallback function must be declared as external
     */
    fallback() external payable {
        // send / transfer (forwards 2300 gas to this fallback function)
        // call (forwards all of the gas)
        emit Log(FALLBACK_CODE);
    }

    /**
     *  @dev  Receive is a variant of fallback that is triggered when msg.data
     *        is empty.
     */
    receive() external payable {
        emit Log(RECEIVE_CODE);
    }

    // Payable constructor allows the contract to receive Ether
    constructor(
        address _calendarAddress,
        address _geniAddress,
        address _genftControllerAddress,
        address _minersAddress,
        address _penaltyAddress,
        address _stabilityAddress
    ) payable {
        // Since we cannot "Check for Genius" (the next function implemented)
        // at this point, checking for a zero address will suffice.  It is the
        // 'upgrade' function that will inevitably do a valid "Check for
        // Genius".
        if (
            _calendarAddress == address(0) ||
            _geniAddress == address(0) ||
            _stabilityAddress == address(0) ||
            _minersAddress == address(0) ||
            _penaltyAddress == address(0) ||
            _genftControllerAddress == address(0)
        ) {
            revert ErrorNullAddress();
        }

        calendarAddress = _calendarAddress;
        genftControllerAddress = _genftControllerAddress;
        geniAddress = _geniAddress;
        minersAddress = _minersAddress;
        penaltyAddress = _penaltyAddress;
        stabilityAddress = _stabilityAddress;

        calendarContract = ICalendar(_calendarAddress);
        genftControllerContract = IGenftController(_genftControllerAddress);
        geniContract = IGenius(_geniAddress);
        minersContract = IMiners(_minersAddress);
        stabilityContract = IStability(_stabilityAddress);
    }

    function setWeeklyBurnCost(uint256 _amount) external {
        if (msg.sender != geniContract.oaGrantor()) {
            revert ErrorNotAllowed();
        }

        if (_amount == 0) {
            // alert the Grantor that the cost must be at least 1 GENFT.
            revert ErrorBurnAmountInvalid();
        }

        if (_amount >= subMonthlyBurnCost) {
            revert ErrorBurnAmountInvalid();
        }
        subWeeklyBurnCost = _amount;
    }

    function setMonthlyBurnCost(uint256 _amount) external {
        if (msg.sender != geniContract.oaGrantor()) {
            revert ErrorNotAllowed();
        }
        if (_amount <= subWeeklyBurnCost) {
            // alert the Grantor that the Monthly cost must greater than the
            // Weekly burn cost.
            revert ErrorBurnAmountInvalid();
        }
        subMonthlyBurnCost = _amount;
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
    function lockContract() external {
        if (msg.sender != geniContract.oaGrantor()) {
            revert ErrorNotAllowed();
        }
        contractLocked = true;
    }

    /**
     * @dev  Allows the Grantor one chance to change/update the contract
     *       addresses.  This will be only for a future upgrade.
     * @param  _geniAddress  Genius ERC20 contract
     * @param  _genftControllerAddress  The GENFT Controller contract
     * @param  _stabilityAddress  Genius "Stability Pool" (Collateral Vault)
     *                            contract.
     * @param  _minersAddress  Genius Miners contract
     * @param  _penaltyAddress  Penalty calculations and voting weight contract
     */
    function upgrade(
        address _calendarAddress,
        address _geniAddress,
        address _genftControllerAddress,
        address _stabilityAddress,
        address _minersAddress,
        address _penaltyAddress
    ) external {
        // STEP 0: enforce that this function can only be called once.
        if (contractLocked) {
            revert ErrorAlreadyUpgraded();
        }

        // STEP 1: only the Genius Grantor (of the current Genius contract) can
        // call this.
        if (msg.sender != geniContract.oaGrantor()) {
            revert ErrorNotAllowed();
        }

        // STEP 2: verify all contracts.  They must have Genius-specific
        // functionality to pass verification.
        //
        // Also, none of the new contract addresses can be equal to the prior
        // contract addresses.  Mixing old contracts with new contracts will
        // simply not function properly will the upgrade.
        _checkForGenius(_calendarAddress);
        _checkForGenius(_geniAddress);
        _checkForGenius(_genftControllerAddress);
        _checkForGenius(_stabilityAddress);
        _checkForGenius(_minersAddress);
        _checkForGenius(_penaltyAddress);

        // When upgrading, these contracts *must* have a new contract address
        if (
            _calendarAddress == calendarAddress ||
            _geniAddress == geniAddress ||
            _genftControllerAddress == genftControllerAddress ||
            _stabilityAddress == stabilityAddress ||
            _minersAddress == minersAddress ||
            _penaltyAddress == penaltyAddress
        ) {
            revert ErrorInvalidGenius();
        }

        // STEP 3: update contracts to their upgraded version
        calendarAddress = _calendarAddress;
        genftControllerAddress = _genftControllerAddress;
        geniAddress = _geniAddress;
        minersAddress = _minersAddress;
        penaltyAddress = _penaltyAddress;
        stabilityAddress = _stabilityAddress;

        calendarContract = ICalendar(_calendarAddress);
        genftControllerContract = IGenftController(_genftControllerAddress);
        geniContract = IGenius(_geniAddress);
        minersContract = IMiners(_minersAddress);
        stabilityContract = IStability(_stabilityAddress);
    }

    /**
     * @dev  wrapper to only allow the current edition to be specified
     * @param  _edition  the ERC-1155 contract address
     */
    modifier editionIsCurrent(address _edition) {
        if (_edition != currentEditionCache) {
            // The latest edition could have been updated, so grab the latest
            // value from Genius!
            if (contractLocked) {
                currentEditionCache = genftControllerContract
                    .currentEditionAddress();
            }
            else {
                currentEditionCache = genftControllerContract
                    .currentEdition().editionAddress;
            }

            if (currentEditionCache != _edition) {
                revert ErrorInvalidEdition();
            }
            _;
        }
        else {
            // if the _edition parameter is address(0), we do not need to revert
            // because the null address will never issue GENFTs :D  ...right? ;)
            _;
        }
    }

    /**
     * @dev subscription cost: 2 GENFTs per week, 6 per month, max 6.
     * @param  edition  The GENFTs can only be from 1 edition per End Miner tx.
     * @param  genftIds  the GENFTs to burn
     * @param  amounts  the quantity of the GENFT IDs to burn.
     */
    function subscribe(
        address edition,
        uint256[] calldata genftIds,
        uint256[] calldata amounts
    ) external editionIsCurrent(edition) {
        uint256 tokensToBurn;
        for (uint256 i = 0; i < amounts.length; ) {
            unchecked {
            tokensToBurn += amounts[i];
            i++;
            }
        }

        // STEP 1: ensure the proper amount of GENFTs is selected
        // We need to revert if the amount of tokens to burn is 0, 1, 3, 5.
        //
        // 2 = 1-week sub
        // 4 = 2-week sub
        // 6 = 3-week sub
        // 7 = 1-month sub
        //
        // Therefore, revert as an invalid amount if:
        //      burn < (monthly cost) && burn % (weekly cost) != 2
        //      burn == 0
        //
        // 'burn' can be greater than 7 because the user is allowed to burn more
        // GENFTs for the sake of burning.

        if (
            (tokensToBurn < subMonthlyBurnCost
                && tokensToBurn % subWeeklyBurnCost != 0)
            || tokensToBurn == 0
        ) {
            // NOTE: if genftIds array length does not match amounts, then the
            // ERC1155 burn functionality will revert due to a requirement not
            // being met.
            revert ErrorBurnAmountInvalid();
        }

        // STEP 2: if the subscription is not already setup, then set it up!
        if (subscription[msg.sender] < block.timestamp) {
            subscription[msg.sender] = uint40(block.timestamp);
        }

        // STEP 3: add the subscription time for the subscriber.  Here, we will
        // do the subscription for monthly or weekly for X weeks.
        // Therefore, do monthly if:
        //      burn >= (monthly cost)
        unchecked {
        if (tokensToBurn >= subMonthlyBurnCost) {
            // Subscribe the user for 1 month
            subscription[msg.sender] += 30 days;
        }
        else {
            // Subscribe the user for either 1, 2, etc. weeks
            subscription[msg.sender] += uint40(7 days * tokensToBurn / 2);
            // ^-- + 7 days * burn / (weekly cost)
        }
        } // end unchecked

        // Finally: accept the payment :)
        IGenftAbstract(edition).burnBatch(msg.sender, genftIds, amounts);
    }

    /**
     * @dev    Pay the EOA an amount of native tokens as a reward.  Before
     *         calling this function, check that the 'reward' is greater than
     *         zero.  All calls to this function, at the moment of this commit,
     *         have code that ensures the 'reward' parameter is > 0.
     *
     * @param  reward  the amount to pay in the native token's smallest units.
     */
    function _payEoaNativeToken(uint256 reward) private {
        (bool success, ) = payable(msg.sender).call{value: reward}("");
        if (!success) {
            revert ErrorTransfer();
        }
    }

    /**
     * @dev  get the balance of the contract for a given token (native, erc20)
     * @param  tokenAddress  the address of the token to retrieve balance for
     */
    function balanceOf(address tokenAddress) external view returns (uint256) {
        return tokenAddress == address(0) ?
            address(this).balance :
            IERC20(tokenAddress).balanceOf(address(this));
    }

    /**
     * @dev checks the user's subscription; either reverts or returns True.
     * @return  bool  always true -- will revert if false
     */
    function _checkUserSubscription() private view returns (bool) {
        if (block.timestamp > subscription[msg.sender]) {
            if (subscription[msg.sender] == 0) {
                revert ErrorNoSubscription();
            }
            // The subscription has expired
            revert ErrorExpiredSubscription();
        }

        return true;
    }

    /**
     * @dev  End a collateral miner, current miner index increased.  The msg
     *       sender receives a reward of the collateral (or all) of their choice
     *       from the Royalty Receiver pool.  Why not choose all collaterals?
     *       Because it may not be worth the gas!
     * @param  targetTokens  The Collateral tokens that will reward the caller.
     * @param  edition  The GENFTs can only be from 1 edition per End Miner tx.
     * @param  genftIds  the GENFT IDs that will be burned for payment
     * @param  amounts  the amount to be burned per GENFT
     */
    function endMiner(
        address[] calldata targetTokens,
        address edition,
        uint256[] calldata genftIds,
        uint256[] calldata amounts
    ) external editionIsCurrent(edition) nonReentrant {
        if (nextMinerToEnd == totalMiners) {
            revert ErrorNoMinersToEnd();
        }
        uint256 totalTargetedTokens = targetTokens.length;

        // STEP 1: only allow subscribers to end miners
        {
            Miner memory miner = minersContract.minerStore(address(this),
                nextMinerToEnd);

            uint256 currentGeniusDay = calendarContract.getCurrentGeniusDay();
            bool subscribed;

            // if the next miner to end is within the 7-day grace period, require
            // that the msg.sender is subscribed in order to call this function.
            if (currentGeniusDay < miner.startDay + miner.promiseDays + 7) {
                subscribed = _checkUserSubscription();
            }
            else {
                // if we are outside of the 7-day grace period, then anyone is
                // allowed to call this--whether they are a subscriber or not.
                subscribed = block.timestamp < subscription[msg.sender];
            }

            // STEP 1A: end the miner
            geniContract.endMiner(nextMinerToEnd, true, false);
            unchecked { nextMinerToEnd++; }

            // STEP 1B: handle the GENFT "burn payment" -- depending on how many
            // token rewards were claimed.  The msg.sender will not receive a reward
            // if they did not specify any tokens OR if they have not subscribed!
            if (totalTargetedTokens == 0 || !subscribed) {
                return;
            }
        }

        // STEP 2:
        // Gather the number of tokens to burn -- must be >= number of tokens
        // to gather the reward for.  NOTE: it is possible and allowed to burn
        // more tokens than necessary.
        {
            uint256 tokensToBurn;
            for (uint256 i = 0; i < amounts.length; ) {
                unchecked {
                tokensToBurn += amounts[i];
                i++;
                }
            }

            // NOTE: the amount of tokens to be burned is allowed to be more
            // than 1 GENFT per 'token commission reward' paid to the user.
            // This allows end users to burn more tokens for the sake of burning
            // and making a GENFT more rare :)
            if (tokensToBurn < totalTargetedTokens) {
                revert ErrorBurnAmountInvalid();
            }
        }

        // STEP 3: accept the payment :)
        IGenftAbstract(edition).burnBatch(msg.sender, genftIds, amounts);

        // STEP 4: pay out rewards to msg.sender
        // caller will receive ~14.5% of the balance of all tokens specified.
        //
        // NOTE: the tokens must have a balance of at least 7 of the smallest
        // units in order for the EOA to receive any reward.

        for (uint256 i = 0; i < totalTargetedTokens; ) {
            uint256 balance = targetTokens[i] == address(0)
                ? address(this).balance
                : IERC20(targetTokens[i]).balanceOf(address(this));
            if (balance < 7) {
                continue;
            }

            uint256 reward;
            unchecked {
                reward = balance * PHI_NPOW_4 / PHI_PRECISION;
            }

            // Handle native token
            if (targetTokens[i] == address(0)) {
                _payEoaNativeToken(reward);
            }
            else {
                IERC20(targetTokens[i]).transfer(msg.sender, reward);
            }

            unchecked { i++; }
        }
    }

    /**
     * @dev    deploy token
     * @param  token  will be used mint the new miner
     * @param  edition  the current edition for the GENFT to burn
     * @param  genft  the GENFT ID that will be burned
     * @param  force  the token will be 'deployed' for benefitting Genius users
     *                even if the resulting miner is smaller than average.
     */
    function deployToken(
        address token,
        address edition,
        uint256 genft,
        bool force
    ) external editionIsCurrent(edition) nonReentrant {
        _checkUserSubscription();

        // First: burn the GENFT token
        unchecked {
            IGenftAbstract(edition).burn(msg.sender, genft, 1);
        }

        uint256 balance = token == address(0)
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));
        if (balance == 0) {
            revert ErrorZeroBalance();
        }

        // 1,000 trillion units for a 18 precision token, 27 precision PHI_10.
        // This will not overflow.
        uint256 reward;
        // If the token is not GENI, then we need to figure out the amount of
        // Genius Credit.
        uint256 geniCreditAmount;

        unchecked {
            reward = balance * PHI_10_PERC / PHI_PRECISION;
            geniCreditAmount = token != geniAddress
                ? _calcGeniusDebtToIssue(token, balance - reward)
                : balance;
        }

        uint256 weight = IPenalty(penaltyAddress).minerWeight(geniCreditAmount);

        // Scenario 0: the weight of the miner we are about to create is larger
        // than the average miner, and therefore the EOA will receive a reward.
        if (weight > WEIGHT_PRECISION && reward > 0) {
            // send the EOA their reward
            if (token == address(0)) {
                _payEoaNativeToken(reward);
            }
            else {
                IERC20(token).transfer(msg.sender, reward);
            }

            unchecked { balance -= reward; }
        }
        else if (!force && reward > 0) {
            // Revert if there's not enough weight.
            revert ErrorNotEnoughWeight();
        }

        // Scenario 1: Issue Genius Credit.
        // This will revert if the Collateral Vault is no-longer accepting the
        // token to issue credit or if there are any other issues.
        if (token != geniAddress) {
            // If this is NOT the native token and we cannot approve the ERC20
            if (
                token != address(0) &&
                !IERC20(token).approve(address(stabilityContract), balance)
            ) {
                revert ErrorApproval();
            }

            if (token == address(0)) {
                stabilityContract.issueGeniusDebt{ value: balance }(
                    token, balance, 90, false
                );
            }
            else {
                stabilityContract.issueGeniusDebt(token, balance, 90, false);
            }

            unchecked { totalMiners++; }
            return;
        }

        // Scenario 2: Proof of Benevolence GENI tokens.
        IERC20(token).approve(address(minersContract), balance);
        if (contractLocked) {
            // Post-Lock: token amount, call-back contract (will be NULL),
            // parameters (none), and False so no GENFT is minted.
            minersContract.proofOfBenevolence(
                balance,
                address(0),
                0,
                false
            );
        }
        else {
            (bool success,) = minersAddress.call(
                abi.encodeWithSignature(
                    "proofOfBenevolence(uint256,address,address,bool)",
                    balance, geniAddress, address(0), false
                )
            );

            if (!success) {
                revert ErrorInvalidGenius();
            }
        }   // end if contract locked (doing Proof of Benevolence)
    }

    /**
     * @dev Unlocks the Collateral Vault Refund for this RRC contract's
     *      account.
     */
    function unlockCvRefund() external {
        // If GENI is in Phase 3, then it's better to "expire" the RRC's own
        // refund.  Everyone profits.  Only do this if the contract is locked,
        // meaning that the ability to expire one's own refund BEFORE THE
        // EXPIRATION TIME will be available.

        if (contractLocked && geniContract.phase3()) {
            stabilityContract.expireOwnRefund();
            return;
        }

        // If there is any issue, function will revert ErrorNativeTokenTransfer
        stabilityContract.claimRefund();
    }

    /**
     * @dev    calculate Genius debt to be issued - internal function
     * @param  token  will be used mint the new miner
     * @param  amount  token amount
     */
    function _calcGeniusDebtToIssue(address token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        uint256 rSupply = geniContract.reserveSupply();
        uint256 localMaxSystemDebt = stabilityContract.maxSystemDebt(rSupply);
        uint256 rate = stabilityContract.issueRate(token);
        uint256 totalIssuedGenitos = stabilityContract.totalIssuedGenitos();
        uint256 maxTxDebt = stabilityContract.maxTxDebt(rSupply);

        unchecked {
        uint256 geniusDebtAmount = amount * GENIUS_PRECISION / rate;
        uint256 newIssuedGenitos = geniusDebtAmount > maxTxDebt
            ? maxTxDebt : geniusDebtAmount;

        if (totalIssuedGenitos + newIssuedGenitos > localMaxSystemDebt) {
            newIssuedGenitos = localMaxSystemDebt - totalIssuedGenitos;
        }

        if (newIssuedGenitos > MAX_GENITO_PRINCIPAL) {
            newIssuedGenitos -= MAX_GENITO_PRINCIPAL;
        }

        if (totalIssuedGenitos + newIssuedGenitos > MAX_ISSUED_GENITOS) {
            newIssuedGenitos = MAX_ISSUED_GENITOS - totalIssuedGenitos;
        }
        if (newIssuedGenitos == 0) revert ErrorIssuedGenitosInvalid();

        return newIssuedGenitos;
        } // end unchecked
    }

}
