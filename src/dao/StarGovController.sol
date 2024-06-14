//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./StarGovernance.sol";
import "../util/FREEAssetOwnership.sol";

error ErrDAO_NotAuthorizedToStar(uint64 star_projectID, address operator);

struct StarIslandCensorship
{
    uint64 star_projectID;
    uint256 islandID;
    eMODERATION_FAULT fault_type;
    string alleged_fault_data;// The IPFS hash representing the JSON object storing the details of the issue.
}


contract StarGovController is FREE_Controllable
{
    using FREE_AssetOwnershipUtil for FREE_AssetOwnership;

    event StarOwnershipTransferred(uint64 projectID, address new_owner);

    event StarMaintainerAssigned(uint64 projectID, address maintainer, address authorizer);

    event StarSponsorship(uint64 sponsor_projectID, uint64 promoted_projectID);


    ///  ********** *****Extension Contracts ************ *********** ///
    StarGovernance private _star_governance_contract;
    StarProjectDB private _star_db_contract;

    ///  ********** *********Extension Data for Contracts ********* ///

    /**
     * Quorum proposal assignment mapped to the Star voting session
     */
    mapping(uint256 => StarGovernanceQuorum) private _star_quorum_proposal;

    /**
     * Pricing proposal assignment mapped to the Star voting session
     */
    mapping(uint256 => StarPricing) private _star_pricing_proposal;


    /**
     * Censorship proposal mapped to the Star voting session
     */
    mapping(uint256 => StarIslandCensorship) private _star_island_censorship_proposal;

    ///  ********** **************************** **************** ///

    // Stars Ownership to addresses    
    FREE_AssetOwnership private _star_ownership_inventory;

    /**
     * Star maintainers could submit tasks proposals.
     * The mapping key corresponds to the combination of the projectID (uint64) and the address of the maintainer (uint160).
     * The result should match the address of the maintainer.
     */
    mapping(uint256 => address) private _star_maintainers;

    uint32 private _minimum_sponsorship_prestige_level;
    

    constructor(address gov_contract_addr, 
                address star_db_addr,
                uint32 minimum_sponsorship_prestige_level,
                address initialOwner)
    FREE_Controllable(initialOwner)
    {
        _minimum_sponsorship_prestige_level = minimum_sponsorship_prestige_level;
        _star_governance_contract = StarGovernance(gov_contract_addr);
        _star_db_contract = StarProjectDB(star_db_addr);
    }

    function get_minimum_sponsorship_prestige_level() public view returns(uint32)
    {
        return _minimum_sponsorship_prestige_level;
    }

    function set_minimum_sponsorship_prestige_level(uint32 level) external onlyOwner
    {
        _minimum_sponsorship_prestige_level = level;
    }

    ////// Star governance functions /////

    modifier validStarOwner(uint64 _projectID) {
        _checkValidStarOwner(_projectID, msg.sender);
        _;
    }

    function _checkValidStarOwner(uint64 _projectID, address _owner_addr) internal view
    {
        if(is_owner(_projectID, _owner_addr) == false)
        {
            revert ErrGov_NotAuthorizedToManipulateStar(_projectID, _owner_addr);
        }
    }


    modifier validStarMaintainer(uint64 _projectID) {
        _checkValidStarMaintainer(_projectID, msg.sender);
        _;
    }

    function _checkValidStarMaintainer(uint64 _projectID, address _owner_addr) internal view
    {
        if(is_owner_or_maintainer(_projectID, _owner_addr) == false)
        {
            revert ErrGov_NotAuthorizedToManipulateStar(_projectID, _owner_addr);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////// Maintainers Access control /////////////////////////////
    
    function star_owner(uint64 star_projectID) public view returns(address)
    {     
        if(star_projectID <= FREE_DEFAULT_TOKEN_ID64) return address(0);
        return _star_ownership_inventory.ownerOf(uint256(star_projectID));
    }

    /**
     * This method is called by FREEDERATION
     */
    function set_star_ownership(uint64 star_projectID, address owner_pk) external onlyOwner
    {
        // register star into inventory
        _star_ownership_inventory.grant(owner_pk, uint256(star_projectID));
    }

    /**
     * This method is called by FREEDERATION
     */
    function revoke_ownership(uint64 star_projectID) external onlyOwner
    {
        _star_ownership_inventory.revoke(uint256(star_projectID));
    }

    /**
     * The owner could call this method
     */
    function transfer_ownership(uint64 star_projectID, address new_owner) external
    {        
        _star_ownership_inventory.transfer(uint256(star_projectID), msg.sender, new_owner);

        emit StarOwnershipTransferred(star_projectID, new_owner);
    }

    function get_stars_inventory_count(address pk_owner) public view returns(uint64)
    {
        return _star_ownership_inventory.list_count(pk_owner);
    }

    function get_inventory_starID(address pk_owner, uint64 index) public view returns(uint64)
    {
        return uint64(_star_ownership_inventory.get(pk_owner, index));
    }

    function calc_maintainer_hash(uint64 star_projectID, address maintainer) public pure returns(uint256)
    {
        uint256 u_maintain_addr = FREE_ADDRtoU256(maintainer);
        return uint256(star_projectID) | (u_maintain_addr << uint256(64));
    }

    function assign_maintainer(
        uint64 star_projectID,
        address maintainer
    ) external
    {
        address original_owner = msg.sender;

        if(original_owner == address(0) ||
           maintainer == address(0) ||
           star_projectID <= FREE_DEFAULT_TOKEN_ID64 )
        {
            revert ErrAsset_CannotGrantOnNullAddress(star_projectID);
        }

        address pk_owner = _star_ownership_inventory.ownerOf(uint256(star_projectID));
        if(pk_owner != original_owner)
        {
            revert ErrAsset_WrongAssetOwner(star_projectID, original_owner, pk_owner);
        }
        
        uint256 maintainerhash = calc_maintainer_hash(star_projectID, maintainer);
        _star_maintainers[maintainerhash] = maintainer;

        emit StarMaintainerAssigned(star_projectID, maintainer, original_owner);
    }

    function is_maintainer(uint64 star_projectID, address maintainer) public view returns(bool)
    {
        uint256 maintainerhash = calc_maintainer_hash(star_projectID, maintainer);
        return _star_maintainers[maintainerhash] == maintainer ? true : false;
    }

    function revoke_maintainer(uint64 star_projectID, address maintainer) external
    {
        address original_owner = msg.sender;

        if(original_owner == address(0) ||
           maintainer == address(0) ||
           star_projectID <= FREE_DEFAULT_TOKEN_ID64)
        {
            revert ErrAsset_CannotGrantOnNullAddress(star_projectID);
        }

        address pk_owner = _star_ownership_inventory.ownerOf(uint256(star_projectID));
        if(pk_owner != original_owner)
        {
            revert ErrAsset_WrongAssetOwner(star_projectID, original_owner, pk_owner);
        }
        
        uint256 maintainerhash = calc_maintainer_hash(star_projectID, maintainer);
        _star_maintainers[maintainerhash] = address(0);
    }

    function is_owner(uint64 star_projectID, address operator) public view returns(bool)
    {
        if(operator == address(0) || star_projectID <= FREE_DEFAULT_TOKEN_ID64) return false;
        return _star_ownership_inventory.ownerOf(uint256(star_projectID)) == operator ? true : false;
    }

    function is_owner_or_maintainer(uint64 star_projectID, address operator) public view returns(bool)
    {
        if(operator == address(0) || star_projectID <= FREE_DEFAULT_TOKEN_ID64) return false;
        if(_star_ownership_inventory.ownerOf(uint256(star_projectID)) == operator) return true;

        uint256 maintainerhash = calc_maintainer_hash(star_projectID, operator);
        return _star_maintainers[maintainerhash] == operator ? true : false;
    }


    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    function change_star_info(
        uint64 star_projectID,
        string memory projectURL,
        string memory description
    ) external validStarOwner(star_projectID)
    { 
        _star_db_contract.change_star_info(star_projectID, projectURL, description);
    }

    function change_star_name(
        uint64 star_projectID,
        bytes32 newname
    ) external validStarOwner(star_projectID)
    {
        _star_db_contract.change_star_name(star_projectID, newname);
    }

    function configure_governance_quorum(
        uint64 star_projectID,
        StarGovernanceQuorum memory govinfo
    ) external validStarOwner(star_projectID)
    {        

        _star_governance_contract.configure_governance_quorum(star_projectID, govinfo);
    }

    function configure_star_pricing(
        uint64 star_projectID,
        StarPricing memory pricing
    ) external validStarOwner(star_projectID)
    {
        StarGovernanceQuorum memory quorum = _star_governance_contract.project_quorum_info(star_projectID);

        if(quorum.project_changing_quorum_rate != 0 || quorum.project_changing_quorum_min_count != 0)
        {
            revert ErrGov_StarLimitedByGovernance(star_projectID);
        }

        _star_db_contract.configure_star_pricing(star_projectID, pricing);
    }

    /**
     * Owner of the project attempts to sponsor another project (if no quorum governance has been stablished)
     */
    function direct_project_sponsorship(
        uint64 sponsor_projectID,
        uint64 promoted_projectID
    ) external validStarOwner(sponsor_projectID)
    {
        StarGovernanceQuorum memory quorum = _star_governance_contract.project_quorum_info(sponsor_projectID);

        if(quorum.project_changing_quorum_rate != 0 || quorum.project_changing_quorum_min_count != 0)
        {
            revert ErrGov_StarLimitedByGovernance(sponsor_projectID);
        }

        // promote star
        _star_db_contract.promote_star_sponsor(
            sponsor_projectID, promoted_projectID,
            _minimum_sponsorship_prestige_level
        );

        emit StarSponsorship(sponsor_projectID, promoted_projectID);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////

    function get_quorum_config_proposal(uint256 sessionID) public view returns(StarGovernanceQuorum memory)
    {
        return _star_quorum_proposal[sessionID];
    }

    /**
     * This Method should be called by maintainer
     */
    function make_quorum_config_proposal(
        uint64 star_projectID,
        StarGovernanceQuorum memory config
    ) external validStarOwner(star_projectID) returns(uint256)
    {
        uint256 sessionID = _star_governance_contract.register_voting_session(
            star_projectID,
            eDeliberationKind.QUORUM_DELIBERATION, 0
        );

        _star_quorum_proposal[sessionID] = config;

        return sessionID;
    }

    //////////////////////////////////////////////////////////////////////////////////

    function get_pricing_config_proposal(uint256 sessionID) public view returns(StarPricing memory)
    {
        return _star_pricing_proposal[sessionID];
    }

    function make_pricing_config_proposal(
        uint64 star_projectID,
        StarPricing memory config
    ) external validStarOwner(star_projectID) returns(uint256)
    {
        uint256 sessionID = _star_governance_contract.register_voting_session(
            star_projectID,
            eDeliberationKind.PRICING_DELIBERATION, 0
        );

        _star_pricing_proposal[sessionID] = config;

        return sessionID;
    }

    //////////////////////////////////////////////////////////////////////////////////

    function make_sponsorship_proposal(
        uint64 sponsor_projectID,
        uint64 promoted_projectID
    ) external validStarOwner(sponsor_projectID) returns(uint256)
    {
        if(promoted_projectID == 0)
        {
            revert ErrGov_NotAuthorizedToManipulateStar(sponsor_projectID, msg.sender);
        }

        return _star_governance_contract.register_voting_session(
            sponsor_projectID,
            eDeliberationKind.STAR_SPONSORSHIP_DELIBERATION, 
            promoted_projectID
        );        
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////

    function get_censorship_case_info(uint256 sessionID) public view returns(StarIslandCensorship memory)
    {
        return _star_island_censorship_proposal[sessionID];
    }

    function make_star_island_censorship_allegation(        
        StarIslandCensorship memory censorship_requirement
    ) external validStarMaintainer(censorship_requirement.star_projectID) returns(uint256)
    {
        uint256 case_sessionID = _star_governance_contract.register_voting_session(
            censorship_requirement.star_projectID,
            eDeliberationKind.ISLAND_CENSORSHIP_DELIBERATION,
            censorship_requirement.islandID
        );

        _star_island_censorship_proposal[case_sessionID] = censorship_requirement;

        return case_sessionID;
    }

    /////////////////////////////////////////////////////////////////////////////
    function make_task_proposal(
        StarTaskProposal memory proposal
    ) external validStarMaintainer(proposal.star_projectID) returns(uint256)
    {
        return _star_governance_contract.make_task_proposal(proposal);
    }

    ///////////////////////////////////////////////////////////////////////////
    function commit_vote(
        uint256 islandID,
        uint256 sessionID,
        bool approval
    ) external onlyOwner returns(eVotingState, eDeliberationKind)
    {
        (eVotingState vstate, eDeliberationKind vkind) = _star_governance_contract.commit_vote(islandID, sessionID, approval);
        
        if(vstate == eVotingState.CASE_APPROVED && 
            (
                vkind == eDeliberationKind.QUORUM_DELIBERATION ||
                vkind == eDeliberationKind.PRICING_DELIBERATION ||
                vkind == eDeliberationKind.STAR_SPONSORSHIP_DELIBERATION
            )
        )
        {
            uint64 star_projectID = _star_governance_contract.voting_session_project(sessionID);

            if(vkind == eDeliberationKind.QUORUM_DELIBERATION)
            {
                StarGovernanceQuorum storage new_gov_quorum = _star_quorum_proposal[sessionID];

                _star_governance_contract.configure_governance_quorum(star_projectID, StarGovernanceQuorum({
                    budget_quorum_rate: new_gov_quorum.budget_quorum_rate,
                    budget_quorum_min_count: new_gov_quorum.budget_quorum_min_count,
                    censorship_quorum_rate: new_gov_quorum.censorship_quorum_rate,
                    censorship_quorum_min_count: new_gov_quorum.censorship_quorum_min_count,
                    project_changing_quorum_rate: new_gov_quorum.project_changing_quorum_rate,
                    project_changing_quorum_min_count: new_gov_quorum.project_changing_quorum_min_count
                }));
            }
            else if(vkind == eDeliberationKind.PRICING_DELIBERATION)
            {
                StarPricing storage new_pricing = _star_pricing_proposal[sessionID];
                _star_db_contract.configure_star_pricing(star_projectID, new_pricing);
            }
            else if(vkind == eDeliberationKind.STAR_SPONSORSHIP_DELIBERATION)
            {
                uint256 subject_proj = _star_governance_contract.voting_session_subject(sessionID);
                // promote star
                _star_db_contract.promote_star_sponsor(
                    star_projectID, uint64(subject_proj),
                    _minimum_sponsorship_prestige_level
                );

                emit StarSponsorship(star_projectID, uint64(subject_proj));
            }
        }

        return (vstate, vkind);
    }   

}