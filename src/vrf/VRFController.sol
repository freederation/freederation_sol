//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./VRFCircleProblem.sol";
import "./VRFCampaignTaskDB.sol";
import "./VRFIslandDB.sol";
import "./VRFLeadboard.sol";
import "./VRFSignedRecordDB.sol";
import "../util/FREEStackArray.sol";


error ErrVRF_NotEnoughFeeStoragePayment();


// VRF DAO
uint256 constant VRF_RECORD_STORAGE_FEE = 100000;

/*
 * This limit rate increments max_records_x_campaign for reputation earnings.
 */
uint32 constant VRF_CAMPAIGN_RECORDS_UPGRADE_RATE = 8;
uint32 constant VRF_MAX_CAMPAIGN_RECORDS_X_ISLAND = 6;

uint constant VRF_GATHEING_SIGNED_SOLUTIONS_INTERVAL = 2 hours;
uint constant VRF_GATHEING_REVEALED_SOLUTIONS_INTERVAL = 1 days;

uint32 constant VRF_MIN_AVAILABLE_RECORDS = 8;

uint256 constant VRF_FEE_PROBLEM_SOLVING = 0;
uint256 constant VRF_FEE_BONUS = 1;

enum eVRF_CAMPAIGN_STATUS 
{ 
    /**
    * No campaign has been inserted yet. New records would obtain 
    * the index of the last campaign.
    */
    VRFCAMPAIGN_IDLE,
    VRFCAMPAIGN_PROCESSING_PROBLEM,
    VRFCAMPAIGN_GATHERING_PROPOSALS,
    VRFCAMPAIGN_GATHERING_REVEALS,
    VRFCAMPAIGN_CLOSING
}


struct DVRANDAOParams 
{
    /**
     * Storage fee for creating a new record.
     * Records created during a processing phase don't have to pay a fee.
     */
    uint256 record_storage_fee;
    uint gathering_signed_solutions_interval;
    uint gathering_revealed_solutions_interval;
    /// Maximum number of proposals for campaign
    uint32 max_campaign_proposals;
    uint32 minimum_records_for_campaign;
    uint32 campaign_records_upgrade_rate;
    // For problem solving
    int64 solution_min_radius;
    uint32 max_static_circle_count;
    // Maximum radius of the generated circles
    int64 max_static_circle_radius;
    int64 problem_area_size;
}


interface IVRFController is IERC165
{
    //////////////////////////////// DAO Config   //////////////////////////////////

    function get_params() external view returns (DVRANDAOParams memory);

    function config_params(DVRANDAOParams calldata params) external;

    ////////////////////////////////______End DAO Config___//////////////////////////////////

    function get_islands_contract() external view returns (IVRFIslandDB);

    function get_campaigns_contract() external view returns (IVRFCampaignTaskDB);

    function get_records_contract() external view returns (IVRFSignedRecordDB);

    function get_problem_contract() external view returns (IVRFCircleProblem);

    function get_leadboard_contract() external view returns (IVRFLeadboard);

    ////////////////////////////////     DAO Status      //////////////////////////////////
    
    function get_random_seed() external view returns (uint256);
    function accumulated_fee_bounty() external view returns (uint256);
    function available_records() external view returns (uint256);
    function phase_due_time() external view returns (uint);

    function check_campaign_phase(uint blocktime) external;
    
    /*
     * This must be called after a reveal and after updating a campaign status;
     * @code
     * check_campaign_phase(daostate, blocktime);
     * @endcode
     */
    function finalize_campaign() external returns (bool);
    
    /**
     * This function must be called after finalize_campaign
     */
    function punish_leftovers() external;

    /**
     * Tells If this DAO is enabled for campaigns
     */
    function is_enabled_for_campaigns() external view returns (bool);

    function get_campaign_phase() external view returns (eVRF_CAMPAIGN_STATUS);

    function can_start_campaign() external view returns (bool);

    function current_campaignID() external view returns (uint256);

    function current_campaign_bounty() external view returns (uint256);
    
    ////////////// Public         --------------------///

    /*
     * This method should be used by the contract administrator, for enabling campaigns on this DAO.
     * @warning This is a trusted setup
     */
    function enable_first_campaign(uint256 master_seed) external;
    
    function insert_task(
        uint blocktime,
        uint256 task_refID,
        uint256 bounty
    ) external returns (uint256);

    

    ////////////////////////////////______Ending__Campaign___//////////////////////////////////

    //////////////////////////////// Record Management  ////////////////////////////////////
    
    function record_available_for_commitment(uint256 recordID) external view returns (bool);

    /// Record management
    function insert_record_payable(
        uint blocktime, // for calculating expiration time
        uint256 island_tokenID,
        address pk_owner,
        uint256 fee,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external returns (uint256);
    /**
     * Calling this method contributes to the problem processing.
     * By calling this method, the state of the DAO could transition to the VRFCAMPAIGN_GATHERING_PROPOSALS phase.
     * That's why this needs the blocktime for calculating the expiration time
     */
    function insert_record_problem_working(
        uint blocktime, // for calculating expiration time
        uint256 island_tokenID,
        address pk_owner,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external returns (uint256);

    /**
     * Insert record without paying fee, but bonus
     */
    function insert_record_by_bonus(
        uint blocktime, // for calculating expiration time
        uint256 island_tokenID,
        address pk_owner,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external returns (uint256);
    ////////////////////////////////______Ending__Record___//////////////////////////////////

    //////////////////////////////// Proposal  ////////////////////////////////////

    ////////////// Public RO Query   --------------------///
    function proposal_count() external view returns (uint32);

    function get_proposal(uint32 proposal_index) external view returns (uint256);

    
    ///////////// Public         --------------------///

    /**
     * This function validates if record belongs to Island and is allowed to be used.
     * Returns the proposal index.
     */
    function commit_proposal(
        address pk_owner,
        uint256 recordID,
        uint blocktime
    ) external returns(uint32);

    /**
     * This method has to be called before reveal_proposal() function
     */
    function validate_proposal_integrity(
        uint256 recordID,
        address pk_owner,
        int64 cx,
        int64 cy,
        int64 radius
    ) external returns (bool);

    /**
     * This method is called after validate_proposal_integrity
     */
    function punish_failed_reveal(uint256 recordID) external;


    /**
     * Punish island reputation and clears its bounty balance.
     * Reclaims the  last bounty balance, which will be accounted to accumulated bounty treasury 
     */
    function punish_island_reputation(uint256 islandID) external;

    /**
     * This method has to be called after validate_proposal_integrity().
     * Returns the Leaderboard ranking (1 -> first place; 2 -> second; 3 -> third).
     * Returns 0 if proposal couldn't be ranked but earns reputation.
     * And -1 if is a malformed transaction or wrong answer, thus damages reputation of the Island.
     */
    function reveal_proposal(
        uint256 recordID,
        address pk_owner,
        int64 cx,
        int64 cy,
        int64 radius
    ) external returns (int32);

    //////////////////////7///////// Helpers  /////// ////////////////////////////

    /**
     * This method needs to be called by client before attempting to insert new signed records on current campaign.
     * Returns the tuple with the 3 following fields:     
     * ( uint256(campaignID), uint32(island_index), uint256(storage_fee)).     
     * Where storage_fee tells if client could mint new records for free (with value 0, for contributing for the problem creation), 
     * or spending bonus credit (with value 1), or the actual fee that client has to pay.
     * If island_tokenID is not allowed to register more records, it returns (0, INVALID_INDEX32,0)
     * See also VRFSignedRecordLib.calc_record_params_hash
     */
    function suggested_record_indexparams(uint256 island_tokenID) external view returns (uint256, uint32, uint256);

    /// Helper function for obtaining digital signature hash for record
    /**
     * If Island doesn't have authorization for generating records, it returns 0
     */
    function digital_record_signature_helper(
        uint256 islandID,
        int64 cx,
        int64 cy,
        int64 radius
    ) external view returns (bytes32);
}

/// Implementation of IVRFController
contract VRFController is IVRFController, ERC165, FREE_Controllable 
{
    IVRFIslandDB private _islandDB;
    IVRFCampaignTaskDB private _campaignDB;
    IVRFSignedRecordDB private _signed_recordDB;
    IVRFCircleProblem private _circle_problem;
    IVRFLeadboard private _leadboard;

    eVRF_CAMPAIGN_STATUS private _process_status;

    /**
    * A consecutive index. Starts with 1. 0 Means no campaign has been initiated.
    * Tells the current campaign to be resolved with random number generation.
    */ 
    uint256 private _current_campaingID;

    /**
    * Storage fee for creating a new record. 
    * Records created during a processing phase don't have to pay a fee.
    */
    uint256 private _record_storage_fee;
    
    /**
    * Accumulated fees during the last campaign. It will be grant to the winner
    */
    uint256 private _accumulated_fee_bounty;

    uint private _gathering_signed_solutions_interval;
    uint private _gathering_revealed_solutions_interval;
    uint private _phase_due_time;/// Due time to the next phase
    
    /// Maximum number of proposals for campaign
    uint32 private _max_campaign_proposals;

    /**
    *  By default VRF_MIN_AVAILABLE_RECORDS
    */
    uint32 private _minimum_records_for_campaign;

    /// This limit rate increments max_records_x_campaign for reputation earnings.   
    uint32 private _campaign_records_upgrade_rate;

    /**
    * Proposals are identifiers to signed records
    */
    FREE_StackArray private _proposals;


    constructor(
        address island_db_contract,
        address campaign_db_contract,
        address records_db_contract,
        address circle_problem_contract,
        address leadboard_contract, address initialOwner) 
        FREE_Controllable(initialOwner)
    {
        _islandDB = IVRFIslandDB(island_db_contract);
        _campaignDB = IVRFCampaignTaskDB(campaign_db_contract);
        _signed_recordDB = IVRFSignedRecordDB(records_db_contract);
        _circle_problem = IVRFCircleProblem(circle_problem_contract);
        _leadboard = IVRFLeadboard(leadboard_contract);

        _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_IDLE;
        /// While the current campaign is 0, this DAO couldn't operate campaigns
        _current_campaingID = 0;
        _record_storage_fee = VRF_RECORD_STORAGE_FEE;
        _accumulated_fee_bounty = 0;
        _gathering_signed_solutions_interval = VRF_GATHEING_SIGNED_SOLUTIONS_INTERVAL;
        _gathering_revealed_solutions_interval = VRF_GATHEING_REVEALED_SOLUTIONS_INTERVAL;
        _max_campaign_proposals = VRF_MAX_CAMPAIGN_RECORDS_X_ISLAND;
        _minimum_records_for_campaign = VRF_MIN_AVAILABLE_RECORDS;
        _campaign_records_upgrade_rate = VRF_CAMPAIGN_RECORDS_UPGRADE_RATE;
        
    }

    //////////////////////////////// DAO Configuration  //////////////////////////////////

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IVRFController).interfaceId ||
            super.supportsInterface(interfaceId);
    }


    function get_params() external view virtual override returns (DVRANDAOParams memory) {
        return
            DVRANDAOParams({
                record_storage_fee: _record_storage_fee,
                gathering_signed_solutions_interval: _gathering_signed_solutions_interval,
                gathering_revealed_solutions_interval: _gathering_revealed_solutions_interval,
                max_campaign_proposals: _max_campaign_proposals,
                minimum_records_for_campaign: _minimum_records_for_campaign,
                campaign_records_upgrade_rate: _campaign_records_upgrade_rate,
                solution_min_radius: _circle_problem.get_solution_min_radius(),
                max_static_circle_count: _circle_problem.get_maximum_circle_count(),
                max_static_circle_radius: _circle_problem.get_maximum_circle_radius(),
                problem_area_size: _circle_problem.get_problem_area_size()
            });
    }

    function config_params(DVRANDAOParams calldata params) external virtual override onlyOwner {
        _record_storage_fee = params.record_storage_fee;
        _gathering_signed_solutions_interval = params.gathering_signed_solutions_interval;
        _gathering_revealed_solutions_interval = params.gathering_revealed_solutions_interval;
        _max_campaign_proposals = params.max_campaign_proposals;
        _minimum_records_for_campaign = params.minimum_records_for_campaign;
        _campaign_records_upgrade_rate = params.campaign_records_upgrade_rate;
        _circle_problem.set_solution_min_radius(params.solution_min_radius);
        _circle_problem.set_maximum_circle_count(params.max_static_circle_count);
        _circle_problem.set_maximum_circle_radius(params.max_static_circle_radius);
        _circle_problem.set_problem_area_size(params.problem_area_size);
    }

    ////////////////////////////////______End DAO Config___//////////////////////////////////

    function get_islands_contract() external view returns (IVRFIslandDB)
    {
        return _islandDB;
    }

    function get_campaigns_contract() external view returns (IVRFCampaignTaskDB)
    {
        return _campaignDB;
    }

    function get_records_contract() external view returns (IVRFSignedRecordDB)
    {
        return _signed_recordDB;
    }

    function get_problem_contract() external view returns (IVRFCircleProblem)
    {
        return _circle_problem;
    }

    function get_leadboard_contract() external view returns (IVRFLeadboard)
    {
        return _leadboard;
    }


    ////////////////////////////////     DAO Status      //////////////////////////////////

    function get_random_seed() external view virtual override returns (uint256) 
    {
        return _circle_problem.fetch_last_seed();        
    }

    function accumulated_fee_bounty() external view virtual override returns (uint256) 
    {
        return _accumulated_fee_bounty;
    }

    function available_records() external view virtual override returns (uint256) 
    {
        return _signed_recordDB.available_records();
    }

    function phase_due_time() external view virtual override returns (uint) 
    {
        return _phase_due_time;
    }

    
    //////////////////////////////// Campaign Management  ////////////////////////////////////
    function _could_start_campaign() internal view returns(bool)
    {
        uint256 campaigncount = _campaignDB.campaign_count();
        if(campaigncount == 0) return false;
        if(_current_campaingID >= campaigncount) return false;

        if(_signed_recordDB.available_records() < uint256(_minimum_records_for_campaign)) return false;
        return true;
    }

    function _reset_campaign() internal
    {
        // Its asummed that there is not leadboard ranking when calling this method
        _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM;
        _circle_problem.restart_problem();
    }

    function _check_campaign_phase(uint blocktime) internal
    {
        // If this DAO is idle, start problem solving
        if(_process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_IDLE)
        {
            // could start a new campaign.
            if(_could_start_campaign())
            {
                // If campaign ID is 0, it must be started by the administrator
                if(_current_campaingID > 0) 
                {
                    // advance to the problem solving phase
                    _current_campaingID++;
                    _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM;
                }
            }
        }
        else if(_process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_PROPOSALS)
        {
            if(blocktime > _phase_due_time)
            {
                // check ammount of proposals
                if(_proposals.count == 0)
                {
                    // restart campaign.
                    _reset_campaign();
                }
                else 
                {
                    // move to the next phase for reveals
                    _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_REVEALS;
                    _phase_due_time = blocktime + _gathering_revealed_solutions_interval;
                }
            }
            else if(_proposals.count >= _max_campaign_proposals) // check if has reached the number of proposals for the next phase
            {
                // move to the next phase for reveals
                _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_REVEALS;
                _phase_due_time = blocktime + _gathering_revealed_solutions_interval;
            }
        }
        else if(_process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_REVEALS)
        {
            // All proposals have been reveal? or the due time has reached?
            if(blocktime > _phase_due_time || _proposals.count == 0)
            {
                // mark the finalization phase
                _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_CLOSING;
            }
        }
    }

    
    function check_campaign_phase(uint blocktime) external virtual override onlyOwner
    {
        _check_campaign_phase(blocktime);
    }

    /*
    * This must be called after a reveal and after updating a campaign status;
    * @code
    * check_campaign_phase(daostate, blocktime);
    * @endcode
    */
    function finalize_campaign() external virtual override onlyOwner returns (bool)
    {
        assert(_process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_CLOSING);

        // check if there is a winner
        uint256 first_place = _leadboard.first_place();
        bool sucessful = true;
        if (first_place == 0) 
        {
            // No winners on this round, restart the campaign
            sucessful = false;
            _reset_campaign();
        } 
        else
        {
            // generate random sequence
            uint256 next_rnd_number = _circle_problem.next_rnd_number(); // base number
            next_rnd_number = _leadboard.generate_seed_rnd(next_rnd_number); // generate number with leadboard

            _circle_problem.configure(next_rnd_number);// restart problem

            // obtain bounty and clear campaign
            uint256 bounty = _campaignDB.finalize_campaign(_current_campaingID, next_rnd_number, first_place);

            // reward participants            
            // Assign bounty to the ifrst place
            uint256 islandID = _signed_recordDB.get_record_island(first_place);

            _islandDB.reward_island_bounty(islandID, bounty + _accumulated_fee_bounty);

            // clear accumulated bounty
            _accumulated_fee_bounty = uint256(0);


            // second and third places obtain bonus credits
            uint256 second_place = _leadboard.second_place();
            if (second_place != 0) 
            {
                islandID = _signed_recordDB.get_record_island(second_place);
                // reward second place with 2 game credits
                _islandDB.reward_island_bonus_credits(islandID, 2);

                uint256 third_place = _leadboard.third_place();
                if (third_place != 0) 
                {
                    islandID = _signed_recordDB.get_record_island(third_place);
                    // reward third place with 1 game credit
                    _islandDB.reward_island_bonus_credits(islandID, 1);
                }
            }

            // clear leadboard
            _leadboard.reset_leader_board();

            // attempts to start a new campaign
            bool move_next = _could_start_campaign();
            if (move_next) 
            {
                // advance to the next problem solving phase
                _current_campaingID++;
                _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM;
            } 
            else 
            {
                // put status as idle
                _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_IDLE;
            }

            sucessful = true;
        }

        return sucessful;
    }

    /**
     * This function must be called after finalize_campaign
     */
    function punish_leftovers() external virtual override onlyOwner
    {
        // punish leftovers
        // This loop is under control, no more proposals up to max_campaign_proposals
        uint32 proposalcount = _proposals.count;
        if (proposalcount > 0) 
        {
            for (uint32 i = 0; i < proposalcount; i++) 
            {
                uint256 fault_recordID = FREE_StackArrayUtil.get(_proposals, i);

                // mark record as faulted
                _signed_recordDB.update_record_revelation_status(fault_recordID, false);

                // punish island and take its bounty
                uint256 fauld_islandID = _signed_recordDB.get_record_island(fault_recordID);
                _accumulated_fee_bounty += _islandDB.punish_island_reputation(fauld_islandID);
            }

            FREE_StackArrayUtil.clear(_proposals);
        }
    }

    ////////////// Public RO Query   --------------------///

    /**
     * Tells If this DAO is enabled for campaigns
     */
    function is_enabled_for_campaigns() external view  virtual override returns (bool) 
    {
        return _current_campaingID != 0;
    }

    function get_campaign_phase() external view virtual override returns (eVRF_CAMPAIGN_STATUS) 
    {
        return _process_status;
    }

    function can_start_campaign() external view virtual override returns (bool) 
    {
        return _could_start_campaign();
    }
   
       function current_campaignID() external view virtual override returns (uint256) 
    {
        return _current_campaingID;
    }

    
    function current_campaign_bounty() external view virtual override returns (uint256) 
    {
        if (_current_campaingID == 0) return 0;
        return _campaignDB.campaign_bounty(_current_campaingID) + _accumulated_fee_bounty;
    }

    ////////////// Public         --------------------///

    /*
     * This method should be used by the contract administrator, for enabling campaigns on this DAO.
     * @warning This is a trusted setup
     */
    function enable_first_campaign(uint256 master_seed) external virtual override onlyOwner 
    {
        bool could = _could_start_campaign();
        if (could == false) 
        {
            revert ErrVRF_CannotEnableCampaigns();
        }

        _circle_problem.configure(uint256(keccak256(abi.encodePacked(master_seed, block.timestamp))));
        _current_campaingID = 1;
        _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM;        
    }

    function insert_task(
        uint blocktime,
        uint256 task_refID,
        uint256 bounty
    ) external virtual override onlyOwner returns (uint256) 
    {        
        uint256 new_campaignID = _campaignDB.insert_task(task_refID, bounty);        
        // If this DAO is idle, start problem solving
        _check_campaign_phase(blocktime);
        return new_campaignID;
    }
    

    ////////////////////////////////______Ending__Campaign___//////////////////////////////////

    //////////////////////////////// Record Management  ////////////////////////////////////
    

    function record_available_for_commitment(uint256 recordID)
        external
        view virtual override
        returns (bool)
    {
        return _signed_recordDB.record_available_for_commitment(recordID, _current_campaingID);
    }

    /// Record management
    function _insert_signed_record_base(
        uint256 island_tokenID,
        address pk_owner,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) internal returns(uint256)
    {
        /// register_signed_record r(aises errors  : pk_owner must have authorization on island)
        uint32 island_campaign_index = _islandDB.register_signed_record(
            island_tokenID, pk_owner, _current_campaingID
        );
        assert(island_campaign_index != INVALID_INDEX32);

        // insert new record
        uint256 new_recordID = _signed_recordDB.insert_new_record(
            island_tokenID, pk_owner,
            _current_campaingID, island_campaign_index,
            signature_r, signature_s, parity_v
        );
        
        return new_recordID;
    }


    function insert_record_payable(
        uint blocktime, // for calculating expiration time
        uint256 island_tokenID,
        address pk_owner,
        uint256 fee,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external virtual override onlyOwner returns (uint256) 
    {
        if (fee < _record_storage_fee) 
        {
            revert ErrVRF_NotEnoughFeeStoragePayment();
        }

        // this method raises errors
        uint256 newrecordID = _insert_signed_record_base(
            island_tokenID, pk_owner, signature_r, signature_s, parity_v
        );

        
        _accumulated_fee_bounty += fee;

        // attempt to initiate problem solving phase if idle
        _check_campaign_phase(blocktime);
        return newrecordID;
    }

    /**
     * Calling this method contributes to the problem processing.
     * By calling this method, the state of the DAO could transition to the VRFCAMPAIGN_GATHERING_PROPOSALS phase.
     * That's why this needs the blocktime for calculating the expiration time
     */
    function insert_record_problem_working(
        uint blocktime, // for calculating expiration time
        uint256 island_tokenID,
        address pk_owner,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external virtual override onlyOwner returns (uint256) 
    {
        if (_process_status != eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM) 
        {
            revert ErrVRF_IslandCannotEarnBonusAtThisMoment();
        }

        // this method raises errors
        uint256 newrecordID = _insert_signed_record_base(
            island_tokenID, pk_owner, signature_r, signature_s, parity_v
        );


        // contribute to the problem solving
        bool hasfinished = _circle_problem.insert_new_circle();
        if (hasfinished) 
        {
            // move to gathering process
            _process_status = eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_PROPOSALS;
            // calculation the expiration time
            _phase_due_time = blocktime + _gathering_signed_solutions_interval;
        }

        // earn a bonus
        _islandDB.reward_island_bonus_credits(island_tokenID, 1);

        return newrecordID;
    }

    /**
     * Insert record without paying fee, but bonus
     */
    function insert_record_by_bonus(
        uint blocktime, // for calculating expiration time
        uint256 island_tokenID,
        address pk_owner,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external virtual override onlyOwner returns (uint256) 
    {
        // spend island bonus        
        _islandDB.consume_island_bonus_credit(island_tokenID); // This method raises errors
        
        
        // this method raises errors if reputation fails
        uint256 newrecordID = _insert_signed_record_base(
            island_tokenID, pk_owner, signature_r, signature_s, parity_v
        );
        // At this point, if _insert_signed_record_base fails, island_tokenID could lose a bonus credit. It cannot be restored

        // attempt to initiate problem solving phase if idle
        _check_campaign_phase(blocktime);
        return newrecordID;
    }

    ////////////////////////////////______Ending__Record___//////////////////////////////////

    //////////////////////////////// Proposal  ////////////////////////////////////

    ////////////// Public RO Query   --------------------///
    function proposal_count() external view virtual override returns (uint32) {
        return _proposals.count;
    }

    function get_proposal(uint32 proposal_index) external view virtual override returns (uint256) 
    {
        return FREE_StackArrayUtil.get(_proposals, proposal_index);
    }

    ///////////// Public         --------------------///

    /**
     * This function validates if record belongs to Island and is allowed to be used
     */
    function commit_proposal(
        address pk_owner,
        uint256 recordID,
        uint blocktime
    ) external virtual override onlyOwner returns(uint32)
    {
        /******** Validating Proposal *************/
        if (_process_status != eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_PROPOSALS)
        {
            revert ErrVRF_CannotCommitProposalsAtThisMoment();
        }

        if (recordID == uint256(0) || pk_owner == address(0)) 
        {
            revert Err_InvalidAddressParams();
        }

        (
            uint32 record_proposal_index,
            uint256 islandID,
            address record_pk,
            uint256 record_campaignID
        ) = _signed_recordDB.get_record_commit_proposal_fields(recordID);
        

        // Does this record not being played yet?
        if (record_proposal_index != VRF_RECORD_STATE_AVAILABLE) 
        {
            revert ErrVRF_RecordHasAlreadySpent(recordID);
        }

        if (record_pk != pk_owner) 
        {
            revert ErrVRF_InvalidRecordOwnerAddress(recordID, pk_owner);
        }
        
        if (islandID == uint256(0)) 
        {
            revert ErrVRF_RecordNotAssignedToIsland(recordID);
        }

        (
            uint32 reputation,
            address island_pk,
            uint256 island_last_campaign,
            uint256 last_island_proposal
        ) = _islandDB.proposal_fields(islandID);

        if (reputation < 1) 
        {
            revert ErrVRF_IslandReputationLost(islandID);
        }

        if (record_pk != island_pk) 
        {
            revert ErrVRF_InvalidRecordOwnerAddress(recordID, island_pk);
        }

        if(last_island_proposal != 0) 
        {
            revert ErrVRF_IslandHasAlreadyCommitted(islandID);
        }

        // check the campaign number
        if (record_campaignID > island_last_campaign) 
        {
            revert ErrVRF_RecordCampaignInconsistency(recordID);
        }

        // Time frame for the campaign proposals
        if (record_campaignID >= _current_campaingID) 
        {
            revert ErrVRF_RecordCommittedCampaignEarly(recordID);
        }

        /******** End Validating Proposal *************/

        /******** Registering Proposal *************/
        uint32 prop_index = FREE_StackArrayUtil.insert(_proposals, recordID);
        _signed_recordDB.record_commit_proposal(recordID, prop_index);

        // update island referencing
        _islandDB.assign_current_proposal(islandID, recordID);

        // check campaign phase
        _check_campaign_phase(blocktime);
        
        return prop_index;
    }

    /**
     * This method has to be called before reveal_proposal() function.
     * Also test if
     */
    function validate_proposal_integrity(
        uint256 recordID,
        address pk_owner,
        int64 cx,
        int64 cy,
        int64 radius
    ) external virtual override onlyOwner returns (bool) 
    {
        if (_process_status != eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_REVEALS) 
        {
            revert ErrVRF_CannotRevealProposalsAtThisMoment();
        }

        // This method reverts on error
        _signed_recordDB.assert_proposal_revelation_status(recordID, pk_owner);

        // valdiating record signature
        bool isvalid = _signed_recordDB.is_valid_record_signature(recordID, pk_owner, cx, cy, radius);
        if (isvalid == false) return false;

        // check circle solution
        // cannot touch borders of the space, and radius needs to be greater than solution_min_radius
        return _circle_problem.validate_solution(cx, cy, radius);
    }

    function _remove_proposal(uint32 index, bool revealed_success) internal
    {
        assert(index < _proposals.count);

        uint256 removed_recordID = FREE_StackArrayUtil.get(_proposals, index);

        _signed_recordDB.update_record_revelation_status(removed_recordID, revealed_success);

        (uint32 last_index, bool success) = FREE_StackArrayUtil.remove(_proposals, index);
        assert(success == true);
        if(last_index != index)
        {
            uint256 moved_recordID = FREE_StackArrayUtil.get(_proposals, index);

            // change index on target
            _signed_recordDB.set_record_proposal_index(moved_recordID, index);
        }
    }

    /**
     * This method is called after validate_proposal_integrity
     */
    function punish_failed_reveal(uint256 recordID) external virtual override onlyOwner
    {
        (uint32 proposal_index, uint256 fauld_islandID) = _signed_recordDB.get_record_reveal_proposal_fields(recordID);

        // punish island
        _accumulated_fee_bounty += _islandDB.punish_island_reputation(fauld_islandID);
        // remove proposal        
        _remove_proposal(proposal_index, false);
    }

    function punish_island_reputation(uint256 islandID) external virtual override onlyOwner
    {
        _accumulated_fee_bounty += _islandDB.punish_island_reputation(islandID);
    }    

    /**
     * This method has to be called after validate_proposal_integrity().
     * Returns the Leaderboard ranking (1 -> first place; 2 -> second; 3 -> third).
     * Returns 0 if proposal couldn't be ranked but earns reputation.
     * And -1 if is a malformed transaction or wrong answer, thus damages reputation of the Island.
     */
    function reveal_proposal(
        uint256 recordID,
        address pk_owner,
        int64 cx,
        int64 cy,
        int64 radius
    )
    external virtual override onlyOwner 
    returns (int32) 
    {
        (uint32 proposal_index, uint256 islandID) = _signed_recordDB.get_record_reveal_proposal_fields(recordID);

        // earn reputation and clear proposal
        _islandDB.earn_reputation(islandID, _campaign_records_upgrade_rate);
        
        // update leaderboard
        int32 score = _leadboard.insert_lb_candidate(recordID, pk_owner, cx, cy, radius);

        // remove proposal
        _remove_proposal(proposal_index, true);

        return score;
    }

    
    //////////////////////7///////// Helpers  /////// ////////////////////////////

    /**
     * This method needs to be called by client before attempting to insert new signed records on current campaign.
     * Returns the tuple with the 3 following fields:     
     * ( uint256(campaignID), uint32(island_index), uint256(storage_fee)).     
     * Where storage_fee tells if client could mint new records for free (with value 0, for contributing for the problem creation), 
     * or spending bonus credit (with value 1), or the actual fee that client has to pay.
     * If island_tokenID is not allowed to register more records, it returns (0, INVALID_INDEX32,0)
     * See also VRFSignedRecordLib.calc_record_params_hash
     */
    function suggested_record_indexparams(uint256 island_tokenID)
        external
        view virtual override
        returns (uint256, uint32, uint256)
    {
        (uint256 campaignID, uint32 island_index) = _islandDB.suggested_record_indexparams(island_tokenID, _current_campaingID);
        if(island_index == INVALID_INDEX32)
        {
            return (uint256(0), INVALID_INDEX32, uint256(0));
        }
        
        if(_process_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM)
        {
            /// return problem solving configuration
            return (campaignID, island_index, VRF_FEE_PROBLEM_SOLVING);
        }

        uint32 credits = _islandDB.get_island_bonus_credits(island_tokenID);
        if(credits > 0)
        {
            return (campaignID, island_index, VRF_FEE_BONUS);
        }

        return (campaignID, island_index, _record_storage_fee);
    }

    /// Helper function for obtaining digital signature hash for record
    /**
     * If Island doesn't have authorization for generating records, it returns 0
     */
    function digital_record_signature_helper(
        uint256 islandID,
        int64 cx,
        int64 cy,
        int64 radius
    ) external view virtual override returns (bytes32) {
        (uint256 campaignID, uint32 cindex) = _islandDB.suggested_record_indexparams(islandID, _current_campaingID);
        if (cindex == INVALID_INDEX32) return bytes32(0);
        return VRFSignedRecordLib.calc_record_params_hash(islandID, campaignID, cindex, cx, cy, radius);
    }
    ////////////////////////////////______Ending__Helpers_//////////////////////////////////
}