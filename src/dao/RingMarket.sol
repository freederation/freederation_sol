//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "../util/FREEControllable.sol";
import "../util/FREEAssetOwnership.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

error ErrDAO_RingTokenAlreadyExists(uint256 tokenID);

error ErrDAO_RingGroupAlreadyCompleted(uint256 groupID);

error ErrDAO_RingEquityAlreadyCompleted(uint256 groupID);

error ErrDAO_InvalidRingToken(uint256 tokenID);

error ErrDAO_InvalidRingGroup(uint256 groupID);

error ErrDAO_InvalidRingEquity(uint256 equityID);

error ErrDAO_RingEquityDoesNotBelongToSameGroup(uint256 equityID, uint256 groupID);

error ErrDAO_RingTokenAlreadyBelongsToEquity(uint256 tokenID, uint256 equityID);

error ErrDAO_NotAuthorizedToUseRingToken(uint256 tokenID, address operator);

error ErrDAO_CannotPurchaseRingToken(uint256 tokenID, uint256 listingprice);


struct RingToken
{
    /**
     * Group to which this token belongs to. Should be greater than 0.
     */
    uint256 groupID;


    /**
     * 0 by default.
     * If Not 0, this ring could be purchased instantaneously
     */
    uint256 listing_price;
    
    /**
     * 0 by default.
     * If Not 0, this ring is locked to an equity.
     */
    uint256 equityID;
    
    /**
     * Linked list of connected rings
     */
    uint256 next_ring;
}

struct RingGroup
{
    /**
     * This number is incremented through group size.
     */
    uint32 num_rings;
    
    /**
     * This equity is complete if equity_count == num_rings == group_size
     */
    uint32 equity_count;

    /**
     * Linked list of rings
     */
    uint256 ring_list;

    /**
     * Linked list of equity groups
     */
    uint256 equity_list;


    /**
     * The leading equity is the one with more rings.
     * This could obtain the authority in future governance.
     */
    uint256 leading_equity;
}

struct RingEquity
{
    uint256 groupID;
    uint256 next_equity;// list next element
    uint32 num_rings;
}


interface IRingMarketListener
{
    function onGroupEquityCompleted(uint256 groupID, uint32 handle_code) external;
}

/**
 * Base class for Ring Markets.
 * IMPORTANT: Ring Token and Ring Groups ID cannot be zero. Those should be positive numbers.
 */
abstract contract FREE_RingMarket is FREE_Controllable, ReentrancyGuard
{
    using Address for address;
    
    using FREE_AssetOwnershipUtil for FREE_AssetOwnership;

    event RingTokenCreated(uint256 tokenID, uint256 groupID, address receiver);
    event RingTokenPriceListing(uint256 tokenID, uint256 groupID, uint256 listing_price);
    event RingTokenTransferred(uint256 tokenID, address target);
    event RingTokenPurchased(uint256 tokenID, address buyer, uint256 price_paid);

    event RingGroupCreated(uint256 groupID);
    event RingGroupCompleted(uint256 groupID);

    event RingEquityCreated(uint256 equityID, uint256 groupID, address receiver);
    event RingEquityLeading(uint256 equityID, uint256 groupID);
    event RingGroupEquityComplete(uint256 groupID);
    
    event RingEquityTransferred(uint256 equityID, address target);
    event RingTokenMergingToEquity(uint256 tokenID, uint256 equityID);

    mapping(uint256 => RingToken) internal _ring_tokens;
    mapping(uint256 => RingGroup) internal _ring_groups;
    mapping(uint256 => RingEquity) internal _ring_equities;
    
    /// Group Size of a completed group
    uint32 internal _group_size;
    
    /// Completed Equity callback
    IRingMarketListener internal _equity_listener;
    uint32 internal _listener_handle_code;

    /// Equity generator
    uint256 internal _new_equityID;

    /// Map addresses with token IDs.
    FREE_AssetOwnership internal _ring_token_owners;

    FREE_AssetOwnership internal _equity_owners;

    constructor(uint32 groupSize, address equityListener, uint32 handleCode, address initialOwner) FREE_Controllable(initialOwner)
    {
        _group_size = groupSize;
        _equity_listener = IRingMarketListener(equityListener);
        _listener_handle_code = handleCode;
        _new_equityID = FREE_DEFAULT_TOKEN_ID;
    }

    function ring_group_exists(uint256 groupID) public view returns(bool)
    {
        if(groupID == 0) return false;
        RingGroup storage rgroup = _ring_groups[groupID];
        return rgroup.num_rings > 0;
    }


    function ring_token_exists(uint256 tokenID) public view returns(bool)
    {
        if(tokenID == 0) return false;
        RingToken storage rtoken = _ring_tokens[tokenID];
        return rtoken.groupID > 0;
    }

    function ring_equity_exists(uint256 equityID) public view returns(bool)
    {
        if(equityID <= FREE_DEFAULT_TOKEN_ID) return false;
        RingEquity storage requ = _ring_equities[equityID];
        return requ.num_rings > 0;
    }

    function is_group_completed(uint256 groupID) public view returns(bool)
    {
        if(groupID == 0) return false;
        RingGroup storage rgroup = _ring_groups[groupID];
        return rgroup.num_rings >= _group_size;
    }

    function is_group_equity_completed(uint256 groupID) public view returns(bool)
    {
        if(groupID == 0) return false;
        RingGroup storage rgroup = _ring_groups[groupID];
        return rgroup.equity_count == _group_size;
    }

    /// This method is called by descendants
    function _create_ring_token(uint256 tokenID, uint256 groupID, address target_owner) internal
    {
        if(tokenID == 0 || groupID == 0 || target_owner == address(0))
        {
            revert ErrDAO_InvalidParams();
        }
        
        RingToken storage rtoken = _ring_tokens[tokenID];
        if(rtoken.groupID > 0)
        {
            revert ErrDAO_RingTokenAlreadyExists(tokenID);
        }

        RingGroup storage rgroup = _ring_groups[groupID];
        if(rgroup.num_rings >= _group_size)
        {
            revert ErrDAO_RingGroupAlreadyCompleted(groupID);
        }

        rtoken.groupID = groupID;
        rtoken.listing_price = 0;
        rtoken.equityID = 0;        

        // initiate group
        if(rgroup.num_rings == 0)
        {
            rtoken.next_ring = 0;
            
            _ring_groups[groupID] = RingGroup({
                num_rings:1,
                equity_count:0,
                ring_list:tokenID,
                equity_list:0,
                leading_equity:0
            });

            
            emit RingGroupCreated(groupID);
            
        }
        else
        {
            // connect to next ring
            rtoken.next_ring = rgroup.ring_list;
            rgroup.ring_list = tokenID;
            rgroup.num_rings++;            
        }
        
        _ring_token_owners.grant(target_owner, tokenID);

        emit RingTokenCreated(tokenID, groupID, target_owner);
        emit RingTokenTransferred(tokenID, target_owner);

        if(rgroup.num_rings >= _group_size)
        {
            emit RingGroupCompleted(groupID);
        }        
    }

    //////////////////// Ring Information////////

    function ring_token_info(uint256 tokenID) public view returns(RingToken memory)
    {
        return _ring_tokens[tokenID];
    }

    function ring_group_info(uint256 groupID) public view returns(RingGroup memory)
    {
        return _ring_groups[groupID];
    }

    function ring_equity_info(uint256 equityID) public view returns(RingEquity memory)
    {
        return _ring_equities[equityID];
    }

    
    /////////////////// Inventory Manipulation ///
    
    function ring_owner(uint256 tokenID) public view returns(address)
    {        
        return _ring_token_owners.ownerOf(tokenID);
    }

    function is_ring_owner(uint256 tokenID, address operator) public view returns(bool)
    {
        if(tokenID == 0 || operator == address(0)) return false;
        return _ring_token_owners.ownerOf(tokenID) == operator;
    }

    function transfer_ring_token(uint256 tokenID, address new_owner) external
    {        
        _ring_token_owners.transfer(tokenID, msg.sender, new_owner);

        emit RingTokenTransferred(tokenID, new_owner);
    }

    function ring_token_inventory_count(address owner) public view returns(uint64)
    {
        return _ring_token_owners.list_count(owner);
    }

    function ring_token_inventory_get(address owner, uint64 index) public view returns(uint256)
    {
        return _ring_token_owners.get(owner, index);
    }


    function equity_owner(uint256 equityID) public view returns(address)
    {        
        return _equity_owners.ownerOf(equityID);
    }

    function is_equity_owner(uint256 equityID, address operator) public view returns(bool)
    {
        if(equityID == 0 || operator == address(0)) return false;
        return _equity_owners.ownerOf(equityID) == operator;
    }

    function transfer_equity(uint256 equityID, address new_owner) external
    {        
        _equity_owners.transfer(equityID, msg.sender, new_owner);

        emit RingEquityTransferred(equityID, new_owner);
    }

    function equity_inventory_count(address owner) public view returns(uint64)
    {
        return _equity_owners.list_count(owner);
    }

    function equity_inventory_get(address owner, uint64 index) public view returns(uint256)
    {
        return _equity_owners.get(owner, index);
    }

    ////////////////////////// Equity Minting //////////////////////////

    /// Update leading status and checks if equity is complete
    function _evaluate_equity_status(
        uint256 groupID, 
        uint256 updated_equityID,
        RingGroup storage rgroup
    ) internal
    {        
        if(rgroup.leading_equity == 0)
        {
            // The first equity, should have just 1 token
            // one ring token at a time could be added to equities
            assert(rgroup.equity_count == 1);
            
            rgroup.leading_equity = updated_equityID;// the first winner

            emit RingEquityLeading(updated_equityID, groupID);
            return;
        }

        // check for updates
        if(rgroup.leading_equity != updated_equityID)
        {
            RingEquity storage rupdated_equity = _ring_equities[updated_equityID];
            RingEquity storage rold_equity = _ring_equities[rgroup.leading_equity];
            if(rupdated_equity.num_rings > rold_equity.num_rings)
            {
                // a new king!
                rgroup.leading_equity = updated_equityID;
                emit RingEquityLeading(updated_equityID, groupID);
            }
        }

        // check for completeness       
        if(rgroup.equity_count == _group_size)
        {
            assert(rgroup.equity_count == rgroup.num_rings);

            emit RingGroupEquityComplete(groupID);

            // notify listener
            _equity_listener.onGroupEquityCompleted(groupID, _listener_handle_code);            
        }
    }

    /**
     * This action cannot be reverted
     */
    function convert_ring_to_equity(uint256 tokenID) external nonReentrant returns(uint256)
    {
        RingToken storage rtoken = _ring_tokens[tokenID];
        uint256 groupID = rtoken.groupID;
        if(groupID == 0)
        {
            revert ErrDAO_InvalidRingToken(tokenID);
        }

        if(rtoken.equityID != 0)
        {
            revert ErrDAO_RingTokenAlreadyBelongsToEquity(tokenID, rtoken.equityID);
        }

        // check ownership
        address targetaddr = msg.sender;
        if(_ring_token_owners.ownerOf(tokenID) != targetaddr || targetaddr == address(0))
        {
            revert ErrDAO_NotAuthorizedToUseRingToken(tokenID, targetaddr);
        }

        RingGroup storage rgroup = _ring_groups[groupID];
        if(rgroup.num_rings == 0)
        {
            revert ErrDAO_InvalidRingGroup(tokenID);
        }
        
        assert(rgroup.equity_count < _group_size && rgroup.num_rings > rgroup.equity_count); //equity shouldn't being complete at this point

        // instance new equity
        _new_equityID++;

        _ring_equities[_new_equityID] = RingEquity({
            groupID: groupID,
            next_equity: rgroup.equity_list,
            num_rings: 1
        });

        // account equity
        rgroup.equity_count++;
        rgroup.equity_list = _new_equityID;
        // blind ring token
        rtoken.equityID = _new_equityID;
        rtoken.listing_price = 0;
        _ring_token_owners.revoke(tokenID); // user no longer has access to ring

        // give new equity to caller address
        _equity_owners.grant(targetaddr, _new_equityID);
        
        emit RingEquityCreated(_new_equityID, groupID, targetaddr);
        emit RingTokenMergingToEquity(tokenID, _new_equityID);
        emit RingEquityTransferred(_new_equityID, targetaddr);

        _evaluate_equity_status(groupID, _new_equityID, rgroup);

        return _new_equityID;
    }

    function merge_ring_token_in_equity(uint256 tokenID, uint256 equityID) external nonReentrant
    {
        address targetaddr = msg.sender;
        if(tokenID == 0 || equityID <= FREE_DEFAULT_TOKEN_ID || targetaddr == address(0))
        {
            revert ErrDAO_InvalidParams();
        }

        RingToken storage rtoken = _ring_tokens[tokenID];
        uint256 groupID = rtoken.groupID;
        if(groupID == 0)
        {
            revert ErrDAO_InvalidRingToken(tokenID);
        }

        if(rtoken.equityID != 0)
        {
            revert ErrDAO_RingTokenAlreadyBelongsToEquity(tokenID, rtoken.equityID);
        }

        RingEquity storage requity = _ring_equities[equityID];
        if(requity.groupID != groupID)
        {
            revert ErrDAO_RingEquityDoesNotBelongToSameGroup(equityID, groupID);
        }

        // check group
        RingGroup storage rgroup = _ring_groups[groupID];
        if(rgroup.equity_count >= _group_size)
        {
            // should assert here?
            revert ErrDAO_RingEquityAlreadyCompleted(groupID);
        }

        // check ownership
        if(_ring_token_owners.ownerOf(tokenID) != targetaddr)
        {
            revert ErrDAO_NotAuthorizedToUseRingToken(tokenID, targetaddr);
        }
        
        // blind ring token
        rtoken.equityID = equityID;
        rtoken.listing_price = 0;
        _ring_token_owners.revoke(tokenID); // user no longer has access to ring

        // account equity
        requity.num_rings++;
        rgroup.equity_count++;

        emit RingTokenMergingToEquity(tokenID, equityID);

        _evaluate_equity_status(groupID, equityID, rgroup);
    }

    ////////////////// Listing Price and purchase ////////////////////////////
    function list_token_price(uint256 tokenID, uint256 listing_price) external nonReentrant
    {
        address targetaddr = msg.sender;
        if(tokenID == 0 || targetaddr == address(0))
        {
            revert ErrDAO_InvalidParams();
        }

        RingToken storage rtoken = _ring_tokens[tokenID];
        uint256 groupID = rtoken.groupID;
        
        if(groupID == 0)
        {
            revert ErrDAO_InvalidRingToken(tokenID);
        }

        if(rtoken.equityID != 0)
        {
            revert ErrDAO_RingTokenAlreadyBelongsToEquity(tokenID, rtoken.equityID);
        }

        // check ownership
        if(_ring_token_owners.ownerOf(tokenID) != targetaddr)
        {
            revert ErrDAO_NotAuthorizedToUseRingToken(tokenID, targetaddr);
        }

        rtoken.listing_price = listing_price;

        emit RingTokenPriceListing(tokenID, groupID, listing_price);
    }

    function purchase_token(uint256 tokenID) external payable nonReentrant
    {
        address buyeraddr = msg.sender;
        if(tokenID == 0 || buyeraddr == address(0))
        {
            revert ErrDAO_InvalidParams();
        }

        RingToken storage rtoken = _ring_tokens[tokenID];
        uint256 groupID = rtoken.groupID;
        
        if(groupID == 0)
        {
            revert ErrDAO_InvalidRingToken(tokenID);
        }

        if(rtoken.listing_price == 0)
        {
            revert ErrDAO_CannotPurchaseRingToken(tokenID, rtoken.listing_price);
        }

        if(rtoken.equityID != 0)
        {
            revert ErrDAO_RingTokenAlreadyBelongsToEquity(tokenID, rtoken.equityID);
        }

        address targetaddr = _ring_token_owners.ownerOf(tokenID);

        // check ownership
        if(buyeraddr == targetaddr)
        {
            revert ErrDAO_InvalidParams();
        }

        uint256 payment = msg.value;

        if(rtoken.listing_price > payment)
        {
            revert ErrDAO_CannotPurchaseRingToken(tokenID, rtoken.listing_price);
        }

        // send payment
        Address.sendValue(payable(targetaddr), payment);

        rtoken.listing_price = 0;
        _ring_token_owners.transfer(tokenID, targetaddr, buyeraddr);
        emit RingTokenTransferred(tokenID, buyeraddr);
    }
}