//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./RingMarket.sol";
import "../util/PCGRandomLib.sol";

library IslandRingMarketLib
{
    uint256 constant RING_NUMBER_MASK = (uint256(1) << 128) - 1;    
    
    /**
     * Ring token consist on a combination of a 128bit number and the 64bit project ID.
     */
    function get_ring_codes_pair(uint256 ring_tokenID) pure internal returns(uint64, uint128)
    {
        uint256 ring_number = ring_tokenID & RING_NUMBER_MASK;
        uint256 projectID = ring_tokenID >> 128;
        return (uint64(projectID), uint128(ring_number));
    }

    function calc_ring_code(uint64 projectID, uint128 ring_code) pure internal returns(uint256)
    {
        return uint256(ring_code) | (uint256(projectID) << 128);
    }

    function calc_ring_groupID(uint64 projectID, uint128 ring_code) pure internal returns(uint256)
    {
        return calc_ring_code(projectID, (ring_code % 5) + 1);
    }

    function calc_ring_color(uint128 ring_code) pure internal returns(uint32)
    {
        return uint32(ring_code % 5);
    }

}

struct RingGenRange
{
    uint128 num_rings;
    uint128 base_range;
}

struct IslandRingGenParams
{
    address receiver;
    uint64 star_projectID;
    uint256 islandID;
    uint256 rnd_seed;
    uint32 required_rings;
    uint32 max_iterations;
}

contract IslandRingMarket is FREE_RingMarket
{
    mapping(uint64 => RingGenRange) internal _rings_x_project;
    mapping(uint256 => uint32) internal _island_rings_result; 

    constructor(address equityListenerAddr, uint32 handleCode, address initialOwner)
    FREE_RingMarket(5, equityListenerAddr, handleCode, initialOwner)
    {
    }

    function register_project(uint64 star_projectID) external onlyOwner
    {
        _rings_x_project[star_projectID] = RingGenRange({
            num_rings:0,
            base_range:5
        });
    }

    function generated_rings_x_island(uint256 islandID) public view returns(uint32)
    {
        return _island_rings_result[islandID];
    }

    function get_project_ring_range(uint64 star_projectID) public view returns(RingGenRange memory)
    {
        return _rings_x_project[star_projectID];
    }

    function project_rnd_range_number(uint64 star_projectID) public view returns(uint128)
    {
        return _rings_x_project[star_projectID].base_range * 5;
    }

    function _create_ring_from_code(uint64 star_projectID, uint128 rng_number, address receiver) internal returns(bool)
    {
        uint256 ring_codeID = IslandRingMarketLib.calc_ring_code(star_projectID, rng_number);
        
        if(ring_token_exists(ring_codeID) == true)
        {
            return false; // a collision
        }

        uint256 groupID = IslandRingMarketLib.calc_ring_groupID(star_projectID, rng_number);

        // create a new ring
        _create_ring_token(ring_codeID, groupID, receiver);

        // upgrade range
        RingGenRange storage rangeinfo = _rings_x_project[star_projectID];        
        rangeinfo.num_rings++;
        if(rangeinfo.num_rings >= rangeinfo.base_range)
        {
            rangeinfo.base_range = rangeinfo.num_rings*5;
        }

        return true;
    }

    /**
     * Generate 5 rings for receiver.
     * Returns the number of generated rings. Could be less than 5.
     */
    function generate_random_rings(
        IslandRingGenParams memory params
    ) external nonReentrant onlyOwner returns(uint32)
    {
        uint256 rseed = params.rnd_seed;
        uint32 num_rings = 0;
        uint32 niterations = 0;
        uint32 max_rings = params.required_rings;

        while(num_rings < max_rings && niterations < params.max_iterations)
        {
            (uint256 rnumber, uint256 next_seed) = PCGSha256RandomLib.next_value(rseed);

            rseed = next_seed;

            uint128 ring_range = project_rnd_range_number(params.star_projectID);

            uint128 rnumber0 = uint128(rnumber & IslandRingMarketLib.RING_NUMBER_MASK) % ring_range;
            uint128 rnumber1 = uint128(rnumber >> 128) % ring_range;

            bool bring_created = _create_ring_from_code(params.star_projectID, rnumber0, params.receiver);
            if(bring_created) num_rings++;

            if(num_rings < max_rings)
            {
                bring_created = _create_ring_from_code(params.star_projectID, rnumber1, params.receiver);
                if(bring_created) num_rings++;                
            }

            niterations++;
        }

        // register the already generated rings
        _island_rings_result[params.islandID] = num_rings;

        return num_rings;
    }
}