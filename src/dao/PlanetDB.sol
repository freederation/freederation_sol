//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "../util/FREECalcLib.sol";
import "../util/FREEControllable.sol";
import "../util/FREEAssetOwnership.sol";
import "./StarProjectDB.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

error ErrDAO_PlanetWithNameAlreadyExists(bytes32 name, uint64 projectID);

error ErrDAO_PlanetDoesNotExists(uint256 planetID);

error ErrDAO_NotEnoughFundsForMintingPlanet(uint64 projectID, uint256 required_payment);

error ErrDAO_NotAllowedToMintPlanet(uint64 projectID, address client);

error ErrDAO_NotAllowedToMintIsland(uint256 planetID, address client);


error ErrDAO_NotAllowedToChangePlanet(uint256 planetID, address client);

error ErrDAO_NotOwnsPlanetShare(uint256 planet_shareID, address client);

error ErrDAO_FreeMintingIsForbidden(uint256 planetID);

error ErrDAO_NotEnoughFundsForMintingIsland(uint64 projectID, uint256 planetID, uint256 required_payment);

/// Minting of Initial Planet Offering
struct StarPlanetMinting
{
    uint32 founder_planet_reserve;
    uint32 initial_planet_mint_count;
    uint256 planet_minting_price;
    /// If 0, it allows free minting
    uint32 planet_minting_nonce;
    bool island_free_minting;    
}


struct PlanetInfo
{
    bytes32 name;

    uint64 star_projectID;

    /// Grace periods earned by Star project
    uint32 star_prestige;

    /// Number of minted islands
    uint32 island_count;

    /**
     * The raw commission before taxes and insurance discounts.
     */
    uint256 commission_increment;
    
    /**
     * Current commissions in vesting. When vesting period expires,
     * these commissions will form part of liberated_commissions
     */
    uint256 vesting_commissions;
    uint64 last_vesting_period;

    /**
     * This ammount always increases. 
     * Each PlanetEquityShare calculates their assignation according with 
     * this totalized ammount.
     * This ammount is increased when vesting commisions were liberated and 
     * contributed with the available commisions.
     */
    uint256 liberated_commissions;

    /**
     * If 0, this allows free minting.
     * Otherwise, it requires a signature.
     */
    uint32 island_minting_nonce;

    /// Head of the token list of shares
    uint256 share_list_head;
}


struct PlanetShareInfo
{
    uint256 planetID;

    /**
     * Tell if the owner could change the name of the Planet, 
     * the commission increment or the minting nonce.
     */
    bool planet_control_delegate;

    /**
     * Percentaje of earnings
     */
    uint256 share_percentaje;

    /**
     * The amount of earnings that a share owner could obtain
     * is calculated by the difference between
     * current_widthdraw = percentaje(liberated_commissions, share_portion) - payout_amount
     */
    uint256 payout_amount;


    uint256 share_list_next;
}

struct PlanetEntryParams
{
    bytes32 planet_name;
    uint64 star_projectID;
    uint256 commission_increment;
    uint32 star_prestige;
    bool island_free_minting;
}

struct SignatureAuthorization
{
    address pk_authorizer;
    bytes32 signature_r;
    bytes32 signature_s;
    uint8 parity_v;
}


struct IslandPricingParams
{
    /// Island floor base price. It could vary depending of the planet bonding curve
    uint256 island_floor_price;

    /// Island percentaje factor for incrementing the base price taking the number of islands
    uint256 island_curve_price_rate;
    
    /// Minimum flat commission fee added to the price, before taxes.
    uint256 minimum_commission; 
    
    /// Insurance tax percentaje, calculated over raw commission before taxes.
    uint256 insurance_rate;

    /// FREEDERATION Tax rate, calculated over raw commission before taxes.
    uint256 freederation_tax_rate;
}

struct IslandPriceCalculation
{
    uint256 island_sales_price;

    uint256 planet_commission;

    uint256 insurance_contribution;

    uint256 freederation_tax_contribution;
}

/**
 * Planets never dissapear.
 */
contract PlanetDB is FREE_Controllable, ReentrancyGuard 
{
    using FREE_OwnershipArrayUtil for FREE_OwnershipArray;
    using FREE_AssetOwnershipUtil for FREE_AssetOwnership;
    using FREE_BasicOwnershipUtil for FREE_BasicOwnership;

    event PlanetOwnershipTransferred(uint256 shareID, address new_owner);

    event PlanetCreated(uint64 star_projectID, uint256 new_planetID);
    
    // Stars minting for Planets
    mapping(uint64 => StarPlanetMinting) private _star_planet_minting;

    mapping(uint256 => PlanetInfo) private _planets_info;

    mapping(uint256 => PlanetShareInfo) private _planets_shares_registry;

    /// Maps name hash (name, projectID),  with PlanetID
    FREE_OwnershipArray private _planet_name_registry;
    
    /// Maps planetShareID with address
    FREE_AssetOwnership private _planet_share_ownership;

    /**
     * Maps planets associated to star projects
     */
    FREE_BasicOwnership private _star_planets_map;

    /**
     * This is used by both planets and planet-shares
     */
    uint256 private _new_planetID;

    constructor(address initialOwner) FREE_Controllable(initialOwner)
    {
        _new_planetID = FREE_DEFAULT_TOKEN_ID;
    }

    function register_star_project(
        uint64 star_projectID,
        StarPlanetMinting memory minting_info
    ) onlyOwner external
    {
        _star_planet_minting[star_projectID] = StarPlanetMinting({
            founder_planet_reserve:minting_info.founder_planet_reserve,
            initial_planet_mint_count:minting_info.initial_planet_mint_count,
            planet_minting_price:minting_info.planet_minting_price,
            planet_minting_nonce:minting_info.planet_minting_nonce,
            island_free_minting:minting_info.island_free_minting
        });
    }

    function star_planet_minting(uint64 star_projectID) public view returns(StarPlanetMinting memory)
    {
        return _star_planet_minting[star_projectID];
    }

    function configure_planet_initial_price(
        uint64 star_projectID,
        uint256 price        
    ) external onlyOwner
    {
        StarPlanetMinting storage minting_info = _star_planet_minting[star_projectID];
        minting_info.planet_minting_price = price;
    }


    function configure_star_minting_limitations(
        uint64 star_projectID,
        uint32 planet_minting_nonce,
        bool island_free_minting
    ) external onlyOwner
    {
        StarPlanetMinting storage minting_info = _star_planet_minting[star_projectID];
        minting_info.planet_minting_nonce = planet_minting_nonce;
        minting_info.island_free_minting = island_free_minting;
    }

    function calc_planet_name_hash(bytes32 name, uint64 projectID) public pure returns(uint256)
    {        
        bytes20 hashvote = ripemd160(abi.encodePacked(name, projectID));
        return uint256(uint160(hashvote));
    }

    function _find_planetID_by_hash(uint256 namehash, uint64 projectID) internal view returns(uint256)
    {
        uint64 numentries = _planet_name_registry.list_count(namehash);
        if(numentries == 0) return 0;
        for(uint64 i = 0; i < numentries; i++)
        {
            uint256 planetID = _planet_name_registry.get(namehash, i);
            PlanetInfo storage pinfo = _planets_info[planetID];
            if(pinfo.star_projectID == projectID)
            {
                return planetID;
            }
        }

        return 0;
    }

    /**
     * Returns 0 if not found.
     */
    function find_planet_by_name(bytes32 name, uint64 projectID) public view returns(uint256)
    {
        if(FREE_IsNullName(name) == true) return 0;

        uint256 namehash = calc_planet_name_hash(name, projectID);
        return _find_planetID_by_hash(namehash, projectID);
    }

    /**
     * If name == FREE_NULL_NAME it doesn't register the project
     */
    function _register_planet_name(bytes32 name, uint64 projectID, uint256 new_planetID) internal
    {
        if(FREE_IsNullName(name) == true) return;

        uint256 namehash = calc_planet_name_hash(name, projectID);
        uint256 foundID = _find_planetID_by_hash(namehash, projectID);
        if(foundID != 0)
        {
            revert ErrDAO_PlanetWithNameAlreadyExists(name, projectID);
        }
        
        // insert new netry
        _planet_name_registry.insert(namehash, new_planetID);
    }

    /**
     * If name == FREE_NULL_NAME it doesn't register the project
     */
    function _unregister_planet_name(uint256 planetID) internal
    {
        PlanetInfo storage pinfo = _planets_info[planetID];

        if(FREE_IsNullName(pinfo.name) == true) return;

        uint256 namehash = calc_planet_name_hash(pinfo.name, pinfo.star_projectID);

        bool success = _planet_name_registry.remove_from_parent(namehash, planetID);
        assert(success == true);
    }


    /**
     * If new_name == FREE_NULL_NAME it doesn't register the project
     */
    function _change_planet_name(uint planetID, bytes32 new_name) internal
    {
        PlanetInfo storage pinfo = _planets_info[planetID];

        uint256 new_namehash = 0;

        if(FREE_IsNullName(new_name) == false)
        {
            new_namehash = calc_planet_name_hash(new_name, pinfo.star_projectID);
            uint256 foundID = _find_planetID_by_hash(new_namehash, pinfo.star_projectID);
            if(foundID != 0)
            {
                revert ErrDAO_PlanetWithNameAlreadyExists(new_name, pinfo.star_projectID);
            }
        }

        
        _unregister_planet_name(planetID);
        
        if(new_namehash != 0)
        {
            _planet_name_registry.insert(new_namehash, planetID);
        }
        
        pinfo.name = new_name;
    }

    function _create_planet(
        PlanetEntryParams memory params
    ) internal returns(uint256)
    {
        uint256 next_planetID = _new_planetID + 1;
        // attemp to register new planet with name
        // this could revert if name has been already used.
        // If name == FREE_NULL_NAME it doesn't register the project.
        
        _register_planet_name(params.planet_name, params.star_projectID, next_planetID);

        _new_planetID = next_planetID;

        bool freeminting = params.island_free_minting;

        if(_star_planet_minting[params.star_projectID].island_free_minting == false)
        {
            freeminting = false;
        }

        _planets_info[next_planetID] = PlanetInfo({
            name:params.planet_name,
            star_projectID:params.star_projectID,
            star_prestige:params.star_prestige,
            island_count:0,
            commission_increment:params.commission_increment,
            vesting_commissions:0,
            last_vesting_period:0,
            liberated_commissions:0,
            island_minting_nonce: freeminting ? 0:1,
            share_list_head:0
        });

        // register star planet belonging
        _star_planets_map.insert(uint256(params.star_projectID), next_planetID);

        // send event
        emit PlanetCreated(params.star_projectID, next_planetID);

        return next_planetID;
    }

    function _create_planet_share(
        uint256 planetID,
        address planet_share_owner,
        uint256 share_percentaje,
        bool planet_control_delegate
    ) internal returns(uint256)
    {
        if( planet_share_owner == address(0) ||
            planetID <= FREE_DEFAULT_TOKEN_ID ||
            share_percentaje == 0
        )
        {
            revert ErrDAO_InvalidParams();
        }

        PlanetInfo storage pinfo = _planets_info[planetID];
        if(pinfo.star_projectID <= FREE_DEFAULT_TOKEN_ID64)
        {
            revert ErrDAO_PlanetDoesNotExists(planetID);
        }

        _new_planetID++;

        _planets_shares_registry[_new_planetID] = PlanetShareInfo({
            planetID: planetID,
            planet_control_delegate:planet_control_delegate,
            share_percentaje:share_percentaje,
            payout_amount:0,
            share_list_next: pinfo.share_list_head
        });

        // link list
        pinfo.share_list_head = _new_planetID;

        _planet_share_ownership.grant(planet_share_owner, _new_planetID);

        // notify share ownership
        emit PlanetOwnershipTransferred(_new_planetID, planet_share_owner);

        return _new_planetID;
    }

    /**
     * This method is called by FREEDERATION
     */
    function create_planet(
        PlanetEntryParams memory params
    ) onlyOwner external returns(uint256)
    {
        return _create_planet(params);
    }

    function create_planet_share(
        uint256 planetID,
        address planet_share_owner,
        uint256 share_percentaje,
        bool planet_control_delegate
    ) onlyOwner external returns(uint256)
    {
        return _create_planet_share(
            planetID,
            planet_share_owner,
            share_percentaje,
            planet_control_delegate
        );
    }

    //////////////////////////7 Planet Info //////////////////////////77

    function get_planet_info(uint256 planetID) public view returns(PlanetInfo memory)
    {
        return _planets_info[planetID];
    }

    function get_planet_star_projectID(uint256 planetID) public view returns(uint256)
    {
        return _planets_info[planetID].star_projectID;
    }

    function get_planet_share_info(uint256 planet_shareID) public view returns(PlanetShareInfo memory)
    {
        return _planets_shares_registry[planet_shareID];
    }

    function get_share_planetID(uint256 planet_shareID) public view returns(uint256)
    {
        return _planets_shares_registry[planet_shareID].planetID;
    }


    /// Planet Ownership ///
    function planet_share_owner_addr(uint256 shareID) public view returns(address)
    {     
        if(shareID <= FREE_DEFAULT_TOKEN_ID) return address(0);
        return _planet_share_ownership.ownerOf(shareID);
    }

    function is_planet_share_owner(uint256 shareID, address pk_owner) public view returns(bool)
    {     
        if(shareID <= FREE_DEFAULT_TOKEN_ID || pk_owner == address(0)) return false;
        return _planet_share_ownership.ownerOf(shareID) == pk_owner ? true : false;
    }

    /**
     * This method is called by FREEDERATION
     */
    function revoke_planet_share_ownership(uint256 shareID) external onlyOwner
    {
        _planet_share_ownership.revoke(shareID);
    }

    /**
     * The owner could call this method
     */
    function transfer_planet_share_ownership(uint256 shareID, address new_owner) external
    {        
        _planet_share_ownership.transfer(shareID, msg.sender, new_owner);

        emit PlanetOwnershipTransferred(shareID, new_owner);
    }

    /**
     * Number of planet shares owned by pk_owner
     */
    function get_planet_shares_inventory_count(address pk_owner) public view returns(uint64)
    {
        return _planet_share_ownership.list_count(pk_owner);
    }

    function get_inventory_planet_shareID(address pk_owner, uint64 index) public view returns(uint256)
    {
        return _planet_share_ownership.get(pk_owner, index);
    }

    
    //////////////// Minting ///////////////////////////

    function get_planet_minting_nonce(uint64 star_projectID) public view returns(uint32)
    {
        StarPlanetMinting storage minting = _star_planet_minting[star_projectID];
        return minting.planet_minting_nonce;
    }

    function allows_free_island_minting(uint64 star_projectID) public view returns(bool)
    {
        StarPlanetMinting storage minting = _star_planet_minting[star_projectID];
        return minting.island_free_minting;
    }


    /// Use this for calc signature
    function calc_planet_minting_signature_hash(
        uint64 star_projectID,
        address target
    ) public view returns(bytes32)
    {
        StarPlanetMinting storage minting = _star_planet_minting[star_projectID];
        return keccak256(abi.encode(star_projectID, minting.planet_minting_nonce, target));
    }


    /**
     * Attempts to mint a planet from the reserved inventory.
     * Only could be invoked by Star project founder.
     * Returns a tuple with an unique planet share: (planetID, planet_shareID)
     */
    function owner_planet_minting(
        address pk_owner, PlanetEntryParams memory params
    ) external onlyOwner returns(uint256, uint256)
    {
        StarPlanetMinting storage minting = _star_planet_minting[params.star_projectID];

        if(minting.founder_planet_reserve == 0)
        {
            revert ErrDAO_NotAllowedToMintPlanet(params.star_projectID, pk_owner);
        }

        uint256 new_planetID = _create_planet(params);

        // create share
        uint new_shareID = _create_planet_share(
            new_planetID,
            pk_owner,
            FREE_PERCENTAJE_FACTOR,true
        );

        minting.founder_planet_reserve--;

        return (new_planetID, new_shareID);
    }

    /**
     * Returns a tuple with an unique planet share: (planetID, planet_shareID)
     */
    function planet_minting_signature(
        address target, uint256 payment,
        PlanetEntryParams memory params,
        SignatureAuthorization memory authorization
    ) external onlyOwner returns(uint256, uint256)
    {
        StarPlanetMinting storage minting = _star_planet_minting[params.star_projectID];
        if(minting.initial_planet_mint_count == 0)
        {
            revert ErrDAO_NotAllowedToMintPlanet(params.star_projectID, target);
        }

        if(minting.planet_minting_price > payment)
        {
            revert ErrDAO_NotEnoughFundsForMintingPlanet(params.star_projectID, minting.planet_minting_price);
        }

        if(minting.planet_minting_nonce > 0)
        {
            // check signature
            bytes32 chash = keccak256(abi.encode(params.star_projectID, minting.planet_minting_nonce, target));
            bytes32 eth_digest = MessageHashUtils.toEthSignedMessageHash(chash);// adapt to Ethereum signature format

            (address recovered, ECDSA.RecoverError error, ) = ECDSA.tryRecover(
                eth_digest, 
                authorization.parity_v,
                authorization.signature_r,
                authorization.signature_s
            );

            if(error != ECDSA.RecoverError.NoError || recovered != authorization.pk_authorizer) 
            {
                revert ErrDAO_NotAllowedToMintPlanet(params.star_projectID, target);
            }

            minting.planet_minting_nonce++;
        }       

        uint256 new_planetID = _create_planet(params);
        // create share
        uint new_shareID = _create_planet_share(
            new_planetID,
            target,
            FREE_PERCENTAJE_FACTOR,true
        );

        minting.initial_planet_mint_count--;

        return (new_planetID, new_shareID);
    }

    /**
     * Returns a tuple with an unique planet share: (planetID, planet_shareID)
     */
    function planet_minting_freely(
        address target, uint256 payment,
        PlanetEntryParams memory params        
    ) external onlyOwner returns(uint256, uint256)
    {
        StarPlanetMinting storage minting = _star_planet_minting[params.star_projectID];
        
        if( minting.initial_planet_mint_count == 0 ||            
            minting.planet_minting_nonce > 0)
        {
            revert ErrDAO_NotAllowedToMintPlanet(params.star_projectID, target);
        }

        if(minting.planet_minting_price > payment)
        {
            revert ErrDAO_NotEnoughFundsForMintingPlanet(params.star_projectID, minting.planet_minting_price);
        }

        
        uint256 new_planetID = _create_planet(params);
        // create share
        uint new_shareID = _create_planet_share(
            new_planetID,
            target,
            FREE_PERCENTAJE_FACTOR,true
        );

        minting.initial_planet_mint_count--;

        return (new_planetID, new_shareID);
    }

    //////////////////////Planet Config /////////////////////////////

    function _check_planet_controller(address operator, uint256 planet_shareID) internal view
    {
        if(is_planet_share_owner(planet_shareID, operator) == false)
        {
            revert ErrDAO_NotOwnsPlanetShare(planet_shareID, operator);
        }

        PlanetShareInfo storage psinfo = _planets_shares_registry[planet_shareID];
        if(psinfo.planet_control_delegate == false)
        {
            revert ErrDAO_NotAllowedToChangePlanet(psinfo.planetID, operator);
        }
    }


    function _check_planet_share_owner(address operator, uint256 planet_shareID) internal view
    {
        if(is_planet_share_owner(planet_shareID, operator) == false)
        {
            revert ErrDAO_NotOwnsPlanetShare(planet_shareID, operator);
        }
    }
    
    modifier canChangePlanet(uint256 _planet_shareID) {
        _check_planet_controller(msg.sender, _planet_shareID);
        _;
    }

    /**
     * This method can be called directly by planet owner
     */
    function config_planet_commission(
        uint256 planet_shareID,
        uint256 commission_increment
    ) external canChangePlanet(planet_shareID)
    {
        uint256 planetID = _planets_shares_registry[planet_shareID].planetID;
        PlanetInfo storage pinfo = _planets_info[planetID];
        pinfo.commission_increment = commission_increment;
    }

    function config_planet_free_minting(
        uint256 planet_shareID,
        bool free_minting
    ) external canChangePlanet(planet_shareID)
    {
        uint256 planetID = _planets_shares_registry[planet_shareID].planetID;
        PlanetInfo storage pinfo = _planets_info[planetID];
        StarPlanetMinting storage star_minting = _star_planet_minting[pinfo.star_projectID];

        if(free_minting == true && star_minting.island_free_minting == false)
        {
            revert ErrDAO_FreeMintingIsForbidden(planetID);
        }

        uint32 prevvalue = pinfo.island_minting_nonce;
        pinfo.island_minting_nonce = free_minting == true ? 0 : (prevvalue != 0 ? prevvalue : 1);
    }

    function change_planet_name(
        uint256 planet_shareID,
        bytes32 new_name
    ) external canChangePlanet(planet_shareID)
    {
        uint256 planetID = _planets_shares_registry[planet_shareID].planetID;

        _change_planet_name(planetID, new_name);
    }

    

    /**
     * Remarks: selling_price is optional. The actual payment from FREEDERATION, can be 0.
     */
    function calc_island_price(
        uint256 planetID,
        uint256 selling_price, // the actual payment from FREEDERATION, can be 0
        IslandPricingParams memory pricing_params
    ) public view returns(IslandPriceCalculation memory)
    {
        PlanetInfo storage pinfo = _planets_info[planetID];
        
        uint256 curvefloorprice = FREE_CalcLib.curve_floor_price(StarIslandBondingCurve({
            island_floor_price: pricing_params.island_floor_price,
            island_curve_price_rate: pricing_params.island_curve_price_rate,
            star_prestige: pinfo.star_prestige,
            island_count: (pinfo.island_count + 1) // avoid 0 value
        }));

        uint256 rawcommision = pinfo.commission_increment;
        rawcommision = rawcommision < pricing_params.minimum_commission ? pricing_params.minimum_commission : rawcommision;

        // Fix the actual commission if the selling price is greater than the suggested price
        if(selling_price > (curvefloorprice + rawcommision))
        {
            rawcommision = selling_price - curvefloorprice;
        }

        uint256 insurance = FREE_PERCENTAJE(rawcommision, pricing_params.insurance_rate);
        uint256 freederation_tax = FREE_PERCENTAJE(rawcommision, pricing_params.freederation_tax_rate);

        return IslandPriceCalculation({
            island_sales_price: (curvefloorprice + rawcommision),
            planet_commission: (rawcommision - insurance - freederation_tax),
            insurance_contribution: insurance,
            freederation_tax_contribution: freederation_tax
        });
    }

    function get_island_minting_nonce(uint256 planetID) public view returns(uint32)
    {
        PlanetInfo storage pinfo = _planets_info[planetID];
        return pinfo.island_minting_nonce;
    }

    /// Use this for calc signature
    function calc_island_minting_signature_hash(
        uint256 planet_shareID,
        address target
    ) public view returns(bytes32)
    {
        PlanetShareInfo storage pshareinfo = _planets_shares_registry[planet_shareID];
        PlanetInfo storage pinfo = _planets_info[pshareinfo.planetID];
        return keccak256(abi.encode(planet_shareID, pinfo.island_minting_nonce, target));
    }

    function _update_vesting_period(PlanetInfo storage pinfo, address star_db_contract_addr) internal
    {
        IStarProjectDB star_db_contract = IStarProjectDB(star_db_contract_addr);
        uint64 vesting_period = star_db_contract.current_star_vesting_cycle(pinfo.star_projectID);

        if(pinfo.last_vesting_period < vesting_period)
        {

            // check if we don't have a sanctioned vesting period
            if(star_db_contract.is_vesting_cycle_sanctioned(pinfo.star_projectID, pinfo.last_vesting_period) == false)
            {
                // not sanctioned, then aggregate the last vesting commission
                pinfo.liberated_commissions += pinfo.vesting_commissions;
            }
            // else, clear commissions and forget last vesting period
            
            pinfo.vesting_commissions = 0;
            pinfo.last_vesting_period = vesting_period;
        }
    }


    function _mint_island_final(
        PlanetInfo storage pinfo,
        uint256 commision,
        address star_db_contract_addr
    ) internal
    {
        _update_vesting_period(pinfo, star_db_contract_addr);

        pinfo.vesting_commissions += commision;
        pinfo.island_count++;
    }

    /**
     * Commission is calculated by FREEDERATION.
     * PRE: FREEDERATION should check if Star project allows free minting.
     */
    function mint_island_freely(
        uint256 planetID,
        uint256 commision,        
        address star_db_contract_addr
    ) external onlyOwner
    {
        PlanetInfo storage pinfo = _planets_info[planetID];
        
        /*
        --- FREEDERATION should check if Star project allows free minting.

        bool islandfreeminting = _star_planet_minting[pinfo.star_projectID].island_free_minting;        
        if(pinfo.island_minting_nonce > 0 || islandfreeminting == false)
        {
            revert ErrDAO_NotAllowedToMintIsland(planetID, target);
        }
        */

        _mint_island_final(pinfo, commision, star_db_contract_addr);
    }


    function mint_island_signature(
        uint256 planet_shareID,
        uint256 commision,        
        address target,
        address star_db_contract_addr,
        SignatureAuthorization memory authorization
    ) external onlyOwner
    {
        _check_planet_share_owner(authorization.pk_authorizer, planet_shareID);

        PlanetShareInfo storage pshareinfo = _planets_shares_registry[planet_shareID];
        PlanetInfo storage pinfo = _planets_info[pshareinfo.planetID];
        
        if(pinfo.island_minting_nonce == 0)
        {
            if(_star_planet_minting[pinfo.star_projectID].island_free_minting == false)
            {                
                revert ErrDAO_NotAllowedToMintPlanet(pinfo.star_projectID, target);
            }            
        }

        if(pinfo.island_minting_nonce > 0)
        {
            bytes32 chash = keccak256(abi.encode(planet_shareID, pinfo.island_minting_nonce, target));

            bytes32 eth_digest = MessageHashUtils.toEthSignedMessageHash(chash);// adapt to Ethereum signature format

            (address recovered, ECDSA.RecoverError error, ) = ECDSA.tryRecover(
                eth_digest, 
                authorization.parity_v,
                authorization.signature_r,
                authorization.signature_s
            );

            if(error != ECDSA.RecoverError.NoError || recovered != authorization.pk_authorizer) 
            {
                revert ErrDAO_NotAllowedToMintPlanet(pinfo.star_projectID, target);
            }

            pinfo.island_minting_nonce++;
        }

        _mint_island_final(pinfo, commision, star_db_contract_addr);
    }

    /// ////////////////////////////////////////////////////////// ///

    function determine_commissions_payout(
        uint256 planet_shareID,
        address star_db_contract_addr
    ) public view returns(uint256, address)
    {
        address share_owner = _planet_share_ownership.ownerOf(planet_shareID);
        if(share_owner == address(0)) return (0, address(0));

        PlanetShareInfo storage pshareinfo = _planets_shares_registry[planet_shareID];
        PlanetInfo storage pinfo = _planets_info[pshareinfo.planetID];

        // get vesting period
        IStarProjectDB star_db_contract = IStarProjectDB(star_db_contract_addr);
        uint64 vesting_period = star_db_contract.current_star_vesting_cycle(pinfo.star_projectID);

        uint256 accumulated_commissions = pinfo.liberated_commissions;
        if(vesting_period > pinfo.last_vesting_period)
        {
            // check if we don't have a sanctioned vesting period
            if(star_db_contract.is_vesting_cycle_sanctioned(pinfo.star_projectID, pinfo.last_vesting_period) == false)
            {
                accumulated_commissions += pinfo.vesting_commissions;
            }
        }

        uint256 portion_commissions = FREE_PERCENTAJE(accumulated_commissions, pshareinfo.share_percentaje);
        return (portion_commissions - pshareinfo.payout_amount, share_owner);
    }

    /**
     * Returns the tuple of (payout, star_projectID)
     */
    function extract_commissions_payout(
        uint256 planet_shareID,
        address client_target,
        address star_db_contract_addr
    ) external onlyOwner returns(uint256, uint64)
    {
        _check_planet_share_owner(client_target, planet_shareID);

        PlanetShareInfo storage pshareinfo = _planets_shares_registry[planet_shareID];
        PlanetInfo storage pinfo = _planets_info[pshareinfo.planetID];

        // update vesting period
        _update_vesting_period(pinfo, star_db_contract_addr);

        uint256 portion_commissions = FREE_PERCENTAJE(pinfo.liberated_commissions, pshareinfo.share_percentaje);

        uint256 ret_commissions = portion_commissions - pshareinfo.payout_amount;
        
        pshareinfo.payout_amount = portion_commissions;// account commissions

        return (ret_commissions, pinfo.star_projectID);
    }
    

}