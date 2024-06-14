//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./FREEcommon.sol";

//************ Simple array stack implementation *************************
struct FREE_StackArray
{
    // number of allocated elements
    uint32 count;
    
    /// Pseudo array
    mapping(uint32 => uint256) array;   
}


library FREE_StackArrayUtil 
{    
    function clear(FREE_StackArray storage listobj) internal
    {        
        listobj.count = uint32(0);
    }

    function get(FREE_StackArray storage listobj, uint32 index) internal view returns(uint256)
    {
        return listobj.array[index];
    }


    /// Gets an element from a hash
    function hget(FREE_StackArray storage listobj, uint256 ihash) internal view returns(uint256)
    {
        uint32 _count = listobj.count;
        if(_count == 0) return uint256(0);
        uint256 capped = ihash % uint256(_count);
        return listobj.array[uint32(capped)];
    }

    
    /// Removes the peek object from list queue
    function dequeue(FREE_StackArray storage listobj) internal returns(uint256)
    {
        uint32 _count = listobj.count;
        if(_count == 0) return uint256(0);
        
        _count--;
        listobj.count = _count;
        return listobj.array[_count];
    }

    /**
     * Returns the last index where the element has been inserted
     */
    function insert(FREE_StackArray storage listobj, uint256 newtokenID) internal returns(uint32)
    {
        uint32 _count = listobj.count;
        listobj.array[_count] = newtokenID;        
        listobj.count = _count + 1;
        return _count;
    }

    /// Swap elements to the last
    /// Returns the new size, and the success flag
    function remove(FREE_StackArray storage listobj, uint32 index) internal returns (uint32, bool)
    {
        uint32 _count = listobj.count;
        if(index >= _count) return (_count, false);

        _count--;

        if(index < _count)
        {
            // swap with last element
            listobj.array[index] = listobj.array[_count];
        }

        listobj.count = _count;
        return (_count, true);
    }

    function swap_elements(FREE_StackArray storage listobj, uint32 index0, uint32 index1) internal
    {
        uint32 _count = listobj.count;
        require((index0 < _count) && (index1 < _count) && (index0 != index1), "Wrong element indexes");

        uint256 element0 = listobj.array[index0];
        listobj.array[index0] = listobj.array[index1];
        listobj.array[index1] = element0;
    }

}


//************ Simple array Ownership implementation *************************

/**
 * This collection requires tokens represented as unsigned integers of 192 bits.
 * Doesn't support eliminating elements by the tokenID. Only indices are supported
 */
struct FREE_BasicOwnership
{

    // Size of each Owner linked collection
    mapping(uint256 => uint64) array_sizes;   

    
    /// Pseudo array
    mapping(uint256 => uint256) ownership;    
}

library FREE_BasicOwnershipUtil 
{    
    function token_index_hash(uint256 token_id, uint64 index) internal pure returns(uint256)
    {
        return (token_id & FREE_MAX_TOKEN_VALUE) | (uint256(index) << FREE_UPPER_TOKEN_MASK_BIT_COUNT);
    }

    function index_from_hash(uint256 hashindex) internal pure returns(uint64)
    {
        uint256 ret_index_val = (hashindex >> FREE_UPPER_TOKEN_MASK_BIT_COUNT) & INVALID_INDEX64;
        return uint64(ret_index_val);
    }

    function token_from_hash(uint256 hashindex) internal pure returns(uint256)
    {
        return hashindex & FREE_MAX_TOKEN_VALUE;
    }

    function list_count(FREE_BasicOwnership storage listobj, uint256 parent_token) internal view returns(uint64)
    {
        return listobj.array_sizes[parent_token];
    }


    function clear(FREE_BasicOwnership storage listobj, uint256 parent_token) internal
    {        
        listobj.array_sizes[parent_token] = uint64(0);
    }
    
    function get(FREE_BasicOwnership storage listobj, uint256 parent_token, uint64 index) internal view returns(uint256)
    {
        uint256 tokenhash = token_index_hash(parent_token, index);
        return listobj.ownership[tokenhash];
    }


    function set(FREE_BasicOwnership storage listobj, uint256 parent_token, uint64 index, uint256 value) internal
    {
        uint256 tokenhash = token_index_hash(parent_token, index);
        listobj.ownership[tokenhash] = value;        
    }

    
    /// Removes the peek object from list queue
    function dequeue(FREE_BasicOwnership storage listobj, uint256 parent_token) internal returns(uint256)
    {
        uint64 _count = listobj.array_sizes[parent_token];
        if(_count == 0) return uint256(0);
        
        _count--;
        
        // extract element
        uint256 hashindex = token_index_hash(parent_token, _count);        
        uint256 value_token = listobj.ownership[hashindex];

        // update count
        listobj.array_sizes[parent_token] = _count;
        return value_token;
    }


    /**
     * Returns the index of the last inserted element
     */
    function insert(FREE_BasicOwnership storage listobj, uint256 parent_token, uint256 newtokenID) internal
    {
        uint64 _count = listobj.array_sizes[parent_token];
        uint256 hashindex = token_index_hash(parent_token, _count);
        listobj.ownership[hashindex] = newtokenID;
        listobj.array_sizes[parent_token] = _count + 1;        
    }

    /// Swap elements to the last
    /// Returns the new size, and the success flag
    function remove(
        FREE_BasicOwnership storage listobj,
        uint256 parent_token,
        uint64 index) internal returns (bool)
    {
        uint64 _count = listobj.array_sizes[parent_token];
        if(index >= _count) return false;

        _count--;

        if(index < _count)
        {
            uint256 hashindex0 = token_index_hash(parent_token, index);
            uint256 hashindex1 = token_index_hash(parent_token, _count);
            // swap with last element
            listobj.ownership[hashindex0] = listobj.ownership[hashindex1];            
        }

        listobj.array_sizes[parent_token] = _count;
        return true;
    }

    function swap_elements(FREE_BasicOwnership storage listobj, uint256 parent_token, uint64 index0, uint64 index1) internal
    {
        uint64 _count = listobj.array_sizes[parent_token];        
        require((index0 < _count) && (index1 < _count) && (index0 != index1), "Wrong element indexes");

        uint256 hashindex0 = token_index_hash(parent_token, index0);
        uint256 hashindex1 = token_index_hash(parent_token, index1);
        
        uint256 element0 = listobj.ownership[hashindex0];
        uint256 element1 = listobj.ownership[hashindex1];
        listobj.ownership[hashindex0] = element1;
        listobj.ownership[hashindex1] = element0;
    }
}

//************ Advanced array Ownership implementation *************************


/**
 * Advanced Ownership collection.
 * This allows removing elements by tokenID
 * This collection requires tokens represented as unsigned integers of 192 bits
 */
struct FREE_OwnershipArray
{

    // Size of each Owner linked collection
    mapping(uint256 => uint64) array_sizes;   

    
    /// Pseudo array
    mapping(uint256 => uint256) ownership;

    /**
     * Index reference. (For fast elimination).
     * 1-based index. 0 means undefined.
     */ 
    mapping(uint256 => uint64) index_ref;
}

library FREE_OwnershipArrayUtil 
{    
    function token_index_hash(uint256 token_id, uint64 index) internal pure returns(uint256)
    {
        return FREE_BasicOwnershipUtil.token_index_hash(token_id, index);
    }

    function index_from_hash(uint256 hashindex) internal pure returns(uint64)
    {
        return FREE_BasicOwnershipUtil.index_from_hash(hashindex);
    }

    function token_from_hash(uint256 hashindex) internal pure returns(uint256)
    {
        return FREE_BasicOwnershipUtil.token_from_hash(hashindex);
    }

    function list_count(FREE_OwnershipArray storage listobj, uint256 parent_token) internal view returns(uint64)
    {
        return listobj.array_sizes[parent_token];
    }


    function clear(FREE_OwnershipArray storage listobj, uint256 parent_token) internal
    {        
        listobj.array_sizes[parent_token] = uint64(0);
    }
    
    function get(FREE_OwnershipArray storage listobj, uint256 parent_token, uint64 index) internal view returns(uint256)
    {
        uint256 tokenhash = FREE_BasicOwnershipUtil.token_index_hash(parent_token, index);
        return listobj.ownership[tokenhash];
    }


    function set(FREE_OwnershipArray storage listobj, uint256 parent_token, uint64 index, uint256 value) internal
    {
        uint256 tokenhash = FREE_BasicOwnershipUtil.token_index_hash(parent_token, index);
        listobj.ownership[tokenhash] = value;
        listobj.index_ref[value] = index + 1;// 1-based index
    }

    
    /// Removes the peek object from list queue
    function dequeue(FREE_OwnershipArray storage listobj, uint256 parent_token) internal returns(uint256)
    {
        uint64 _count = listobj.array_sizes[parent_token];
        if(_count == 0) return uint256(0);
        
        _count--;
        
        // extract element
        uint256 hashindex = FREE_BasicOwnershipUtil.token_index_hash(parent_token, _count);        
        uint256 value_token = listobj.ownership[hashindex];

        listobj.index_ref[value_token] = 0;// remove reference

        // update count
        listobj.array_sizes[parent_token] = _count;

        return value_token;
    }


    /**
     * Returns the index of the last inserted element
     */
    function insert(FREE_OwnershipArray storage listobj, uint256 parent_token, uint256 newtokenID) internal
    {
        uint64 _count = listobj.array_sizes[parent_token];
        uint256 hashindex = FREE_BasicOwnershipUtil.token_index_hash(parent_token, _count);
        listobj.ownership[hashindex] = newtokenID;
        listobj.array_sizes[parent_token] = _count + 1;
        listobj.index_ref[newtokenID] = _count + 1;// for helping removing it.        
    }

    function _remove_internal(
        FREE_OwnershipArray storage listobj,
        uint256 parent_token,
        uint64 index,
        uint64 count,
        uint256 hashindex0
    ) internal
    {
        uint64 new_count = count - 1;

        if(index < new_count)
        {
            // swap element from the tail            
            uint256 hashindex1 = FREE_BasicOwnershipUtil.token_index_hash(parent_token, new_count);
            uint256 swap_tokenID = listobj.ownership[hashindex1];
            // swap with last element
            listobj.ownership[hashindex0] = swap_tokenID;
            // Assigning previous token index ref
            listobj.index_ref[swap_tokenID] = index + 1; // 1-based index.
        }        

        listobj.array_sizes[parent_token] = new_count;        
    }

    /// Swap elements to the last
    /// Returns the new size, and the success flag
    function remove(
        FREE_OwnershipArray storage listobj,
        uint256 parent_token,
        uint64 index) internal returns (bool)
    {
        uint64 _count = listobj.array_sizes[parent_token];
        if(index >= _count) return (false);

        uint256 hashindex0 = FREE_BasicOwnershipUtil.token_index_hash(parent_token, index);
        uint256 exit_tokenID = listobj.ownership[hashindex0];
        listobj.index_ref[exit_tokenID] = 0; // clear index

        _remove_internal(listobj, parent_token, index, _count, hashindex0);
        return true;
    }


    function remove_from_parent(
        FREE_OwnershipArray storage listobj,
        uint256 parent_token,
        uint256 exit_tokenID) internal returns (bool)
    {
        uint64 _count = listobj.array_sizes[parent_token];
        uint64 ref_index = listobj.index_ref[exit_tokenID];
        
        if(ref_index > _count || _count == 0) return false;// malformed index

        uint256 hashindex0 = FREE_BasicOwnershipUtil.token_index_hash(parent_token, ref_index - 1);
        listobj.index_ref[exit_tokenID] = 0; // clear index

        _remove_internal(listobj, parent_token, ref_index - 1, _count, hashindex0);
        return true;
    }

    function swap_elements(FREE_OwnershipArray storage listobj, uint256 parent_token, uint64 index0, uint64 index1) internal
    {
        uint64 _count = listobj.array_sizes[parent_token];        
        require((index0 < _count) && (index1 < _count) && (index0 != index1), "Wrong element indexes");

        uint256 hashindex0 = FREE_BasicOwnershipUtil.token_index_hash(parent_token, index0);
        uint256 hashindex1 = FREE_BasicOwnershipUtil.token_index_hash(parent_token, index1);
        
        uint256 element0 = listobj.ownership[hashindex0];
        uint256 element1 = listobj.ownership[hashindex1];
        listobj.ownership[hashindex0] = element1;
        listobj.ownership[hashindex1] = element0;

        listobj.index_ref[element0] = index1 + 1;
        listobj.index_ref[element1] = index0 + 1;
    }
}
