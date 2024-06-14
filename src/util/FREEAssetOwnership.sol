//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./FREEStackArray.sol";

error ErrAsset_CannotGrantOnNullAddress(uint256 tokenID);
error ErrAsset_AssetHasNoOwner(uint256 tokenID);
error ErrAsset_WrongAssetOwner(uint256 tokenID, address alleged_owner, address real_owner);


struct FREE_AssetOwnership
{
    FREE_OwnershipArray collection;
    mapping(uint256 => address) owners;
}

library FREE_AssetOwnershipUtil
{
    function list_count(FREE_AssetOwnership storage asset_db, address pk_owner) internal view returns(uint64)
    {
        if(pk_owner == address(0)) return 0;
        uint256 u_addr = FREE_ADDRtoU256(pk_owner);
        return FREE_OwnershipArrayUtil.list_count(asset_db.collection, u_addr);
    }
    
    function get(FREE_AssetOwnership storage asset_db, address pk_owner, uint64 index) internal view returns(uint256)
    {
        if(pk_owner == address(0)) return 0;
        uint256 u_addr = FREE_ADDRtoU256(pk_owner);
        return FREE_OwnershipArrayUtil.get(asset_db.collection, u_addr, index);
    }

    function ownerOf(FREE_AssetOwnership storage asset_db, uint256 tokenID) internal view returns(address)
    {
        return asset_db.owners[tokenID];
    }

    function grant(FREE_AssetOwnership storage asset_db, address pk_owner, uint256 tokenID) internal
    {        
        if(pk_owner == address(0))
        {
            revert ErrAsset_CannotGrantOnNullAddress(tokenID);
        }

        asset_db.owners[tokenID] = pk_owner;
        uint256 u_addr = FREE_ADDRtoU256(pk_owner);
        FREE_OwnershipArrayUtil.insert(asset_db.collection, u_addr, tokenID);
    }

    /**
     * Revokes the token from its owner. In case of not having an owner, it returns false.
     */
    function revoke(FREE_AssetOwnership storage asset_db, uint256 tokenID) internal
    {
        address pk_owner = asset_db.owners[tokenID];
        if(pk_owner == address(0))
        {
            revert ErrAsset_AssetHasNoOwner(tokenID);
        }
        
        uint256 u_addr = FREE_ADDRtoU256(pk_owner);
        bool bl = FREE_OwnershipArrayUtil.remove_from_parent(asset_db.collection, u_addr, tokenID);
        assert(bl == true);

        asset_db.owners[tokenID] = address(0);
    }

    function transfer(
        FREE_AssetOwnership storage asset_db,
        uint256 tokenID,
        address original_owner, 
        address new_owner
    ) internal
    {
        address pk_owner = asset_db.owners[tokenID];
        if(pk_owner != original_owner)
        {
            revert ErrAsset_WrongAssetOwner(tokenID, original_owner, pk_owner);
        }

        if(pk_owner != address(0))
        {
            uint256 u_addr = FREE_ADDRtoU256(pk_owner);
            bool bl = FREE_OwnershipArrayUtil.remove_from_parent(asset_db.collection, u_addr, tokenID);
            assert(bl == true);            
        }

        asset_db.owners[tokenID] = new_owner;// could be address(0)

        if(new_owner != address(0))
        {            
            uint256 u_addr_new = FREE_ADDRtoU256(new_owner);
            FREE_OwnershipArrayUtil.insert(asset_db.collection, u_addr_new, tokenID);            
        }
    }

}