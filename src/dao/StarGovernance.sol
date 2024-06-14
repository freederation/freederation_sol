//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;


import "./StarProjectDB.sol";

error ErrGov_IslandAlreadyVote(uint256 islandID, uint256 sessionID);

error ErrGov_VotingSessionExpired(uint256 sessionID);

error ErrGov_InvalidIsland(uint256 islandID);

error ErrGov_InvalidSession(uint256 sessionID);

error ErrGov_IslandDoesNotBelongToProjectSession(uint256 islandID, uint256 sessionID, uint64 projectID);

error ErrGov_NotAuthorizedToManipulateStar(uint64 projectID, address operator);

error ErrGov_StarLimitedByGovernance(uint64 projectID);

error ErrGov_StarNeedsGovernance(uint64 projectID);

error ErrGov_StarHasNotEnoughFundsInTreasury(uint64 projectID, uint256 amount);

error ErrGov_IslandHasNoPower(uint256 islandID);

error ErrGov_InvalidParams();

error ErrGov_TaskCannotGetPaid(uint256 taskID);

error ErrGov_TaskWrongReceiver(uint256 taskID, address receiver);


enum eDeliberationKind
{
    PRICING_DELIBERATION,
    QUORUM_DELIBERATION,
    TASK_APROVAL_DELIBERATION,
    TASK_EVAL_DELIBERATION,
    ISLAND_CENSORSHIP_DELIBERATION,
    STAR_SPONSORSHIP_DELIBERATION
}

enum eVotingState
{
    CASE_OPEN,
    CASE_APPROVED,
    CASE_DENIED
}

enum eMODERATION_FAULT
{
    COPYRIGHT_INFRIGEMENT,
    FRAUD,
    HARMFUL_CONTENT,
    SECURITY_ISSUES
}

enum eStarTaskFulfillment
{
    PROPOSED,
    RESERVED, // Budget assigned
    FULFILLED_PENDANT,/// Waiting for payment
    FULFILLED_CHARGED,/// Already paid
    CANCELLED /// Cancelled and refunded
}


struct StarGovernanceQuorum
{
    /**
     * Percentaje of members required for quorum, when deciding the budget assignation.
     * If 0, and min count is also 0, then no consensus is required.
     */
    uint256 budget_quorum_rate;
    
    /**
     * Minimum count of voters required for budget assignation.
     * If 0, then budget_quorum_rate will be used
     */
    uint budget_quorum_min_count;

    /**
     * Percentaje of members required for quorum, when deciding banning Islands due to content moderation infrigement.
     * If 0, and min count is also 0, then no consensus is required.
     */
    uint256 censorship_quorum_rate;
    
    /**
     * Minimum count of voters required for banning islands because of content infrigement.
     * If 0, then budget_quorum_rate will be used.
     */
    uint censorship_quorum_min_count;

    /**
     * Percentaje of members required for quorum, when proposing changes to Star project parameters.
     * If 0, and min count is also 0, then no consensus is required.
     */
    uint256 project_changing_quorum_rate;
    
    /**
     * Minimum count of voters required for changing Star project parameters.
     * If 0, then budget_quorum_rate will be used.
     */
    uint project_changing_quorum_min_count;
    
}

struct IslandGovernanceEntry
{
    /// If voting_weight == 0 and projectID == 0, means this entry is no longer valid
    uint64 projectID;    
    uint32 voting_weight;
}


struct StarVotingSession
{
    uint64 star_projectID;
    eDeliberationKind kind;
    eVotingState state;
    /**
     * The task proposal, or the Island to be banned.
     */
    uint256 subject;
    uint start_event;
    uint deadline_duration;
    uint voting_yay;
    uint voting_nay;
}

struct StarBudget
{
    /**
     * Current Star Treasure Balance, which hasn't been liquidate yet.
     * 
     */
    uint256 star_treasury_vault;
    
    /**
     * Ammount of money required by approved tasks
     */
    uint256 required_budget;


    /**
     * Accumulated project payout to project maintainers. Which has been substracted from  star_treasury_vault
     */
    uint256 project_payout_amount;

    

    /**
     * The index in the backlog of tasks to be financed.
     * 1-based. 0 Means no tasks currently loaded.
     * See _star_approved_tasks member. 
     */
    uint64 approved_backlog_index;
}

struct StarGovtStatus
{    
    uint256 num_islands;
    uint256 pricing_sessionID;
    uint256 quorum_sessionID;
}


struct StarTaskInfo
{
    uint64 star_projectID;
    uint256 required_budget;
    /// Receiver that will reclaim the payment for fulfilled task
    address receiver;    
    uint publication_time;
    uint approval_time;
    uint deadline_duration;
    uint256 voting_session;
    eStarTaskFulfillment fulfillment;
    // The IPFS hash representing the JSON object storing the details of the issue.
    string detail; 
}

struct StarTaskProposal
{
    uint64 star_projectID;
    uint256 required_budget;
    uint deadline_duration;
    /// Receiver that could reclaim the payment for fulfilled task
    address receiver;
    // The IPFS hash representing the JSON object storing the details of the issue.
    string detail; 
}


struct FREE_GovernanceTimeParams
{
    uint budget_quorum_expiration_time;
    uint project_quorum_expiration_time;
    uint censorship_quorum_expiration_time;
}

/**
 * In FREEDERATION, Only through Meta Islands DAO members could pariticpate in governance decisions.
 * 
 */
contract StarGovernance is FREE_Controllable
{    
    using FREE_BasicOwnershipUtil for FREE_BasicOwnership;

    // events
    event NewTaskProposal(uint256 taskID, uint64 projectID, uint256 voting_session);

    event NewVotingSession(uint256 sessionID, uint64 projectID, eDeliberationKind kind);

    event VotingFinished(uint256 sessionID, eDeliberationKind kind, bool approval);

    event VoteSubmission(uint256 sessionID, uint256 islandID);

    event TaskProposalCancelled(uint256 taskID, uint64 projectID, uint256 voting_session);

    event TaskFundingReserved(uint256 taskID, uint64 projectID, uint256 funds_ammount);

    event TaskFulfilled(uint256 taskID, uint64 projectID);

    event TaskFulfilledCharged(uint256 taskID, uint64 projectID, address receiver, uint256 funds_ammount);

    
    
    /// Project contribution
    event StarProjectContribution(uint64 projectID, uint256 star_treasury_vault, uint256 required_budget);

    event StarProjectPayout(uint64 projectID, uint256 star_treasury_balance, uint256 amount, address receiver);

    /////////////////////////////////////////////////        

    FREE_GovernanceTimeParams private _quorum_expiration_time;

    mapping(uint64 => StarGovernanceQuorum) private _star_quorum_governance;

    mapping(uint64 => uint256) private _star_islands_count;    

    // Star budget management
    mapping(uint64 => StarBudget) private _star_budget;
        
    /// Islands that could participate in the governance with voting power
    mapping(uint256 => IslandGovernanceEntry) private _island_entries;

    mapping(uint256 => StarTaskInfo) private _star_tasks_registry;

    mapping(uint256 => StarVotingSession) private _star_session_registry;


    /**
     * Maps the hash of the Island voting related to a session (hash160(islandID, projectID, sessionID)),
     * Handles hash collisions on a secondary list which contains the sessionID
     */
    FREE_BasicOwnership private _island_vote_registry;

    /**
     * Proposals to be approved in voting sessions.
     * Contains the ID of the voting sessions
     */
    FREE_BasicOwnership private _star_voting_proposals;

    /**
     * Approved tasks with budget already reserved to them
     */
    FREE_BasicOwnership private _star_approved_tasks;

    uint256 _new_taskID;
    uint256 _new_sessionID;

    constructor(address initialOwner) FREE_Controllable(initialOwner)
    {
        _new_taskID = FREE_DEFAULT_TOKEN_ID;
        _new_sessionID = FREE_DEFAULT_TOKEN_ID;
        _quorum_expiration_time.budget_quorum_expiration_time = 1 weeks;
        _quorum_expiration_time.project_quorum_expiration_time = 1 weeks;
        _quorum_expiration_time.censorship_quorum_expiration_time = 1 weeks;
    }


    /////////////////////// Project Info /////////////////////////////////////
    
    function _initialize_project(uint64 projectID) internal
    {       
        _star_quorum_governance[projectID] = StarGovernanceQuorum({
            budget_quorum_rate:0,
            budget_quorum_min_count:0,
            censorship_quorum_rate:0,
            censorship_quorum_min_count:0,
            project_changing_quorum_rate:0,
            project_changing_quorum_min_count:0
        });

        _star_islands_count[projectID] = 0;

        _star_budget[projectID] = StarBudget({
            star_treasury_vault:0,
            required_budget:0,
            project_payout_amount:0,
            approved_backlog_index:0
        });
    }

    function register_star_project(uint64 star_projectID) onlyOwner external
    {
        _initialize_project(star_projectID);
    }


    function project_quorum_info(uint64 star_projectID) public view returns(StarGovernanceQuorum memory)
    {
        return _star_quorum_governance[star_projectID];
    }

    function project_budget(uint64 star_projectID) public view returns(StarBudget memory)
    {
        return _star_budget[star_projectID];
    }


    function configure_governance_quorum(
        uint64 star_projectID,
        StarGovernanceQuorum memory govinfo
    ) external onlyOwner
    {
        StarGovernanceQuorum storage quorum = _star_quorum_governance[star_projectID];

        if(quorum.project_changing_quorum_rate != 0 || quorum.project_changing_quorum_min_count != 0)
        {
            revert ErrGov_StarLimitedByGovernance(star_projectID);
        }

        _star_quorum_governance[star_projectID] = govinfo;
    }

    /////////////////////// End Project Info /////////////////////////////////////
    
    /////////////// Island Participants ////////////////

    function register_island(uint64 star_projectID, uint256 islandID) external onlyOwner
    {
        _island_entries[islandID] = IslandGovernanceEntry({
            projectID:star_projectID,
            voting_weight:1
        });


        _star_islands_count[star_projectID]++;
    }

    function get_island_governance_info(uint256 islandID) public view returns(IslandGovernanceEntry memory)
    {
        return _island_entries[islandID];
    }

    function is_valid_island(uint256 islandID) public view returns(bool)
    {
        return _island_entries[islandID].projectID != 0;
    }

    function grant_power(uint256 islandID, uint256 island_delegateID, uint32 weight) external onlyOwner
    {
        if(islandID == 0 ||
           island_delegateID == 0)
        {
            revert ErrGov_InvalidIsland(islandID);
        }

        IslandGovernanceEntry storage src_entry = _island_entries[islandID];

        if(src_entry.projectID == 0)
        {
            revert ErrGov_InvalidIsland(islandID);
        }

        if(src_entry.voting_weight == 0)
        {
            revert ErrGov_IslandHasNoPower(islandID);
        }

        IslandGovernanceEntry storage dst_entry = _island_entries[island_delegateID];
        if(dst_entry.projectID == 0)
        {
            revert ErrGov_InvalidIsland(island_delegateID);
        }

        uint32 transfer_ammount = (src_entry.voting_weight < weight || weight == 0) ? src_entry.voting_weight: weight;
        src_entry.voting_weight -= transfer_ammount;
        dst_entry.voting_weight += transfer_ammount;
    }

    function __destroy_island_entry(uint256 islandID) internal
    {
        _island_entries[islandID] = IslandGovernanceEntry({
            projectID:0, // 0 project means not existing island.
            voting_weight:0
        });
    }

    function destroy_island_entry(uint256 islandID) external onlyOwner
    {
        __destroy_island_entry(islandID);
    }

    //////////// Voting Session Info //////////////////
    
    function voting_session_info(uint256 sessionID) public view returns(StarVotingSession memory)
    {
        return _star_session_registry[sessionID];
    }

    function voting_session_project(uint256 sessionID) public view returns(uint64)
    {
        return _star_session_registry[sessionID].star_projectID;
    }

    function voting_session_subject(uint256 sessionID) public view returns(uint256)
    {
        return _star_session_registry[sessionID].subject;
    }

    function star_voting_proposal_count(uint64 star_projectID) public view returns(uint64)
    {
        return _star_voting_proposals.list_count(star_projectID);
    }

    function get_voting_proposal_sessionID(uint64 star_projectID, uint64 index) public view returns(uint256)
    {
        return _star_voting_proposals.get(star_projectID, index);
    }

    function calc_voting_hash(uint256 islandID, uint256 sessionID) public view returns(uint256)
    {
        uint64 projectID = _island_entries[islandID].projectID;
        bytes20 hashvote = ripemd160(abi.encodePacked(islandID, projectID, sessionID));
        return uint256(uint160(hashvote));
    }

    function has_already_vote(uint64 islandID, uint256 sessionID) public view returns(bool)
    {
        uint256 hashvote = calc_voting_hash(islandID, sessionID);
        // look for entries
        uint64 vcount = _island_vote_registry.list_count(hashvote);
        if(vcount == 0) return false;
        
        // look for collisions
        for(uint64 vi = 0; vi < vcount; vi++)
        {
            uint256 vele = _island_vote_registry.get(hashvote, vi);
            if(vele == sessionID) return true;
        }

        return false;
    }


    function _register_voting_session(
        uint64 star_projectID,
        eDeliberationKind kind,
        uint deadline_duration,
        uint256 subject) internal returns(uint256)
    {
        _new_sessionID++;
        _star_session_registry[_new_sessionID] = StarVotingSession({
            star_projectID:star_projectID,
            kind: kind,
            state:eVotingState.CASE_OPEN,
            subject: subject,
            start_event: block.timestamp,
            deadline_duration: deadline_duration,
            voting_yay:0,
            voting_nay:0
        });

        // register proposal on project
        _star_voting_proposals.insert(uint256(star_projectID), _new_sessionID);

        // emit event
        emit NewVotingSession(_new_sessionID, star_projectID, kind);

        return _new_sessionID;
    }

    /**
     * External version for registering voting session.
     * Used by StarGovController
     */
    function register_voting_session(
        uint64 star_projectID,
        eDeliberationKind kind,
        uint256 subject
    ) external onlyOwner returns(uint256)
    {
        StarGovernanceQuorum storage quorum = _star_quorum_governance[star_projectID];

        uint duration = 0;
        if( kind == eDeliberationKind.PRICING_DELIBERATION ||
            kind == eDeliberationKind.QUORUM_DELIBERATION ||
            kind == eDeliberationKind.STAR_SPONSORSHIP_DELIBERATION )
        {
            if(quorum.project_changing_quorum_rate == 0 && quorum.project_changing_quorum_min_count == 0)
            {
                revert ErrGov_StarNeedsGovernance(star_projectID);
            }
        
            duration = _quorum_expiration_time.project_quorum_expiration_time;
        }
        else if(kind == eDeliberationKind.ISLAND_CENSORSHIP_DELIBERATION)
        {
            if(quorum.censorship_quorum_rate == 0 && quorum.censorship_quorum_min_count == 0)
            {
                revert ErrGov_StarNeedsGovernance(star_projectID);
            }

            duration = _quorum_expiration_time.censorship_quorum_expiration_time;
        }
        else
        {
            revert ErrGov_InvalidParams();
        }

        return _register_voting_session(star_projectID, kind, duration, subject);
    }
    
    //////////////////////// Task Backlog funding ///////////////////////////////

    /**
     * This method reserves budget on requiring tasks, and creates a new voting session
     * for evaluating their performance
     */
    function _update_funding_backlog(uint64 projectID) internal
    {        
        StarBudget storage budget = _star_budget[projectID];
        if(budget.required_budget == uint256(0) || budget.star_treasury_vault == uint256(0))
        {
            return;
        }

        uint64 tasks_count = _star_approved_tasks.list_count(projectID);
        uint64 next_index = budget.approved_backlog_index;

        // advance backlog index while distributing the treasure vault
        while(next_index < tasks_count)
        {
            // get task to be financed
            uint256 taskID = _star_approved_tasks.get(uint256(projectID), next_index);            
            StarTaskInfo storage taskinfo = _star_tasks_registry[taskID];

            assert(taskinfo.fulfillment == eStarTaskFulfillment.PROPOSED);

            if(budget.star_treasury_vault >= taskinfo.required_budget)
            {
                // tasks financed successfully
                budget.star_treasury_vault -= taskinfo.required_budget;
                budget.required_budget -= taskinfo.required_budget;

                taskinfo.fulfillment = eStarTaskFulfillment.RESERVED;

                taskinfo.approval_time = block.timestamp;

                // create a new case for the evaluation for the task, with the specified deadline
                taskinfo.voting_session = _register_voting_session(
                    projectID,
                    eDeliberationKind.TASK_EVAL_DELIBERATION,
                    taskinfo.deadline_duration,
                    taskID
                );
                
                // emit event of task reserved
                emit TaskFundingReserved(taskID, projectID, taskinfo.required_budget);

                next_index++;                
            }
            else
            {
                // break loop
                break;
            }
        }

        budget.approved_backlog_index = next_index;// update index
    }

    function _move_task_to_backlog(uint64 projectID, uint256 taskID) internal
    {
        StarTaskInfo storage taskinfo = _star_tasks_registry[taskID];
        assert(taskinfo.star_projectID == projectID);
        assert(taskinfo.fulfillment ==  eStarTaskFulfillment.PROPOSED);

        StarBudget storage budget = _star_budget[projectID];
        budget.required_budget += taskinfo.required_budget;// account the required budget

        _star_approved_tasks.insert(uint256(projectID), taskID); // project backlog needs to be updated

        taskinfo.approval_time = block.timestamp;
    }

    function get_task_info(uint256 taskID) public view returns(StarTaskInfo memory)
    {
        return _star_tasks_registry[taskID];
    }

    function star_approved_tasks_count(uint64 projectID) public view returns(uint64)
    {
        return _star_approved_tasks.list_count(uint256(projectID));
    }

    function get_approved_taskID(uint64 projectID, uint64 index) public view returns(uint256)
    {
        return _star_approved_tasks.get(uint256(projectID), index);
    }

    /**
     * Returns the voting session.
     */
    function make_task_proposal(
        StarTaskProposal memory proposal
    ) external onlyOwner returns(uint256)
    {
        StarGovernanceQuorum storage quorum = _star_quorum_governance[proposal.star_projectID];

        if(quorum.budget_quorum_rate == 0 && quorum.budget_quorum_min_count == 0)
        {
            revert ErrGov_StarNeedsGovernance(proposal.star_projectID);
        }

        if(proposal.required_budget == 0 ||
           proposal.deadline_duration == 0 ||
           proposal.receiver == address(0) )
        {
            revert ErrGov_InvalidParams();
        }

        _new_taskID++;

        uint256 sessionID = _register_voting_session(
            proposal.star_projectID,
            eDeliberationKind.TASK_APROVAL_DELIBERATION,
            _quorum_expiration_time.budget_quorum_expiration_time,
            _new_taskID
        );

        _star_tasks_registry[_new_taskID] = StarTaskInfo({
            star_projectID: proposal.star_projectID,
            required_budget : proposal.required_budget,
            receiver:proposal.receiver,
            publication_time : block.timestamp,
            approval_time: 0,
            deadline_duration: proposal.deadline_duration,
            voting_session: sessionID,
            fulfillment: eStarTaskFulfillment.PROPOSED,
            detail: proposal.detail
        });

        emit NewTaskProposal(_new_taskID, proposal.star_projectID, sessionID);

        return sessionID;
    }

    function payout_fulfilled_task(
        uint256 taskID,
        address receiver
    ) external onlyOwner returns(address, uint256)
    {
        StarTaskInfo storage taskinfo = _star_tasks_registry[taskID];
        if(taskinfo.fulfillment != eStarTaskFulfillment.FULFILLED_PENDANT)
        {
            revert ErrGov_TaskCannotGetPaid(taskID);
        }

        if(taskinfo.receiver != receiver || receiver == address(0))
        {
            revert ErrGov_TaskWrongReceiver(taskID, receiver);
        }

        taskinfo.fulfillment = eStarTaskFulfillment.FULFILLED_CHARGED;
        
        return (receiver, taskinfo.required_budget);    
    }

    
    
    //////////// Voting Session Quorum Execution ///////////
        
    function _determine_quorum(
        uint voting_yay,
        uint voting_nay,
        uint island_population,
        uint quorum_rate,
        uint quorum_mincount,
        bool deadline_reached
    ) internal pure returns(eVotingState)
    {
        uint total_votes = voting_yay + voting_nay;

        eVotingState vcount0 = voting_yay > voting_nay ?  eVotingState.CASE_APPROVED : eVotingState.CASE_DENIED;
        
        // Reached the total of members, no need to measure
        if(total_votes >= island_population)
        {            
            return vcount0;
        }
        else if(deadline_reached == false)
        {
            /// wait for completion
            return eVotingState.CASE_OPEN;
        }

        // deadline reached, assume that quorum need to be determined
        if(quorum_rate == 0)
        {
            if(quorum_mincount == 0)
            {
                // it's irrelevant, no quorum stablished
                return eVotingState.CASE_APPROVED;
            }
            else if(total_votes < quorum_mincount)
            {
                // insufficient votes
                return eVotingState.CASE_DENIED;
            }

            // quorum reached 
            return vcount0;
        }

        uint minimum_portion_count = FREE_PERCENTAJE(island_population, quorum_rate);

        if(total_votes >= minimum_portion_count)
        {
            // quorum reached 
            return vcount0;
        }

        if(quorum_mincount > total_votes || quorum_mincount == 0)
        {
            // no quorum reached
            return eVotingState.CASE_DENIED;
        }

        // quorum reached: quorum_mincount <= total_votes && quorum_mincount > 0
        return vcount0;
    }    

    function _execute_quorum(uint256 sessionID, bool deadline_reached) internal returns(eVotingState, eDeliberationKind)
    {
        StarVotingSession storage voting_session = _star_session_registry[sessionID];

        assert(voting_session.state == eVotingState.CASE_OPEN);

        uint64 projectID = voting_session.star_projectID;

        uint256 num_islands = _star_islands_count[projectID];
        StarGovernanceQuorum storage  gov_quorum = _star_quorum_governance[projectID];

        eDeliberationKind vkind = voting_session.kind;

        if(vkind == eDeliberationKind.PRICING_DELIBERATION ||           
           vkind == eDeliberationKind.STAR_SPONSORSHIP_DELIBERATION ||
           vkind == eDeliberationKind.QUORUM_DELIBERATION)
        {
            // determine deliberation
            eVotingState vstate0 = _determine_quorum(
                voting_session.voting_yay,
                voting_session.voting_nay,
                num_islands,
                gov_quorum.project_changing_quorum_rate,
                gov_quorum.project_changing_quorum_min_count,
                deadline_reached
            );

            voting_session.state = vstate0;

            if(vstate0 != eVotingState.CASE_OPEN)
            {
                emit VotingFinished(sessionID, vkind, vstate0 == eVotingState.CASE_APPROVED);
            }

            return (vstate0, vkind);
        }
        else if(vkind == eDeliberationKind.ISLAND_CENSORSHIP_DELIBERATION)
        {
            eVotingState vstate1 = _determine_quorum(
                voting_session.voting_yay,
                voting_session.voting_nay,
                num_islands,
                gov_quorum.censorship_quorum_rate,
                gov_quorum.censorship_quorum_min_count,
                deadline_reached
            );

            voting_session.state = vstate1;

            if(vstate1 != eVotingState.CASE_OPEN)
            {
                emit VotingFinished(sessionID, vkind, vstate1 == eVotingState.CASE_APPROVED);
            }

            if(vstate1 == eVotingState.CASE_APPROVED)
            {
                __destroy_island_entry(voting_session.subject);
            }

            return (vstate1, vkind);
        }

        // budget assignation
        eVotingState vstate2 = _determine_quorum(
            voting_session.voting_yay,
            voting_session.voting_nay,
            num_islands,
            gov_quorum.budget_quorum_rate,
            gov_quorum.budget_quorum_min_count,
            deadline_reached
        );

        if(vstate2 == eVotingState.CASE_OPEN)
        {
            // not ready yet
            return (eVotingState.CASE_OPEN, vkind);
        }

        voting_session.state = vstate2;

        if(vstate2 != eVotingState.CASE_OPEN)
        {
            emit VotingFinished(sessionID, vkind, vstate2 == eVotingState.CASE_APPROVED);
        }
        
        uint256 taskID = voting_session.subject;
        assert(taskID > FREE_DEFAULT_TOKEN_ID && taskID <= _new_taskID);
        StarTaskInfo storage taskinfo = _star_tasks_registry[taskID];

        // check approval or evaluation
        if(vkind == eDeliberationKind.TASK_APROVAL_DELIBERATION)
        {
            if(vstate2 == eVotingState.CASE_DENIED)
            {
                // not approval, reject case                
                taskinfo.fulfillment = eStarTaskFulfillment.CANCELLED;

                emit TaskProposalCancelled(taskID, projectID, sessionID);

                return (eVotingState.CASE_DENIED, vkind);
            }

            // move the task to the approval backlog
            _move_task_to_backlog(projectID, taskID);

            _update_funding_backlog(projectID);

            return (eVotingState.CASE_APPROVED, vkind);
        }

        assert(vkind == eDeliberationKind.TASK_EVAL_DELIBERATION);

        // the task should be reserved
        assert(taskinfo.fulfillment == eStarTaskFulfillment.RESERVED);

        StarBudget storage budget = _star_budget[projectID];

        if(vstate2 == eVotingState.CASE_DENIED)
        {
            // restore funds and cancel the task            
            budget.star_treasury_vault += taskinfo.required_budget;
            taskinfo.fulfillment = eStarTaskFulfillment.CANCELLED;

            emit TaskProposalCancelled(taskID, projectID, sessionID);

            _update_funding_backlog(projectID);
        }
        else
        {
            budget.project_payout_amount += taskinfo.required_budget;
            taskinfo.fulfillment = eStarTaskFulfillment.FULFILLED_PENDANT;

            emit TaskFulfilled(taskID, projectID);
        }

        return (vstate2, vkind);
    }

    /**
     * Reverts if islandID is not allowed to vote on the session.
     * Returns the new state of the session.
     */
    function commit_vote(uint256 islandID, uint256 sessionID, bool approval) external onlyOwner returns(eVotingState, eDeliberationKind)
    {
        if(sessionID > _new_sessionID || sessionID <= FREE_DEFAULT_TOKEN_ID)
        {
            revert ErrGov_InvalidSession(sessionID);
        }

        StarVotingSession storage voting_session = _star_session_registry[sessionID];
        if(voting_session.state != eVotingState.CASE_OPEN)
        {
            revert ErrGov_VotingSessionExpired(sessionID);
        }
        
        // check if island is allowed to vote
        IslandGovernanceEntry storage island_entry = _island_entries[islandID];
        if(island_entry.projectID == 0 || island_entry.voting_weight == 0)
        {
            revert ErrGov_InvalidIsland(islandID);
        }

        if(voting_session.star_projectID != island_entry.projectID)
        {
            revert ErrGov_IslandDoesNotBelongToProjectSession(islandID, sessionID, voting_session.star_projectID);
        }

        uint256 hashvote = calc_voting_hash(islandID, sessionID);
        // look for entries
        uint64 vcount = _island_vote_registry.list_count(hashvote);
        if(vcount > 0)
        {
            // look for collisions
            for(uint64 vi = 0; vi < vcount; vi++)
            {
                uint256 vele = _island_vote_registry.get(hashvote, vi);
                if(vele == sessionID)
                {
                    revert ErrGov_IslandAlreadyVote(islandID, sessionID);
                }
            }
        }
        
        // mark vote
        _island_vote_registry.insert(hashvote, sessionID);
        
        // count
        if(approval)
        {
            voting_session.voting_yay += island_entry.voting_weight;
        }
        else
        {
            voting_session.voting_nay += island_entry.voting_weight;
        }

        // notify vote submission
        emit VoteSubmission(sessionID, islandID);

        uint deadline = voting_session.start_event + voting_session.deadline_duration;
        return _execute_quorum(sessionID, block.timestamp >= deadline);
    }

    //////////////////////////// Star Funding Budget //////////////////////////
    
    /**
     * Returns resulting budget
     */
    function contribute_star_treasury(
        uint64 star_projectID,
        uint256 payment
    ) external onlyOwner returns(uint256)
    {
        StarBudget storage budget = _star_budget[star_projectID];
        budget.star_treasury_vault += payment;

        _update_funding_backlog(star_projectID);

        emit StarProjectContribution(
            star_projectID, 
            budget.star_treasury_vault,
            budget.required_budget
        );

        return budget.star_treasury_vault;
    }


    /**
    * Reverts on error or if ammount exceeded the available funds in treasure.
    * Emits 
    */
    function extract_treasure_funds(
        uint64 star_projectID,
        uint256 ammount,
        address receiver
    ) external onlyOwner
    { 
        StarGovernanceQuorum storage quorum = _star_quorum_governance[star_projectID];

        if(quorum.budget_quorum_rate != 0 || quorum.budget_quorum_min_count != 0)
        {
            revert ErrGov_StarLimitedByGovernance(star_projectID);
        }

        StarBudget storage budget = _star_budget[star_projectID];
        if(budget.star_treasury_vault < ammount)
        {
            revert ErrGov_StarHasNotEnoughFundsInTreasury(star_projectID, ammount);
        }

        budget.star_treasury_vault -= ammount;
        budget.project_payout_amount += ammount;

        emit StarProjectPayout(
            star_projectID,
            budget.star_treasury_vault,
            ammount,
            receiver
        );
        
    }

    

}
