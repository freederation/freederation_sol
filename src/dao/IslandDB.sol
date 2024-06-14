//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "../util/FREEControllable.sol";
import "../util/FREEAssetOwnership.sol";
import "./StarProjectDB.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

error ErrDAO_IslandWithNameAlreadyExists(bytes32 name, uint256 planetID, uint64 projectID);

error ErrDAO_IslandDoesNotExists(uint256 islandID);

error ErrDAO_NotAllowedToChangeIsland(uint256 islandID, address client);


struct IslandInfo
{
    uint64 star_projectID;
    uint256 planetID;
    /**
    * This Reputation score increments each time that the Island completes a reveal correctly.
    * In case of providing wrong information or failing to reveal its commited response, this score
    * is set to 0  and the Island get banned permanently. 
    */
    uint32 reputation;
}

struct IslandMeta
{
    /**
     * Names only could have 1 coincidence on planets. But projects could
     * have many islands with the same name
     */
    bytes32 name;
    /**
     * URL which points to an IPFS content, 3D Asset or Virtual Room, 
     */
    string URLdata;
}

contract IslandDB is FREE_Controllable, ReentrancyGuard 
{
    using FREE_OwnershipArrayUtil for FREE_OwnershipArray;
    using FREE_AssetOwnershipUtil for FREE_AssetOwnership;

    event IslandOwnershipTransferred(uint256 islandID, address new_owner);
    event IslandCreated(uint64 star_projectID, uint256 planetID, uint256 islandID);
    event IslandDestroyed(uint256 islandID);

    mapping(uint256 => IslandInfo) private _islands_info;
    mapping(uint256 => IslandMeta) private _islands_meta;

    /// Maps name hash (name, planetID, projectID),  with islandID
    FREE_OwnershipArray private _island_name_registry;

    /// Maps islandID with address
    FREE_AssetOwnership private _islands_ownership;

    uint256 _new_islandID;

    constructor(address initialOwner) FREE_Controllable(initialOwner)
    {
        _new_islandID = FREE_DEFAULT_TOKEN_ID;
    }

    function _check_island_owner(address operator, uint256 islandID) internal view
    {
        if(operator == address(0) || islandID <= FREE_DEFAULT_TOKEN_ID)
        {
            revert ErrDAO_InvalidParams();
        }

        IslandInfo storage pinfo = _islands_info[islandID];
        if(pinfo.reputation == 0 || pinfo.star_projectID <= FREE_DEFAULT_TOKEN_ID64 || pinfo.planetID <= FREE_DEFAULT_TOKEN_ID)
        {
            revert ErrDAO_IslandDoesNotExists(islandID);
        }

        if(is_island_owner(islandID, operator) == false)
        {
            revert ErrDAO_NotAllowedToChangeIsland(islandID, operator);
        }
    }
    
    modifier canChangeIsland(uint256 islandID) {
        _check_island_owner(msg.sender, islandID);
        _;
    }


    function calc_island_name_hash(bytes32 name, uint256 planetID, uint64 projectID) public pure returns(uint256)
    {        
        bytes20 hashvote = ripemd160(abi.encodePacked(name, planetID, projectID));
        return uint256(uint160(hashvote));
    }

    function _find_islandID_by_hash(uint256 namehash, uint256 planetID, uint64 projectID) internal view returns(uint256)
    {
        uint64 numentries = _island_name_registry.list_count(namehash);
        if(numentries == 0) return 0;
        for(uint64 i = 0; i < numentries; i++)
        {
            uint256 islandID = _island_name_registry.get(namehash, i);
            IslandInfo storage pinfo = _islands_info[islandID];
            if(pinfo.star_projectID == projectID && pinfo.planetID == planetID)
            {
                return islandID;
            }
        }

        return 0;
    }

    /**
     * Returns 0 if not found.
     */
    function find_island_by_name(bytes32 name, uint256 planetID, uint64 projectID) public view returns(uint256)
    {
        if(FREE_IsNullName(name) == true) return 0;

        uint256 namehash = calc_island_name_hash(name, planetID, projectID);
        return _find_islandID_by_hash(namehash, planetID, projectID);
    }

    function _register_island_name(bytes32 name, uint256 planetID, uint64 projectID, uint256 new_islandID) internal
    {
        if(FREE_IsNullName(name) == true) return;

        uint256 namehash = calc_island_name_hash(name, planetID, projectID);
        uint256 foundID = _find_islandID_by_hash(namehash, planetID, projectID);
        if(foundID != 0)
        {
            revert ErrDAO_IslandWithNameAlreadyExists(name, planetID, projectID);
        }
        
        // insert new netry
        _island_name_registry.insert(namehash, new_islandID);
    }

    function _unregister_island_name(uint256 islandID) internal
    {        
        IslandMeta storage pmeta = _islands_meta[islandID];
        if(FREE_IsNullName(pmeta.name) == true) return;

        IslandInfo storage pinfo = _islands_info[islandID];
        uint256 namehash = calc_island_name_hash(pmeta.name, pinfo.planetID, pinfo.star_projectID);
        bool success = _island_name_registry.remove_from_parent(namehash, islandID);
        assert(success == true);
    }

    function _change_island_name(uint islandID, bytes32 new_name) internal
    {
        IslandInfo storage pinfo = _islands_info[islandID];

        uint256 new_namehash = 0;

        if(FREE_IsNullName(new_name) == false)
        {
            new_namehash = calc_island_name_hash(new_name, pinfo.planetID, pinfo.star_projectID);
            uint256 foundID = _find_islandID_by_hash(new_namehash, pinfo.planetID, pinfo.star_projectID);
            if(foundID != 0)
            {
                revert ErrDAO_IslandWithNameAlreadyExists(new_name, pinfo.planetID, pinfo.star_projectID);
            }
        }
        
        _unregister_island_name(islandID);
        
        if(new_namehash != 0)
        {
            _island_name_registry.insert(new_namehash, islandID);
        }        

        // update name
        _islands_meta[islandID].name = new_name;
    }

    /// Island creation
    function create_island(
        address owner,
        uint64 star_projectID,
        uint256 planetID,
        IslandMeta memory island_meta_info
    ) external onlyOwner nonReentrant returns(uint256)
    {
        if( owner == address(0) || 
            star_projectID <= FREE_DEFAULT_TOKEN_ID64 ||
            planetID <= FREE_DEFAULT_TOKEN_ID)
        {
            revert ErrDAO_InvalidParams();
        }
        
        uint256 next_id = _new_islandID + 1;
        // attempt to register new name
        // this could revert the process
        _register_island_name(island_meta_info.name, planetID, star_projectID, next_id);

        // proceed with confidence
        _new_islandID = next_id;

        _islands_meta[next_id] = island_meta_info;

        _islands_info[next_id] = IslandInfo({
            star_projectID: star_projectID,
            planetID: planetID,
            reputation:1
        });

        // register ownership
        _islands_ownership.grant(owner, next_id);

        emit IslandCreated(star_projectID, planetID, next_id);

        emit IslandOwnershipTransferred(next_id, owner);
        
        return next_id;
    }


    //////////////////////////7 Planet Info //////////////////////////77

    function get_island_info(uint256 islandID) public view returns(IslandInfo memory)
    {
        return _islands_info[islandID];
    }

    function get_island_name(uint256 islandID) public view returns(bytes32)
    {
        return _islands_meta[islandID].name;
    }

    function get_island_meta(uint256 islandID) public view returns(IslandMeta memory)
    {
        return _islands_meta[islandID];
    }

    function change_island_meta(
        uint256 islandID,
        IslandMeta memory metainfo
    ) nonReentrant canChangeIsland(islandID) external
    {
        IslandMeta storage current_meta = _islands_meta[islandID];
        
        if(current_meta.name != metainfo.name)
        {
            // attempt to change name
            _change_island_name(islandID, metainfo.name);
        }

        current_meta.URLdata = metainfo.URLdata;
    }

    ///////////////////7/// Planet Ownership /////////////////////
    function island_owner_addr(uint256 islandID) public view returns(address)
    {     
        if(islandID <= FREE_DEFAULT_TOKEN_ID) return address(0);
        return _islands_ownership.ownerOf(islandID);
    }

    function is_island_owner(uint256 islandID, address pk_owner) public view returns(bool)
    {     
        if(islandID <= FREE_DEFAULT_TOKEN_ID || pk_owner == address(0)) return false;
        return _islands_ownership.ownerOf(islandID) == pk_owner ? true : false;
    }

    /**
     * This method is called by FREEDERATION
     */
    function revoke_island_ownership(uint256 islandID) external onlyOwner
    {
        _islands_ownership.revoke(islandID);
    }

    /**
     * The owner could call this method
     */
    function transfer_island_ownership(uint256 islandID, address prev_owner, address new_owner) external onlyOwner
    {        
        _islands_ownership.transfer(islandID, prev_owner, new_owner);

        emit IslandOwnershipTransferred(islandID, new_owner);
    }

    /**
     * Number of islands shares owned by pk_owner
     */
    function get_islands_inventory_count(address pk_owner) public view returns(uint64)
    {
        return _islands_ownership.list_count(pk_owner);
    }

    function get_inventory_islandID(address pk_owner, uint64 index) public view returns(uint256)
    {
        return _islands_ownership.get(pk_owner, index);
    }

    //// Moderation methods /// 
    function increase_island_reputation(uint256 islandID, uint32 points) external onlyOwner nonReentrant
    {
        _islands_info[islandID].reputation += points;
    }


    function destroy_island(uint256 islandID) external onlyOwner nonReentrant
    {
        _islands_info[islandID].reputation = 0;
        _islands_ownership.revoke(islandID);

        // remove name
        _unregister_island_name(islandID);

        emit IslandDestroyed(islandID);
    }

}