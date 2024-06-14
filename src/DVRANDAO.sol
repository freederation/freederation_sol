//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./vrf/VRFController.sol";

contract DVRANDAO is Ownable, ReentrancyGuard 
{
    using Address for address;
    using FREE_StackArrayUtil for FREE_StackArray;

    event NewCampaign(uint256 campaign, uint256 task);
    event NewRecordSigned(
        address owner,
        uint256 island_id,
        uint256 record_id,
        uint256 current_campaign
    );
    event ProposalComitted(uint256 target_campaign, uint256 record_id, uint32 proposal_index);
    event ProposalRevealed(uint256 target_campaign, uint256 record_id);
    event ProposalRevealFailed(uint256 target_campaign, uint256 record_id);
    event ProposalFaulted(uint256 target_campaign, uint256 record_id);

    event CampaignSolvingInit(uint256 target_campaign);

    event CampaignGatheringProposals(uint256 target_campaign);
    //// This event is raised when no proposals are available. Restart problem
    event CampaignAbsenteeism(uint256 target_campaign);
    /// Capturing reveals after the proporsal commitment has finished
    event CampaignGatheringReveals(uint256 target_campaign);

    /// This event is raised when expiration time for reveals have been elapsed.
    event CampaignRevealingExpiration(uint256 target_campaign);

    /// Campaign revelation success and best solution has chosen
    event CampaignFinishedSuccessfully(
        uint256 target_campaign,
        uint256 task,
        uint256 random_seed,
        uint256 first_place_winner
    );

    // This events occurr when proposals revealing failed to offer a good solution for the campaign problem. Problem restarts again with a new number
    event CampaignResolutionFailed(uint256 target_campaign);

    // VRF components
    VRFCircleProblem private _circle_problem;
    VRFLeadboard private _leadboard;
    VRFCampaignTaskDB private _campaignDB;
    VRFIslandDB private _islandDB;
    VRFSignedRecordDB private _signed_recordDB;
    // VRF State manager
    VRFController private _controller;

    constructor(address initialOwner) Ownable(initialOwner)
    {
        // initialize parameters of daostate
        uint256 initial_seed = uint256( keccak256(abi.encodePacked(block.timestamp, _msgSender())) );
        
        _circle_problem = new VRFCircleProblem(initial_seed, initialOwner);
        _leadboard = new VRFLeadboard(initialOwner);
        _campaignDB = new VRFCampaignTaskDB(initialOwner);
        _islandDB = new VRFIslandDB(initialOwner);
        _signed_recordDB = new VRFSignedRecordDB(initialOwner);

        _controller = new VRFController(
            address(_islandDB),
            address(_campaignDB),
            address(_signed_recordDB), 
            address(_circle_problem),
            address(_leadboard),
            initialOwner
        );

        // connect contracts with controller
        address thisowner = owner();
        _controller.assignControllerRole(thisowner);

        _circle_problem.assignControllerRole(address(_controller));
        _circle_problem.assignControllerRole(thisowner);
        _leadboard.assignControllerRole(address(_controller));
        _leadboard.assignControllerRole(thisowner);
        _campaignDB.assignControllerRole(address(_controller));        
        _campaignDB.assignControllerRole(thisowner);
        _islandDB.assignControllerRole(address(_controller));
        _islandDB.assignControllerRole(thisowner);
        _signed_recordDB.assignControllerRole(address(_controller));
        _signed_recordDB.assignControllerRole(thisowner);

    }

    //////////////////////////////// DAO Configuration  //////////////////////////////////

    function get_params() external view returns (DVRANDAOParams memory) {
        return _controller.get_params();
    }

    function config_params(DVRANDAOParams calldata params)
        external
        onlyOwner
        nonReentrant
    {
        _controller.config_params(params);
    }

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

    function get_controller_contract() external view returns(IVRFController)
    {
        return _controller;
    }

    ////////////////////////////////______End DAO Config___//////////////////////////////////

    ////////////////////////////////     DAO Status      //////////////////////////////////
    
    function get_random_seed() external view returns (uint256) {
        return _controller.get_random_seed();
    }

    function accumulated_fee_bounty() external view returns (uint256) {
        return _controller.accumulated_fee_bounty();
    }

    function available_records() external view returns (uint256) 
    {
        return _signed_recordDB.available_records();
    }

    function phase_due_time() external view returns (uint) {
        return _controller.phase_due_time();
    }

    ////////////////////////////////____End DAO Status___//////////////////////////////////

    //////////////////////////////// Island Management//////////////////////////////////
    
    /**
     * This method only could be used by the parent contract
     */
    function register_island(uint256 islandID, address island_owner)
        external
        onlyOwner
    {
        _islandDB.register_island(islandID, island_owner);
    }

    /**
     * This method only could be used by the parent contract
     */
    function change_island_owner(
        uint256 islandID,
        address prev_island_owner,
        address new_island_owner
    ) external onlyOwner 
    {
        _islandDB.change_island_owner(
            islandID,
            prev_island_owner,
            new_island_owner
        );
    }

    /**
     * Withdraw payment to the caller of this functions, is
     */
    function payout_island_bounty(
        uint256 islandID,
        uint256 value
    ) external nonReentrant 
    {
        // Verify ownership
        address src_addr = _msgSender();

        if (
            src_addr == address(0) ||
            value == uint256(0) ||
            islandID == uint256(0)
        ) {
            revert Err_InvalidAddressParams();
        }

        // This method reverts if src_addr is not owner of the Island
        _islandDB.consume_island_bounty_payout(islandID, src_addr, value);

        // send money

        Address.sendValue(payable(src_addr), value);
    }

    /**
     * Punish island reputation and clears its bounty balance.
     * Reclaims the  last bounty balance, which will be accounted to accumulated bounty treasury 
     */
    function punish_island_reputation(uint256 islandID) external onlyOwner
    {
        _controller.punish_island_reputation(islandID);
    }

    ////////////////////////////////______Ending__Island____//////////////////////////////////

    //////////////////////////////// Campaign Management  ////////////////////////////////////    

    ////////////// Private           --------------------///

    /**
     * Reverts in case of error.
     * Returns true when finiishing gathering reveals. indicating special care of finishing task
     */
    function _check_phase_transition_event(eVRF_CAMPAIGN_STATUS prev_status)
        internal
        returns (bool)
    {
        eVRF_CAMPAIGN_STATUS new_status = _controller.get_campaign_phase();
        if (new_status == prev_status) return false;

        uint256 _current_campaignID = _controller.current_campaignID();

        if (prev_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_IDLE) 
        {
            assert(new_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM);
            emit CampaignSolvingInit(_current_campaignID);
        }
        else if (prev_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM)
        {
            assert(new_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_PROPOSALS);
            emit CampaignGatheringProposals(_current_campaignID);
        } 
        else if (prev_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_PROPOSALS) 
        {
            if (new_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_GATHERING_REVEALS) 
            {
                emit CampaignGatheringReveals(_current_campaignID);
            }
            else 
            {
                // must restart problem again
                assert(new_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM);
                emit CampaignAbsenteeism(_current_campaignID);
                emit CampaignSolvingInit(_current_campaignID);
            }
        } 
        else 
        {
            // gathering reveals must be handled with special care
            assert(new_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_CLOSING);
            return true;
        }

        return false;
    }

    function _finish_campaign() internal
    {
        uint256 _current_campaignID = _controller.current_campaignID();
        bool success = _controller.finalize_campaign();

        if (success == true) 
        {
            // get winner campaign
            VRFCampaignTask memory finished_campaign = _campaignDB.fetch_campaign_info(_current_campaignID);

            emit CampaignFinishedSuccessfully(
                _current_campaignID,
                finished_campaign.task_refID,
                finished_campaign.random_seed,
                finished_campaign.winner_record
            );

        }
        else 
        {
            emit CampaignResolutionFailed(_current_campaignID);
            emit CampaignSolvingInit(_current_campaignID);
        }

        uint32 proposalcount = _controller.proposal_count();
        if (proposalcount > 0) 
        {
            // The last campaign has leftovers, so punish them
            // This loop is under control, no more proposals up to max_campaign_proposals

            for (uint32 i = 0; i < proposalcount; i++) 
            {
                uint256 fault_recordID = _controller.get_proposal(i);
                emit ProposalFaulted(_current_campaignID, fault_recordID);
            }

            _controller.punish_leftovers();
        }
    }

    ////////////// Public RO Query   --------------------///

    /**
     * Tells If this DAO is enabled for campaigns
     */
    function is_enabled_for_campaigns() external view returns (bool) {
        return _controller.is_enabled_for_campaigns();
    }

    function get_campaign_phase() external view returns (eVRF_CAMPAIGN_STATUS) {
        return _controller.get_campaign_phase();
    }

    function can_start_campaign() external view returns (bool) {
        return _controller.can_start_campaign();
    }

    
    function current_campaignID() external view returns (uint256) {
        return _controller.current_campaignID();
    }

    
    ////////////// Public         --------------------///

    /*
     * This method should be used by the contract administrator, for enabling campaigns on this DAO.
     * @warning This is a trusted setup
     */
    function enable_first_campaign(uint256 master_seed)
        external
        onlyOwner
        nonReentrant
    {
        _controller.enable_first_campaign(master_seed);
    }

    /**
     * This method only could be used by parent contract.
     * Returns the consecutive index of the new campaign created.
     * It must pay a fee for creating a new task. This fee will be the bounty for the task.
     */
    function create_new_task(uint256 task_id)
        external
        payable
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        uint256 valuebounty = msg.value;

        if (valuebounty == uint256(0)) 
        {
            revert ErrVRF_CampaignWithoutBounty();
        }

        eVRF_CAMPAIGN_STATUS prev_status = _controller.get_campaign_phase();

        uint256 ret_campaign = _controller.insert_task(
            block.timestamp,
            task_id,
            valuebounty
        );

        emit NewCampaign(ret_campaign, task_id); // announce campaign

        // check status
        bool handle_closing = _check_phase_transition_event(prev_status);
        if (handle_closing == true) 
        {
            // close campaign
            _finish_campaign();
        }

        return ret_campaign;
    }

    ////////////////////////////////______Ending__Campaign___//////////////////////////////////

    //////////////////////////////// Record Management  ////////////////////////////////////
    
    function record_available_for_commitment(uint256 recordID)
        external view
        returns (bool)
    {
        return _controller.record_available_for_commitment(recordID);
    }

    ////////////// Public         --------------------///

    function _insert_record_paid(
        uint256 islandID,
        address src_addr,
        uint256 valuefee,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) internal nonReentrant returns (uint256) 
    {

        eVRF_CAMPAIGN_STATUS prev_status = _controller.get_campaign_phase();
        uint256 _current_campaignID = _controller.current_campaignID();
        
        // This method checks ownership of Island
        uint256 ret_record = _controller.insert_record_payable(
            block.timestamp,
            islandID,
            src_addr,
            valuefee,
            signature_r,
            signature_s,
            parity_v
        );

        emit NewRecordSigned(
            src_addr,
            islandID,
            ret_record,
            _current_campaignID
        ); // announce record

        // check status
        bool handle_closing = _check_phase_transition_event(prev_status);
        if (handle_closing == true) {
            // close campaign
            _finish_campaign();
        }

        return ret_record;
    }

    function insert_record_own(
        uint256 islandID,
        address src_addr,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external payable onlyOwner returns (uint256) 
    {
        // Verify ownership        
        uint256 valuefee = msg.value;
        return _insert_record_paid(islandID, src_addr, valuefee, signature_r, signature_s, parity_v);
    }

    function insert_record(
        uint256 islandID,        
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external payable returns (uint256) 
    {
        return _insert_record_paid(islandID, msg.sender, msg.value, signature_r, signature_s, parity_v);
    }

    /**
     * This method consumes the bonus of the Island
     */
    function _insert_record_using_bonus(
        uint256 islandID,
        address src_addr,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) internal nonReentrant returns (uint256) 
    {        
        eVRF_CAMPAIGN_STATUS prev_status = _controller.get_campaign_phase();
        
        uint256 _current_campaignID = _controller.current_campaignID();
     
        uint256 ret_record = _controller.insert_record_by_bonus(
            block.timestamp,
            islandID,
            src_addr,
            signature_r,
            signature_s,
            parity_v
        );

        emit NewRecordSigned(
            src_addr,
            islandID,
            ret_record,
            _current_campaignID
        ); // announce record

        // check status
        bool handle_closing = _check_phase_transition_event(prev_status);
        if (handle_closing == true) {
            // close campaign
            _finish_campaign();
        }

        return ret_record;
    }

    function insert_record_bonus_own(
        uint256 islandID,
        address src_addr,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external onlyOwner returns (uint256) 
    {        
        return _insert_record_using_bonus(islandID, src_addr, signature_r, signature_s, parity_v);
    }

    function insert_record_bonus(
        uint256 islandID,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external returns (uint256) 
    {
        return _insert_record_using_bonus(islandID, msg.sender, signature_r, signature_s, parity_v);
    }

    /**
     * This method only could be called when solving a problem
     */
    function _insert_record_solving_problem(
        uint256 islandID,
        address src_addr,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) internal nonReentrant returns (uint256) 
    {
        eVRF_CAMPAIGN_STATUS prev_status = _controller.get_campaign_phase();

        uint256 ret_record = _controller.insert_record_problem_working(
            block.timestamp,
            islandID,
            src_addr,
            signature_r,
            signature_s,
            parity_v
        );

        emit NewRecordSigned(
            src_addr,
            islandID,
            ret_record,
            _controller.current_campaignID()
        ); // announce record

        ///This never leads to finalization events
        _check_phase_transition_event(prev_status);

        return ret_record;
    }

    /**
     * This method only could be called when solving a problem
     */
    function insert_record_solving_own(
        uint256 islandID,
        address src_addr,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external onlyOwner returns (uint256) 
    {
        return _insert_record_solving_problem(islandID, src_addr, signature_r, signature_s, parity_v);
    }

    function insert_record_solving(
        uint256 islandID,
        bytes32 signature_r,
        bytes32 signature_s,
        uint8 parity_v
    ) external returns (uint256) 
    {
        return _insert_record_solving_problem(islandID, msg.sender, signature_r, signature_s, parity_v);
    }


    /// Signed record proposals
    function _commit_proposal(uint256 recordID, address src_addr) internal nonReentrant 
    {
        eVRF_CAMPAIGN_STATUS prev_status = _controller.get_campaign_phase();
        uint256 _current_campaignID = _controller.current_campaignID();        

        uint32 proposal_index = _controller.commit_proposal(src_addr, recordID, block.timestamp);

        emit ProposalComitted(_current_campaignID, recordID, proposal_index);

        // check status
        _check_phase_transition_event(prev_status);
    }

    function commit_proposal_own(uint256 recordID, address src_addr) external onlyOwner
    {
        _commit_proposal(recordID, src_addr);
    }


    function commit_proposal(uint256 recordID) external
    {
        _commit_proposal(recordID, msg.sender);
    } 


    /**
     * If failed to reveal solution returns negative (-1).
     * Otherwise return the leadboard score: 1 - First. 2 - Second, 3 - third.
     */
    function _reveal_proposal(
        uint256 recordID,
        address src_addr,
        int64 cx,
        int64 cy,
        int64 radius
    ) internal nonReentrant returns (int32)
    {
        eVRF_CAMPAIGN_STATUS prev_status = _controller.get_campaign_phase();
        uint256 _current_campaignID = _controller.current_campaignID();        

        int32 score = 0;
        bool isvalid = _controller.validate_proposal_integrity(
            recordID,
            src_addr,
            cx,
            cy,
            radius
        );
        
        if (isvalid == false) {
            _controller.punish_failed_reveal(recordID);
            score = -1;
        }
        else 
        {
            // commit reveal
            score = _controller.reveal_proposal(recordID, src_addr, cx, cy, radius);
        }

        // raise event
        if (score < 0) 
        {
            emit ProposalRevealFailed(_current_campaignID, recordID);
        }
        else 
        {
            emit ProposalRevealed(_current_campaignID, recordID);
        }

        // check campaign phase
        _controller.check_campaign_phase(block.timestamp);

        // check status
        bool handle_closing = _check_phase_transition_event(prev_status);
        if (handle_closing == true) 
        {
            // close campaign
            _finish_campaign();
        }

        return score;
    }

    /**
     * If failed to reveal solution returns negative (-1).
     * Otherwise return the leadboard score: 1 - First. 2 - Second, 3 - third.
     */
    function reveal_proposal_own(
        uint256 recordID,
        address src_addr,
        int64 cx,
        int64 cy,
        int64 radius
    ) external onlyOwner returns (int32)
    {
        return _reveal_proposal(recordID, src_addr, cx, cy, radius);
    }

    function reveal_proposal(
        uint256 recordID,
        int64 cx,
        int64 cy,
        int64 radius
    ) external returns (int32)
    {
        return _reveal_proposal(recordID, msg.sender, cx, cy, radius);
    }

    ////////////////////////////////______Ending__Proposal___//////////////////////////////////

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
        external view
        returns (uint256, uint32, uint256)
    {
        return _controller.suggested_record_indexparams(island_tokenID);
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
    ) external view returns (bytes32) 
    {
        return  _controller.digital_record_signature_helper(islandID, cx, cy, radius);
    }

    function is_valid_record_signature(
        uint256 recordID,
        address pk_owner,
        int64 cx,
        int64 cy,
        int64 radius
    ) external view returns (bool) 
    {
        return _signed_recordDB.is_valid_record_signature(
                recordID,
                pk_owner,
                cx,
                cy,
                radius
            );
    }

    ////////////////////////////////______Ending__Helpers_//////////////////////////////////
}
