//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "../util/FREEControllable.sol";
import "../util/FREEcommon.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

uint256 constant FREE_NUCLEUS_TOKEN_PRICE = 0.01 ether;

error ErrFREE_Nucleus_NotEnoughPaymentToMintNucleus(address receiver, uint256 payment, uint256 required_price);

error ErrFREE_Nucleus_InsufficientNucleusBalance(address owner, uint256 required_balance);

error ErrFREE_Nucleus_InvalidParams();

contract FREE_NucleusToken is Ownable, ReentrancyGuard 
{
    event Transfer(address indexed from, address indexed to, uint256 amount);

    event NucleusSpended(address indexed from);

    uint256 private _nucleus_token_price;
    uint256 private _total_supply;
    mapping(address => uint256) _nucleus_token_balance;

    constructor(address initialOwner) Ownable(initialOwner)
    {
        _nucleus_token_price = FREE_NUCLEUS_TOKEN_PRICE;
        _total_supply = 0;
    }

    function nucleus_token_price() external view returns(uint256)
    {
        return _nucleus_token_price;
    }

    /**
     *  Called from FREEDERATION.
     *  This only could mint 1 nucleus token at a time. Extra payment would be absorved by FREEDERATION
     */
    function nucleus_token_mint(address receiver, uint256 payment) external onlyOwner nonReentrant
    {
        if(payment < _nucleus_token_price)
        {
            revert ErrFREE_Nucleus_NotEnoughPaymentToMintNucleus(receiver, payment, _nucleus_token_price);
        }

        _nucleus_token_balance[receiver] += 1;
        _total_supply += 1;

        emit Transfer(address(this), receiver, 1);
    }

    /**
     * Called from FREEDERATION, for creating projects.
     * This spend 1 nucleus token. If not enough balance on receiver, it raises an error and reverts.
     */
    function spend_nucleus_token(address spender) external onlyOwner nonReentrant
    {
        if(spender == address(0))
        {
            revert ErrFREE_Nucleus_InvalidParams();
        }
        
        if(_nucleus_token_balance[spender] < 1)
        {
            revert ErrFREE_Nucleus_InsufficientNucleusBalance(spender, 1);
        }

        _nucleus_token_balance[spender] -= 1;
        emit NucleusSpended(spender);        
    }

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256)
    {
        return _total_supply;
    }

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256)
    {
        return _nucleus_token_balance[account];
    }

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external nonReentrant returns (bool)
    {
        address source = msg.sender;
        if(source == address(0) || to == address(0) || amount == 0 || source == to)
        {
            revert ErrFREE_Nucleus_InvalidParams();
        }

        if(_nucleus_token_balance[source] < amount)
        {
            return false;
        }

        _nucleus_token_balance[source] -= amount;
        _nucleus_token_balance[to] += amount;

        emit Transfer(source, to, amount);

        return true;
    }

}