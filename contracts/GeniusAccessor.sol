// SPDX-License-Identifier: UNLICENSED
// Genius is NOT LICENSED FOR COPYING.
// Genius (C) 2023. All Rights Reserved.
pragma solidity 0.8.4;

interface ICalendar {
    function getCurrentGeniusDay() external view returns (uint256);
}

interface IGenius {
    function oaGrantor() external view returns (address);

    function reserveSupply() external view returns (uint256);

    function endMiner(
        uint256 minerIndex,
        bool benevolence,
        bool mintNft
    ) external;

    function PHI() external view returns (uint256);

    function phase3() external view returns (bool);
}

// A.K.A. the Stability Pool
interface ICollateralVault {
    function existingCollaterals(address colToken) external view returns (bool);

    function activeCollaterals(address colToken) external view returns (bool);
}

interface IGenftController {
    struct Edition {
        address editionAddress;
        uint56 id;
        uint40 startTime;
    }

    function currentEdition() external view
        returns (IGenftController.Edition memory);

    // upgraded call
    function currentEditionAddress() external view returns (address);
}

/**
 * ACCESS TO GENIUS CORE FUNCTIONALITY
 */

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
function geniusRandom(
    address account,
    uint256 salt
) view returns (uint256) {
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
