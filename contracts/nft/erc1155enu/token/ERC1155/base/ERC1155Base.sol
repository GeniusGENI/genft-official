// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import { ERC1155BaseInternal, ERC1155BaseStorage } from './ERC1155BaseInternal.sol';

/**
 * @title Base ERC1155 contract
 * @dev derived from https://github.com/OpenZeppelin/openzeppelin-contracts/ (MIT license)
 */
abstract contract ERC1155Base is ERC1155BaseInternal {

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(
        address account,
        uint256 id
    ) public view virtual override returns (uint256) {
        return _balanceOf(account, id);
    }

    /**
     * @dev See {IERC1155-balanceOfBatch}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(
        address[] memory accounts,
        uint256[] memory ids
    ) public view virtual override returns (uint256[] memory) {
        if (accounts.length != ids.length)
            revert ERC1155Base__ArrayLengthMismatch();

        mapping(uint256 => mapping(address => uint256))
            storage balances = ERC1155BaseStorage.layout().balances;

        uint256[] memory batchBalances = new uint256[](accounts.length);

        unchecked {
            for (uint256 i; i < accounts.length; i++) {
                if (accounts[i] == address(0))
                    revert ERC1155Base__BalanceQueryZeroAddress();
                batchBalances[i] = balances[ids[i]][accounts[i]];
            }
        }

        return batchBalances;
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(
        address account,
        address operator
    ) public view virtual override returns (bool) {
        return ERC1155BaseStorage.layout().operatorApprovals[account][operator];
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool status) public virtual override {
        if (msg.sender == operator) revert ERC1155Base__SelfApproval();
        ERC1155BaseStorage.layout().operatorApprovals[msg.sender][
            operator
        ] = status;
        emit ApprovalForAll(msg.sender, operator, status);
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender))
            revert ERC1155Base__NotOwnerOrApproved();
        _safeTransfer(msg.sender, from, to, id, amount, data);
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        if (from != msg.sender && !isApprovedForAll(from, msg.sender))
            revert ERC1155Base__NotOwnerOrApproved();
        _safeTransferBatch(msg.sender, from, to, ids, amounts, data);
    }
}
