// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ERC1155EnumerableInternal, ERC1155EnumerableStorage } from './ERC1155EnumerableInternal.sol';

/**
 * @title ERC1155 implementation including enumerable and aggregate functions
 */
abstract contract ERC1155Enumerable is
    ERC1155EnumerableInternal
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    /**
     * @notice query total minted supply of given token
     * @param id token id to query
     * @return token supply
     */
    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply(id);
    }

    /**
     * @notice query total number of holders for given token
     * @param id token id to query
     * @return quantity of holders
     */
    function totalHolders(uint256 id) public view virtual returns (uint256) {
        return _totalHolders(id);
    }

    /**
     * @notice query holders of given token
     * @param id token id to query
     * @return list of holder addresses
     */
    function accountsByToken(
        uint256 id
    ) public view virtual returns (address[] memory) {
        return _accountsByToken(id);
    }

    /**
     * @notice query tokens held by given address
     * @param account address to query
     * @return list of token ids
     */
    function tokensByAccount(
        address account
    ) public view virtual returns (uint256[] memory) {
        return _tokensByAccount(account);
    }
}
