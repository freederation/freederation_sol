//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./VRFCircleProblem.sol";


error ErrVRF_NotAuthorizedToOperateOnIsland(uint256 islandID);

error ErrVRF_NotEnoughFundsOnIsland(uint256 islandID);

error ErrVRF_PreviousIslandOwnerMistake();

error ErrVRF_IslandCannotProduceMoreRecords(uint256 islandID);

error ErrVRF_IslandWithoutBonus(uint256 islandID);

error ErrVRF_IslandCannotEarnBonusAtThisMoment();

error ErrVRF_IslandReputationLost(uint256 islandID);

error ErrVRF_IslandHasAlreadyCommitted(uint256 islandID);


struct VRFIslandInfo
{
    /**
    * This Reputation score increments each time that the Island completes a reveal correctly.
    * In case of providing wrong information or failing to reveal its commited response, this score
    * is set to 0  and the Island get banned permanently. 
    */
    uint32 reputation;


    /**
    * Bonus credits for keep playing. This bonus could get earned when an
    * Island helps with the processing of the problem configuration, or
    * when helps with the termination of the campaign.
    */ 
    uint32 bonus_credits;

    /**
    * Maximum allowed signed records that an Island could submit during a campaign
    */
    uint32 max_records_x_campaign;

    /// Last campaign where this Island has inserted signed records
    uint256 last_campaingID;

    /// Count of records submitted on the current campaign
    uint32 last_campaign_record_count;


    /// current proposal record. 0 If not proposal has made yet
    uint256 current_proposal;

    /**
    * Paid balance from bounties
    */
    uint256 bounty_balance;

    address owner_address;
}

interface IVRFIslandDB is IERC165
{
    function get_island_owner(uint256 islandID) external view returns(address);
    function get_island_bounty_balance(uint256 islandID) external view returns(uint256);
    function get_island_reputation(uint256 islandID) external view returns(uint32);
    function get_island_bonus_credits(uint256 islandID) external view returns(uint32);
    function get_island_info(uint256 islandID) external view returns (VRFIslandInfo memory);
    
    /**
    * Maximum allowed signed records that an Island could submit during a campaign.
    * This could be updated depending on the reputation of the Island
    */
    function get_max_records_x_campaign(uint256 islandID) external view returns(uint32);

    /// Last campaign where this Island has inserted signed records
    function get_last_campaingID(uint256 islandID) external view returns(uint256);

    /// Count of records submitted on the current campaign
    function get_last_campaign_record_count(uint256 islandID) external view returns(uint32);


    /// current proposal record. 0 If not proposal has made yet
    function get_current_proposal(uint256 islandID) external view returns(uint256);

    

    /**
     * This method only could be used by the parent contract
     */
    function register_island(uint256 islandID, address island_owner) external;


    /**
     * This is called when the Island owner chooses a proposal for engaging in a random number generation campaign.	
     */
    function assign_current_proposal(uint256 islandID, uint256 recordID) external;

    /**
     *  Call this method before assigning a proposal.
     * It returns the tuple (reputation, owner_address, last_campaign, last_proposal)
     */
    function proposal_fields(uint256 islandID) external view returns(uint32, address, uint256, uint256);

    /**
     * This method only could be used by the parent contract
     */
    function change_island_owner(
        uint256 islandID,
        address prev_island_owner,
        address new_island_owner
    ) external;

    function consume_island_bounty_payout(
        uint256 islandID,
        address src_addr,
        uint256 value
    ) external;

    /**
     * Punish island reputation and clears its bounty balance.
     * returns the last bounty balance to be accounted to the DAO accumulated treasury 
     */
    function punish_island_reputation(uint256 islandID) external returns(uint256);

    /**
     * Accumulate bounty into the Island balance
     */
    function reward_island_bounty(uint256 islandID, uint256 bounty) external;

    function reward_island_bonus_credits(uint256 islandID, uint32 credits) external;

    /**
     * Consumes one island bonus credit.
     * If the island doesn't have enough bonus credits, it reverts the operation and raises an error.
     */
    function consume_island_bonus_credit(uint256 islandID) external;

    /**
     * This increases the campaign registration threshold, based on campaign_records_upgrade_rate
     */
    function earn_reputation(uint256 islandID, uint32 campaign_records_upgrade_rate) external;

    ///////////////// Signed record registering ////////////////////
    
    /**
    * This method needs to be called by client before attempting to insert new signed records on current campaign.
    * Returns the campaign ID and the index count for the next record (Corresponds to last_campaign_record_count, starting from 1).
    * If island_tokenID is not allowed to register more records, it returns (0, INVALID_INDEX32)
    */
    function suggested_record_indexparams(uint256 islandID, uint256 current_campaignID) external view returns(uint256, uint32);

    /**
     * This method appoints a new record for the Island associated to the current campaign. It checks
     * if the island could participate in this campaign, depending on the max_records_x_campaign.
     * Returns the current campaign index on the Island (Corresponds to last_campaign_record_count, starting from 1). 
     * In case of surpassing the limit or having a bad reputation, it reverts with an error and returns INVALID_INDEX32
     */
    function register_signed_record(uint256 islandID, address src_addr, uint256 current_campaignID) external returns(uint32);

}

contract VRFIslandDB is IVRFIslandDB, ERC165, FREE_Controllable 
{
    mapping(uint256 => VRFIslandInfo) _islands_info;

    constructor(address initialOwner) FREE_Controllable(initialOwner)
    {
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IVRFIslandDB).interfaceId || super.supportsInterface(interfaceId);
    }

    function get_island_owner(uint256 islandID) external view virtual override returns (address) 
    {
        VRFIslandInfo storage islandobj = _islands_info[islandID];
        return islandobj.owner_address;
    }

    function get_island_bounty_balance(uint256 islandID) external view virtual override returns (uint256)
    {
        VRFIslandInfo storage islandobj = _islands_info[islandID];
        return islandobj.bounty_balance;
    }

    function get_island_reputation(uint256 islandID)
        external view virtual override
        returns (uint32)
    {
        VRFIslandInfo storage islandobj = _islands_info[islandID];
        return islandobj.reputation;
    }

    function get_island_bonus_credits(uint256 islandID)
        external view virtual override
        returns (uint32)
    {
        VRFIslandInfo storage islandobj = _islands_info[islandID];
        return islandobj.bonus_credits;
    }

    function get_island_info(uint256 islandID)
        external view virtual override
        returns (VRFIslandInfo memory)
    {
        return _islands_info[islandID];
    }

    function get_max_records_x_campaign(uint256 islandID) external view virtual override returns(uint32)
    {
        VRFIslandInfo storage islandobj = _islands_info[islandID];
        return islandobj.max_records_x_campaign;
    }

    /// Last campaign where this Island has inserted signed records
    function get_last_campaingID(uint256 islandID) external view virtual override returns(uint256)
    {
        VRFIslandInfo storage islandobj = _islands_info[islandID];
        return islandobj.last_campaingID;
    }

    /// Count of records submitted on the current campaign
    function get_last_campaign_record_count(uint256 islandID) external view virtual override returns(uint32)
    {
        VRFIslandInfo storage islandobj = _islands_info[islandID];
        return islandobj.last_campaign_record_count;
    }


    /// current proposal record. 0 If not proposal has made yet
       function get_current_proposal(uint256 islandID) external view virtual override returns(uint256)
    {
        VRFIslandInfo storage islandobj = _islands_info[islandID];
        return islandobj.current_proposal;
    }

    ////////////// Public         --------------------///

    /**
     * This method only could be used by the parent contract
     */
    function register_island(uint256 islandID, address island_owner) external virtual override onlyOwner
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];      
        // Every Island starts with a base reputation. If faulted, it sets to 0,
        fetch_island.reputation = 1;
        fetch_island.bonus_credits = 0;
        fetch_island.max_records_x_campaign = 1;
        fetch_island.last_campaingID = 0;
        fetch_island.last_campaign_record_count = 0;      
        fetch_island.current_proposal = 0;
        fetch_island.bounty_balance = 0;
        fetch_island.owner_address = island_owner;
    }

    /**
     * This is called when the Island owner chooses a proposal for engaging in a random number generation campaign
     */
    function assign_current_proposal(uint256 islandID, uint256 recordID) external virtual override onlyOwner
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];
        fetch_island.current_proposal = recordID;
    }

    function proposal_fields(uint256 islandID)
    external view virtual override
    returns(uint32, address, uint256, uint256)
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];
        return (
            fetch_island.reputation,
             fetch_island.owner_address,
            fetch_island.last_campaingID,
            fetch_island.current_proposal
        );
    }

    /**
     * This method only could be used by the parent contract
     */
    function change_island_owner(
        uint256 islandID,
        address prev_island_owner,
        address new_island_owner
    ) external virtual override onlyOwner 
    {
        if(prev_island_owner == address(0) || new_island_owner == address(0))
        {
            revert Err_InvalidAddressParams();
        }

        VRFIslandInfo storage fetch_island = _islands_info[islandID];

        if(fetch_island.owner_address != prev_island_owner)
        {
            revert ErrVRF_PreviousIslandOwnerMistake();
        }

        fetch_island.owner_address = new_island_owner;
    }

    function consume_island_bounty_payout(
        uint256 islandID,
        address src_addr,
        uint256 value
    ) external virtual override onlyOwner 
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];

        if (fetch_island.owner_address != src_addr) {
            revert ErrVRF_NotAuthorizedToOperateOnIsland(islandID);
        }

        if (value > fetch_island.bounty_balance) {
            revert ErrVRF_NotEnoughFundsOnIsland(islandID);
        }

        fetch_island.bounty_balance -= value;
    }

    function punish_island_reputation(uint256 islandID) external virtual override onlyOwner returns(uint256)
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];
        uint256 last_bounty_balance = fetch_island.bounty_balance;
        fetch_island.bounty_balance = uint256(0);
        fetch_island.reputation = 0;
        fetch_island.bonus_credits = 0;
        return last_bounty_balance;
    }

    function reward_island_bounty(uint256 islandID, uint256 bounty) external virtual override onlyOwner
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];		
        fetch_island.bounty_balance += bounty;
    }

    function reward_island_bonus_credits(uint256 islandID, uint32 credits) external virtual override onlyOwner
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];		
        fetch_island.bonus_credits += credits;
    }

    function consume_island_bonus_credit(uint256 islandID) external virtual override onlyOwner
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];
        uint32 credit = fetch_island.bonus_credits;
        if(credit == 0)
        {
            revert ErrVRF_IslandWithoutBonus(islandID);
        }

        fetch_island.bonus_credits -= 1;
    }

    /**
     * This increases the campaign registration threshold, based on campaign_records_upgrade_rate
     */
    function earn_reputation(uint256 islandID, uint32 campaign_records_upgrade_rate) external virtual override onlyOwner
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];
        // earn reputation
        fetch_island.reputation++;
        // determine new capacity
        uint32 newcapacity = fetch_island.reputation / campaign_records_upgrade_rate;

        if (fetch_island.max_records_x_campaign < newcapacity) 
        {
            fetch_island.max_records_x_campaign = newcapacity;
        }
    }

    
    /**
    * This method needs to be called by client before attempting to insert new signed records on current campaign.
    * Returns the campaign ID and the index count for the next record (Corresponds to last_campaign_record_count, starting from 1).
    * If island_tokenID is not allowed to register more records, it returns (0, INVALID_INDEX32)
    */
    function suggested_record_indexparams(
        uint256 islandID, uint256 current_campaignID) 
        external view virtual override returns(uint256, uint32)
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];
      
        if(fetch_island.reputation < 1)
        {
            return (0, INVALID_INDEX32);
        }
        
        if(fetch_island.last_campaingID < current_campaignID)
        {
            // restart current campaign with count 1
            return (current_campaignID, 1);
        }

        // Island has been already in this campaign

        /// Check Island record limit      
        uint32 next_index = fetch_island.last_campaign_record_count + 1;
        if(fetch_island.max_records_x_campaign < next_index)
        {
            // reached limit
            return (0, INVALID_INDEX32);
        }

        return (current_campaignID, next_index);
    }

    /**
     * This method appoints a new record for the Island associated to the current campaign. It checks
     * if the island could participate in this campaign, depending on the max_records_x_campaign.
     * Returns the current campaign index on the Island (Corresponds to last_campaign_record_count, starting from 1). 
     * In case of surpassing the limit or having a bad reputation, it reverts with an error and returns INVALID_INDEX32
     */
    function register_signed_record(uint256 islandID, address src_addr, uint256 current_campaignID) 
    external virtual override onlyOwner returns(uint32)
    {
        VRFIslandInfo storage fetch_island = _islands_info[islandID];

        if(fetch_island.owner_address != src_addr)
        {
            revert ErrVRF_NotAuthorizedToOperateOnIsland(islandID);
        }


        if(fetch_island.reputation < 1)
        {
            revert ErrVRF_IslandReputationLost(islandID);
        }

        uint256 last_campaign_ref = fetch_island.last_campaingID;
        uint32 next_index = 1;// A new campaign starts with index 1
      
        if(last_campaign_ref == current_campaignID) // element has been already in this campaign
        {
            // update index
            next_index = fetch_island.last_campaign_record_count + 1;        

            /// Check Island record limit      
            if(fetch_island.max_records_x_campaign < next_index)
            {
                // reached limit
                revert ErrVRF_IslandCannotProduceMoreRecords(islandID);
            }
        }

        fetch_island.last_campaingID = current_campaignID;
        fetch_island.last_campaign_record_count = next_index;

        return next_index;
    }

}