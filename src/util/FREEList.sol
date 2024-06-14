//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

/**
Conventions:
- All token identifiers should be represented by uint256, as dictated by the ERC1155 standard

 */

/// Convenient struct for listing and ownership
struct FREE_ListNode
{
    // Pointer to next token hash
    uint256 next;
    // Pointer to previous token hash
    uint256 prev; 
}

/**
    Basic double link list of tokens.
 */
struct FREE_TokenList
{
    // Pointer to list head token hash. (last element)
    uint256 head;
    // number of allocated elements
    uint count;
    /// Registry of entries
    mapping(uint256 => FREE_ListNode) node_registry;
}

/// Derived information from FREE_TokenOwnershipList
struct FREE_TokenListInfo
{
    // Pointer to list head token hash. (last element)
    uint256 head;
    // number of allocated elements
    uint count;
}

/**
Advanced list for registering list ownership for tokens.
This asummed that each token has an unique identifier that doesn't repeat.
 */
struct FREE_TokenOwnershipList
{
    /// Registry of sublists.
    mapping(uint256 => FREE_ListNode) node_registry;

    /// Registry of ownership of sublists for tokens.
    mapping(uint256 => FREE_TokenListInfo) owner_list_registry;
}


library FREE_TokenListUtil 
{
    function info(FREE_TokenList storage listobj) internal view returns(FREE_TokenListInfo memory)
    {
        return FREE_TokenListInfo({head:listobj.head, count:listobj.count});
    }

    function clear(FREE_TokenList storage listobj) internal
    {
        listobj.head = uint256(0);
        listobj.count = uint(0);
    }

    
    /// Removes the peek object from list queue
    function dequeue(FREE_TokenList storage listobj) internal returns(uint256)
    {
        uint256 _head = listobj.head;
        if(_head == 0) return 0;
        // node and next
        FREE_ListNode storage _head_obj = listobj.node_registry[_head];

        uint256 _next = _head_obj.next;
        _head_obj.next = 0;
        listobj.count--;
        listobj.head = _next;

        if(_next != 0)
        {
            // fix next node
            listobj.node_registry[_next].prev = 0;
        }

        return _head;
    }

    function insert(FREE_TokenList storage listobj, uint256 newtokenID) internal 
    {
        uint256 currheadID = listobj.head;
        if(currheadID == 0){
            // just insert new entry
            listobj.node_registry[newtokenID] = FREE_ListNode({next:0, prev:0});
            listobj.count = 1;            
        }
        else
        {
            // fix previous token
            FREE_ListNode storage head_obj = listobj.node_registry[currheadID];
            head_obj.prev = newtokenID;
            // register new token
            listobj.node_registry[newtokenID] = FREE_ListNode({next:currheadID, prev:0});
            listobj.count++;
        }

        listobj.head = newtokenID;
    }


    function remove(FREE_TokenList storage listobj, uint256 extokenID) internal 
    {
        FREE_ListNode storage extoken_obj = listobj.node_registry[extokenID];
        
        uint256 prevID = extoken_obj.prev;
        uint256 nextID = extoken_obj.next;

        if(prevID != 0)
        {
            FREE_ListNode storage prev_obj = listobj.node_registry[prevID];
            prev_obj.next = nextID;
        }
        else        
        {
            // if(extokenID == listobj.head)
            listobj.head = nextID;
        }

        if(nextID != 0)
        {
            FREE_ListNode storage next_obj = listobj.node_registry[nextID];
            next_obj.prev = prevID;
        }

        // may we should use delete, but better to ensure that default values are 0
        delete listobj.node_registry[extokenID];
        listobj.count--;
    }
    
}

//**********************************************************
library FREE_TokenOwnershipListUtil 
{
    function info(FREE_TokenOwnershipList storage list_container, uint256 parent_token) internal view returns(FREE_TokenListInfo memory)
    {
        FREE_TokenListInfo storage _info = list_container.owner_list_registry[parent_token];
        return FREE_TokenListInfo({head:_info.head, count:_info.count});
    }    

    function sinfo(FREE_TokenOwnershipList storage list_container, uint256 parent_token) internal view returns(FREE_TokenListInfo storage)
    {
        return list_container.owner_list_registry[parent_token];
    }

    function count(FREE_TokenOwnershipList storage list_container, uint256 parent_token) internal view returns(uint)
    {
        return list_container.owner_list_registry[parent_token].count;
    }

    function init_owner(FREE_TokenOwnershipList storage list_container, uint256 parent_token) internal
    {
        list_container.owner_list_registry[parent_token] = FREE_TokenListInfo({head:0,count:0});
    }

    function delete_owner(FREE_TokenOwnershipList storage list_container, uint256 parent_token) internal
    {
        delete list_container.owner_list_registry[parent_token];
    }

    function insert(FREE_TokenOwnershipList storage list_container, uint256 parent_token, uint256 newtokenID) internal 
    {
        FREE_TokenListInfo storage listobj = list_container.owner_list_registry[parent_token];

        uint256 currheadID = listobj.head;// owner list head
        if(currheadID == 0){
            // just insert new sublist entry 
            list_container.node_registry[newtokenID] = FREE_ListNode({next:0, prev:0});
            listobj.count = 1;// update owner
        }
        else
        {
            // fix previous token sublist node
            FREE_ListNode storage head_obj = list_container.node_registry[currheadID];
            head_obj.prev = newtokenID;
            // register new token sublist node
            list_container.node_registry[newtokenID] = FREE_ListNode({next:currheadID, prev:0});
            listobj.count++;// update owner
        }

        listobj.head = newtokenID;
    }


    function remove(FREE_TokenOwnershipList storage list_container, uint256 parent_token, uint256 extokenID) internal 
    {
        FREE_TokenListInfo storage listobj = list_container.owner_list_registry[parent_token];

        FREE_ListNode storage extoken_obj = list_container.node_registry[extokenID];

        uint256 prevID = extoken_obj.prev;
        uint256 nextID = extoken_obj.next;

        if(prevID != 0)
        {
            FREE_ListNode storage prev_obj = list_container.node_registry[prevID];
            prev_obj.next = nextID;
        }
        else if(extokenID == listobj.head)
        {
            listobj.head = nextID;
        }

        if(nextID != 0)
        {
            FREE_ListNode storage next_obj = list_container.node_registry[nextID];
            next_obj.prev = prevID;
        }

        // may we should use delete, but better to ensure that default values are 0
        delete list_container.node_registry[extokenID];

        listobj.count--;// update sublist
    }
    
}

/////////////////////////////// Stack /////////////////////////////////////////

/**
    Basic double link list of tokens.
 */
struct FREE_reeList
{
    // Pointer to list head token hash. (last element)
    uint256 head;
    // number of allocated elements
    uint count;
    /// Registry of entries, point to next element in the list
    mapping(uint256 => uint256) node_registry;
}

library FREE_reeListUtil 
{
    function info(FREE_reeList storage listobj) internal view returns(FREE_TokenListInfo memory)
    {
        return FREE_TokenListInfo({head:listobj.head, count:listobj.count});
    }

    function clear(FREE_reeList storage listobj) internal
    {
        listobj.head = uint256(0);
        listobj.count = uint(0);
    }

    
    /// Removes the peek object from list queue
    function dequeue(FREE_reeList storage listobj) internal returns(uint256)
    {
        uint256 _head = listobj.head;
        uint _count = listobj.count;
        if(_head == 0 || _count == 0) return 0;
        // node and next
        uint256 _next = listobj.node_registry[_head];
        
        if(_count == 1)
        {
            // clear list
            listobj.count = 0;
            listobj.head = uint256(0);
        }
        else
        {
            listobj.count = _count - 1;
            listobj.head = _next;
        }

        return _head;
    }

    function insert(FREE_reeList storage listobj, uint256 newtokenID) internal 
    {        
        listobj.count++;
        listobj.node_registry[newtokenID] = listobj.head;
        listobj.head = newtokenID;
    }    
}
