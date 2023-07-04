// SPDX-License-Identifier: UNLICENSED
// Genius is NOT LICENSED FOR COPYING.
// This Royalty Receiver Contract is NOT LICENSED FOR COPYING.
// (C) 2023. All Rights Reserved.
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IGenius {
    function oaGrantor() external view returns (address);

    function reserveSupply() external view returns (uint256);

    function endMiner(
        uint256 minerIndex,
        bool benevolence,
        bool mintNft
    ) external;

    function PHI() external view returns (uint256);
}

interface IMiners {
    function proofOfBenevolence(
        uint256 tokenAmount,
        address settleCollateral,
        address callbackContract,
        bool mintNft
    ) external;

    function PHI() external view returns (uint256);
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

    function PHI() external view returns (uint256);
}

interface IPenalty {
    function minerWeight(uint256 _principal) external view returns (uint256);

    function PHI() external view returns (uint256);
}

interface IGenftController {
    function PHI_PRECISION() external view returns (uint256);
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

    address public stabilityAddress;
    IStability public stabilityContract;
    address public minersAddress;
    IMiners public minersContract;
    address public geniAddress;
    IGenius public geniContract;
    address public genftControllerAddress;
    IGenftController public genftControllerContract;
    address public penaltyAddress;

    // deadline for permit
    uint256 deadline =
        0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 maxFee =
        0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // Once the upgrade is applied, this flag will prevent the contract from
    // being upgraded again.
    bool public appliedUpgrade = false;

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
        address _geniAddress,
        address _stabilityAddress,
        address _minersAddress,
        address _penaltyAddress,
        address _genftControllerAddress
    ) payable {
        // Since we cannot "Check for Genius" (the next function implemented)
        // at this point, checking for a zero address will suffice.  It is the
        // 'upgrade' function that will inevitably do a valid "Check for
        // Genius".
        if (
            _geniAddress == address(0) ||
            _stabilityAddress == address(0) ||
            _minersAddress == address(0) ||
            _penaltyAddress == address(0) ||
            _genftControllerAddress == address(0)
        ) {
            revert ErrorNullAddress();
        }

        geniAddress = _geniAddress;
        geniContract = IGenius(_geniAddress);
        stabilityAddress = _stabilityAddress;
        stabilityContract = IStability(_stabilityAddress);
        minersAddress = _minersAddress;
        minersContract = IMiners(_minersAddress);
        penaltyAddress = _penaltyAddress;
        genftControllerAddress = _genftControllerAddress;
        genftControllerContract = IGenftController(_genftControllerAddress);
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
     * @param  _minersAddress  Genius Miners contract
     * @param  _penaltyAddress  Penalty calculations and voting weight contract
     */
    function upgrade(
        address _geniAddress,
        address _genftControllerAddress,
        address _stabilityAddress,
        address _minersAddress,
        address _penaltyAddress
    ) external {
        // STEP 0: enforce that this function can only be called once.
        if (appliedUpgrade) {
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
        _checkForGenius(_geniAddress);
        _checkForGenius(_stabilityAddress);
        _checkForGenius(_minersAddress);
        _checkForGenius(_penaltyAddress);

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
            _genftControllerAddress == genftControllerAddress ||
            _stabilityAddress == stabilityAddress ||
            _minersAddress == minersAddress ||
            _penaltyAddress == penaltyAddress
        ) {
            revert ErrorInvalidGenius();
        }

        // STEP 3: update contracts to their upgraded version
        geniAddress = _geniAddress;
        geniContract = IGenius(_geniAddress);
        genftControllerAddress = _genftControllerAddress;
        stabilityAddress = _stabilityAddress;
        stabilityContract = IStability(_stabilityAddress);
        minersAddress = _minersAddress;
        minersContract = IMiners(_minersAddress);
        penaltyAddress = _penaltyAddress;

        // STEP 4:
        // Switch the flag to 'true' so that the Grantor is locked out from
        // upgrading the contract addresses again in the future.
        appliedUpgrade = true;
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
     * @dev  End a collateral miner, current miner index increased.  The msg
     *       sender receives a reward of the collateral (or all) of their choice
     *       from the Royalty Receiver pool.  Why not choose all collaterals?
     *       Because it may not be worth the gas!
     */
    function endMiner(address[] calldata tokens) external nonReentrant {
        if (nextMinerToEnd == totalMiners) {
            revert ErrorNoMinersToEnd();
        }

        geniContract.endMiner(nextMinerToEnd, true, false);
        nextMinerToEnd++;

        if (tokens.length == 0) {
            return;
        }

        // caller will receive ~14.5% of the balance of all tokens.  NOTE: the
        // tokens must have a balance of at least 7 of the smallest units in
        // order for the EOA to receive any reward.
        unchecked {
        for (uint i = 0; i < tokens.length; i++) {
            uint256 balance = tokens[i] == address(0)
                ? address(this).balance
                : IERC20(tokens[i]).balanceOf(address(this));
            if (balance < 7) {
                continue;
            }

            uint256 reward = balance * PHI_NPOW_4 / PHI_PRECISION;

            // Handle native token
            if (tokens[i] == address(0)) {
                _payEoaNativeToken(reward);
            }
            else if (tokens[i] != geniAddress) {
                // Handle ERC-20s other than GENI
                IERC20(tokens[i]).transfer(msg.sender, reward);
            }
        }
        }   // end unchecked
    }

    /**
     * @dev    deploy token
     * @param  token  will be used mint the new miner
     * @param  force  the token will be 'deployed' for benefitting Genius users
     *                even if the resulting miner is smaller than average.
     */
    function deployToken(address token, bool force) external nonReentrant {
        uint256 balance = token == address(0)
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));
        if (balance == 0) {
            revert ErrorZeroBalance();
        }

        // 1 trillion units for a 18 precision token, 27 precision PHI_10.
        // This will not overflow.
        uint256 reward = balance * PHI_10_PERC / PHI_PRECISION;

        // If the token is not GENI, then we need to figure out the amount of
        // Genius Credit.
        uint256 geniCreditAmount = token != geniAddress
            ? _calcGeniusDebtToIssue(token, balance - reward)
            : balance;
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

            balance -= reward;
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

            uint256 newBalance = token == address(0)
                ? address(this).balance
                : IERC20(token).balanceOf(address(this));

            if (token == address(0)) {
                stabilityContract.issueGeniusDebt{ value: balance }(
                    token, balance, 90, false
                );
            }
            else {
                stabilityContract.issueGeniusDebt(token, balance, 90, false);
            }

            totalMiners++;
            return;
        }

        // Scenario 2: Proof of Benevolence GENI tokens.
        IERC20(token).approve(address(minersContract), balance);
        minersContract.proofOfBenevolence(
            balance,
            geniAddress,
            address(0),
            false
        );
    }

    /**
     * @dev Unlocks the Collateral Vault Refund for this RRC contract's
     *      account.
     */
    function unlockCvRefund() external {
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
        uint256 geniusDebtAmount = amount * GENIUS_PRECISION / rate;
        uint256 totalIssuedGenitos = stabilityContract.totalIssuedGenitos();

        uint256 maxTxDebt = stabilityContract.maxTxDebt(rSupply);
        uint256 newIssuedGenitos = geniusDebtAmount > maxTxDebt
            ? maxTxDebt : geniusDebtAmount;
        delete maxTxDebt;

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
    }

}
