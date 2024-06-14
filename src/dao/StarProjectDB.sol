//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "../util/FREEControllable.sol";
import "../util/FREEStackArray.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";


error ErrDAO_StarWithNameAlreadyExists(bytes32 new_name);

error ErrDAO_StarDoesntExists(uint256 projectID);

error ErrDAO_StarIsNotAccredited(uint256 projectID);

error ErrDAO_StarHasNotEnoughRevenueToEvolve(uint256 projectID);

error ErrDAO_StarIsGuilty(uint256 projectID);

error ErrDAO_CannotCondemGuiltyStar(uint256 projectID);

error ErrDAO_NotEnoughTimeForStarPrestigePromotion(uint256 projectID);

error ErrDAO_StarCannotBeingRedimed(uint256 projectID);

error ErrDAO_StarCannotBeingPromoted(uint256 projectID);

error ErrDAO_StarCannotHaveSponsorship(uint256 projectID);

error ErrDAO_StarHasntPaidItsObligations(uint256 projectID);

error ErrDAO_StarHasNotEnoughRevenueToRedemption(uint256 projectID);

error ErrDAO_StarHasNotEnoughRevenueToPromotion(uint256 projectID);

error ErrDAO_WrongRedemptionIndex(uint64 index);

error ErrDAO_WrongPromotionIndex(uint64 index);

error ErrDAO_WrongGuiltyStar(uint64 projectID);

error ErrDAO_ObligationAlreadyPaid(uint64 projectID, uint64 vesting_cycle);

error ErrDAO_CannotContributeWithBannedStar(uint64 projectID);

error ErrDAO_StarHasNotEnoughLiberatedCommissions(uint64 projectID, uint256 amount);


uint256 constant DAOVOTION_TOKEN_MASK = 0xffffffffffffffff; // 64bit token
uint64 constant FREE_DEFAULT_TOKEN_ID64 = 1;// A reference value that is not used and could indicates a null.

struct StarMeta
{
    bytes32 name;
    /// URL of the official web site for the project
    string projectURL;
    string description;    
}

/**
 * Prestige promotion status.
 * State struct, not parametrizable.
 */
struct StarPrestige
{
    /**
     * Indicates how this Star would be promoted. Also indicates if it is
     * unaccredited or if it has its reputation damaged, with the following values:
     * 
     * - FREE_STATUS_UNACCREDITED
     * - FREE_STATUS_GUILTY
     * - FREE_STATUS_ACCREDITED
     * - FREE_STATUS_PARDONED
     * - FREE_STATUS_SPONSORSHIP_BONUS
     * - FREE_STATUS_HONORABLE_BONUS
     * - FREE_STATUS_HONORABLE_SPONSOR_BONUS
     * - FREE_STATUS_SPONSORSHIP_EXTRA_BONUS
     */
    int16 promotion_status;
    
    /// Prestige level updated by vesting periods.
    uint32 prestige_level;

    /// Last time that this Start has been promoted. 
    uint last_promotion_timestamp;
}

/**
 * Price parameters for islands and commissions distribution
 */
struct StarPricing
{
    /// Island floor base price. It could vary depending of the planet bonding curve
    uint256 island_floor_price;

    /// Island percentaje factor for incrementing the base price taking the number of islands
    uint256 island_curve_price_rate;
    
    /// Minimum flat commission fee added to the price, before taxes.
    uint256 minimum_commission; 
    
    /// Insurance tax percentaje, calculated over raw commission before taxes.
    uint256 insurance_rate;

    /**
     * Percentaje of the insurance pool that can be compromised. 
     * So when the defaulted obligations surpass this threshold,
     * it triggers a global downpayment to the insurance vault
     * where all members from the entire Star organization will be charged
     * during this period by losing their commissions.
     */
    uint256 insurance_risk_threshold;
}

/**
 * Information for guilty stars.
 * This sentence is related to a hash
 * that contains the vesting cycle and the guilty star.
 * Any commission generated during this particular vesting cycle will
 * be confiscated.
 */
struct StarPunishment
{
    uint256 sentenceID;
    uint256 due_compensation;
    address indemnified_party;
    uint64 guilty_star;
    uint64 vesting_cycle;
    uint time_event;
    
    /**
     * In case of the indemnified party
     * could be satisfied successfully 
     * (thanks to insurance).
     * The reputation remains intact.
     */
    bool reputation_damage;
}


/**
 * State struct, not parametrizable.
 */
struct StarRevenue
{    
    /// total funds collected for insurance
    uint256 insurance_vault; 

    
    /**
     * Accummulated commisions retained during the current vesting cycle.
     */
    uint256 vesting_commissions;

    /**
     * The liberated commissions from previous vesting cycles
     */
    uint256 liberated_commissions;

    /**
     * This value is incremented after upgrading the prestige of the Star project.
     * However, this value is not related to the Prestige Level (Grace Periods).
     */
    uint64 vesting_cycle;
    
    /**
     * Accumulated reserve for taxes. It should 
     * reach minimum_tax_per_period for being processed 
     * at the current period.
     * If this Star remains unaccredited, the accummulated commissions
     * will be collected only for taxes.
     */
    uint256 tax_reserve;
}


struct StarSentenceParams
{
    uint256 sentenceID;
    uint256 due_compensation;    
    address indemnified_party;
}

struct StarIndemnization
{
    address indemnified_party;
    uint256 instant_downpayment;    
    uint256 indebted_amount;/// If indebted_amount is positive,the accused star becomes guilty.
    uint256 sentence_hash;/// If 0, there is not active sentences on the accused.
}

struct StarCommissionIncome
{    
    uint256 insurance_payment;
    uint256 tax_reserve_payment;
    uint256 vested_commissions_payment;
}


interface IStarProjectDB
{
    function current_star_vesting_cycle(uint64 star_projectID) external view returns(uint64);
    function is_vesting_cycle_sanctioned(uint64 star_projectID, uint64 vesting_cycle) external view returns(bool);
}



contract StarProjectDB is FREE_Controllable, IStarProjectDB
{
    using FREE_OwnershipArrayUtil for FREE_OwnershipArray;


    // Current index for ID assignation
    uint64 private _starprojectID;

    ///  ********** Star attributes **************** ///
    ///
    // Stars Info
    mapping(uint64 => StarMeta) private _star_meta;

    mapping(bytes32 => uint64) private _star_name_registry;

    
    // Stars pricing
    mapping(uint64 => StarPricing) private _star_pricing;

    // Stars prestige
    mapping(uint64 => StarPrestige) private _star_prestige;

    // Stars revenue
    mapping(uint64 => StarRevenue) private _star_revenue;
    
    
    // Star sponsors - reference mapping to sponsor Star
    mapping(uint64 => uint64) private _star_sponsors;

    mapping(uint256 => StarPunishment) private _star_punishment_registry;

    /**
     * Relation between stars and _star_punishment_registry
     */
    FREE_OwnershipArray private _star_sanctions;

    // Listing collection
    uint constant STAR_LIST_NEBULOUS = 1;
    uint constant STAR_LIST_PROMOTING = 2;    
    uint constant STAR_LIST_ACCREDITED = 3;
    uint constant STAR_LIST_GUILTY = 4;
    uint constant STAR_LIST_REDEMPTION = 5;

    FREE_OwnershipArray _star_collections;
    
    constructor(address initialOwner) FREE_Controllable(initialOwner)
    {
        _starprojectID = FREE_DEFAULT_TOKEN_ID64;
    }


    /**
     * @dev Throws if project hasn't been created yet
     */
    modifier validStarProject(uint64 _projectID) {
        _checkStarProjectID(_projectID);
        _;
    }

    function _checkStarProjectID(uint64 _projectID) internal view
    {
        if(_projectID <= FREE_DEFAULT_TOKEN_ID64 || _projectID > _starprojectID)
        {
            revert ErrDAO_StarDoesntExists(_projectID);
        }
    }

    modifier validStarNotOblivion(uint64 _projectID) {
        _checkValidNotOblivion(_projectID);
        _;
    }

    function _checkValidNotOblivion(uint64 _projectID) internal view
    {
        if(_projectID <= FREE_DEFAULT_TOKEN_ID64 || _projectID > _starprojectID)
        {
            revert ErrDAO_StarDoesntExists(_projectID);
        }

        StarPrestige storage _prestige_info = _star_prestige[_projectID];
        if(_prestige_info.promotion_status == FREE_STATUS_GUILTY && _prestige_info.prestige_level == 0)
        {
            revert ErrDAO_CannotContributeWithBannedStar(_projectID);
        }
    }

    /**
     * This function reverts if project is not valid
     */
    function check_valid_project(uint64 star_projectID) public view
    {
        _checkValidNotOblivion(star_projectID);
    }

    function star_project_by_name(bytes32 star_name) public view returns(uint64)
    {
        if(FREE_IsNullName(star_name) == true) return 0;
        
        return _star_name_registry[star_name];
    }
    
    function _initialize_project(uint64 projectID) internal
    {
        // unaccredited list
        _star_collections.insert(STAR_LIST_NEBULOUS, uint256(projectID));

        _star_prestige[projectID] = StarPrestige({
            promotion_status:FREE_STATUS_UNACCREDITED,
            prestige_level:0,
            last_promotion_timestamp:0
        });

        ///Create default values. Later these could be changed
        StarPricing storage pricing_info = _star_pricing[projectID];
        pricing_info.island_floor_price = 1000 gwei;
        pricing_info.island_curve_price_rate = 1000;// 10%
        pricing_info.minimum_commission = 1000 gwei;        
        pricing_info.insurance_rate = 100;//1%
        pricing_info.insurance_risk_threshold = FREE_MIN_INSURANCE_RISK_THRESHOLD;        


        _star_revenue[projectID] = StarRevenue({            
            insurance_vault:uint256(0),
            vesting_commissions:uint256(0),
            liberated_commissions:uint256(0),
            vesting_cycle:uint64(0),
            tax_reserve:uint256(0)
        });
    }

    function register_star_project(
        StarMeta memory project_info
    ) onlyOwner external returns(uint64)
    {
        _starprojectID++;

        // check name existence
        if(FREE_IsNullName(project_info.name) == false)
        {
            if(_star_name_registry[project_info.name] != uint256(0))
            {
                revert ErrDAO_StarWithNameAlreadyExists(project_info.name);
            }

            _star_name_registry[project_info.name] = _starprojectID;
            
        }        
        
        _star_meta[_starprojectID] =  StarMeta({
            name:project_info.name,
            projectURL:project_info.projectURL,
            description:project_info.description
        });

        _initialize_project(_starprojectID);

        return _starprojectID;
    }
    

    /////////////////////Project Information //////////////////////////

    function get_star_meta(uint64 star_projectID) public view returns(StarMeta memory)
    {
        return _star_meta[star_projectID];
    }

    function star_pricing(uint64 star_projectID) public view returns(StarPricing memory) 
    {
        return _star_pricing[star_projectID];
    }

    function star_prestige_info(uint64 star_projectID) public view returns(StarPrestige memory)
    {
        return _star_prestige[star_projectID];
    }

    function star_revenue_info(uint64 star_projectID) public view returns(StarRevenue memory)
    {
        return _star_revenue[star_projectID];
    }

    //////////////////// change project meta //////////////7///
    function change_star_info(
        uint64 star_projectID,
        string memory projectURL,
        string memory description
    ) external onlyOwner validStarNotOblivion(star_projectID)
    {    
        _star_meta[star_projectID].projectURL = projectURL;
        _star_meta[star_projectID].description = description;
    }

    function change_star_name(
        uint64 star_projectID,
        bytes32 newname
    ) external onlyOwner validStarNotOblivion(star_projectID)
    {
        if(FREE_IsNullName(newname) == false)
        {
            uint64 existing_star = _star_name_registry[newname];
            if(existing_star != uint64(0))
            {
                revert ErrDAO_StarWithNameAlreadyExists(newname);
            }
        }
        
        StarMeta storage metainfo = _star_meta[star_projectID];
        // erase old name
        if(FREE_IsNullName(metainfo.name) == false)
        {
            _star_name_registry[metainfo.name] = uint64(0);
        }      

        if(FREE_IsNullName(newname) == false)
        {
            _star_name_registry[newname] = star_projectID;
        }
        
        metainfo.name = newname;
    }
    /////////////////////////Island Pricing functions //////////////////////////////

    function configure_star_pricing(
        uint64 star_projectID,
        StarPricing memory pricing
    ) external onlyOwner validStarProject(star_projectID)
    {
        StarPricing storage _pricing_info = _star_pricing[star_projectID];
        _pricing_info.island_floor_price = pricing.island_floor_price;
        _pricing_info.minimum_commission = pricing.minimum_commission;        

        
        uint256 _insurance_rate = pricing.insurance_rate;
        uint256 _insurance_risk = pricing.insurance_risk_threshold;
        
        _pricing_info.insurance_rate = _insurance_rate > FREE_MAX_INSURANCE_PERCENTAJE ?  FREE_MAX_INSURANCE_PERCENTAJE: _insurance_rate;
        _pricing_info.insurance_risk_threshold = _insurance_risk > FREE_MAX_INSURANCE_RISK_THRESHOLD ?
                                                              FREE_MAX_INSURANCE_RISK_THRESHOLD:
                                                              (_insurance_risk < FREE_MIN_INSURANCE_RISK_THRESHOLD ?   FREE_MIN_INSURANCE_RISK_THRESHOLD : _insurance_risk);
    }

    /////////////////////////// Collections ////////////////////////////

    /// Unaccredited list of star projects
    function collection_list_count(uint32 collection_type) public view returns(uint64)
    {
        return _star_collections.list_count(uint(collection_type));
    }

    function collection_list_get(uint32 collection_type, uint64 index) public view returns(uint64)
    {
        return uint64(_star_collections.get(uint(collection_type), index));
    }

    function get_star_collection_type(uint64 star_projectID) public view returns(uint32)
    {
        int16 status = _star_prestige[star_projectID].promotion_status;
        uint list_type = STAR_LIST_ACCREDITED;

        if(status == FREE_STATUS_GUILTY)
        {
            list_type = STAR_LIST_GUILTY;
        }
        else if(status == FREE_STATUS_REDEMPTION)
        {
            list_type = STAR_LIST_REDEMPTION;
        }
        else if(status == FREE_STATUS_PROMOTING)
        {
            list_type = STAR_LIST_PROMOTING;
        }
        else if(status == FREE_STATUS_UNACCREDITED)
        {
            list_type = STAR_LIST_NEBULOUS;
        }

        return uint32(list_type);
    }    
    
    /////////////////////////// Sponsorship ////////////////////////////

    function is_accredited_star(uint64 star_projectID) public view returns(bool)
    {
        StarPrestige storage prestige_info = _star_prestige[star_projectID];

        if(prestige_info.promotion_status <= 0 || prestige_info.prestige_level < 1 )
        {
            return false;
        }
        return true;
    }

    function is_nebulous_star(uint64 star_projectID) public view returns(bool)
    {
        StarPrestige storage prestige_info = _star_prestige[star_projectID];
        return prestige_info.promotion_status == FREE_STATUS_UNACCREDITED || prestige_info.promotion_status == FREE_STATUS_PROMOTING;
    }

    function is_star_in_oblivion(uint64 star_projectID) public view returns(bool)
    {
        StarPrestige storage prestige_info = _star_prestige[star_projectID];
        return prestige_info.promotion_status == FREE_STATUS_GUILTY && prestige_info.prestige_level == 0;
    }

    function is_worthy_to_upgrade(
        uint64 star_projectID,        
        uint256 minimum_tax_per_period,
        uint grace_period_duration
    ) public view returns(bool)
    {
        StarPrestige storage prestige_info = _star_prestige[star_projectID];

        if(prestige_info.promotion_status <= 0 || prestige_info.prestige_level < 1 )
        {
            return false;
        }

        uint elapsed_time = block.timestamp - prestige_info.last_promotion_timestamp;

        if(elapsed_time < grace_period_duration)
        {
            return false;
        }        

        StarRevenue storage revenue = _star_revenue[star_projectID];

        return revenue.tax_reserve >= minimum_tax_per_period;
    }
    
    function _check_accredited_star(uint64 star_projectID, StarPrestige storage prestige_info) internal view
    {
        if(prestige_info.promotion_status == FREE_STATUS_GUILTY || prestige_info.promotion_status == FREE_STATUS_REDEMPTION)
        {
            revert ErrDAO_StarIsGuilty(star_projectID);
        }
        else if(prestige_info.promotion_status <= 0 || prestige_info.prestige_level < 1 )
        {
            revert ErrDAO_StarIsNotAccredited(star_projectID);
        }
    }
    
    /**
     * Upgrades the prestige level of the Star project DAO, and returns the
     * collected tax revenue.
     */
    function upgrade_prestige_level(
        uint64 star_projectID,
        uint32 minimum_sponsorship_prestige_level,
        uint256 minimum_tax_per_period,
        uint grace_period_duration
    ) external onlyOwner validStarProject(star_projectID) returns(uint256)
    {        
        StarPrestige storage prestige_info = _star_prestige[star_projectID];

        _check_accredited_star(star_projectID, prestige_info);
        

        uint elapsed_time = block.timestamp - prestige_info.last_promotion_timestamp;

        if(elapsed_time < grace_period_duration)
        {
            revert ErrDAO_NotEnoughTimeForStarPrestigePromotion(star_projectID);
        }        

        StarRevenue storage revenue = _star_revenue[star_projectID];

        uint256 taxrevenue = revenue.tax_reserve;
        if(taxrevenue < minimum_tax_per_period)
        {
            revert ErrDAO_StarHasNotEnoughRevenueToEvolve(star_projectID);
        }

        uint32 earned_periods = 1;
        
        // upgrade prestige level
        if((prestige_info.promotion_status & FREE_STATUS_SPONSORSHIP_BONUS) != 0)
        {
            earned_periods++;
            if((prestige_info.promotion_status & FREE_STATUS_SPONSORSHIP_EXTRA_BONUS) != 0)
            {
                earned_periods++;
            }
        }        
        if((prestige_info.promotion_status & FREE_STATUS_HONORABLE_BONUS) != 0)
        {
            earned_periods++;
        }

        prestige_info.prestige_level += earned_periods;

        // update time reference
        prestige_info.last_promotion_timestamp = block.timestamp;

        // clear revenue and liberating vested commissions
        revenue.tax_reserve = uint256(0);

        // update vesting cycle
        revenue.vesting_cycle++;
        revenue.liberated_commissions += revenue.vesting_commissions;
        revenue.vesting_commissions = uint256(0);

        if(prestige_info.prestige_level >= minimum_sponsorship_prestige_level &&
           (prestige_info.promotion_status & FREE_STATUS_PARDONED) == 0)
        {
            // Star project has graduated to sponsorship level.
            // look for sponsor
            uint64 sponsorID = _star_sponsors[star_projectID];
            if(sponsorID != uint64(0))
            {
                // reward sponsor
                StarPrestige storage sponsor_prestige = _star_prestige[sponsorID];
                if(sponsor_prestige.promotion_status > 0 &&
                   (sponsor_prestige.promotion_status & FREE_STATUS_SPONSORSHIP_BONUS) != 0)
                {
                    sponsor_prestige.promotion_status |= FREE_STATUS_SPONSORSHIP_EXTRA_BONUS;
                }

                _star_sponsors[star_projectID] = uint64(0);// unlink from sponsor
            }
        }

        return taxrevenue;
    }

    function sentence_case_hash(
        uint64 star_projectID,
        uint64 vesting_cycle) public pure returns(uint256)
    {
        return uint256(star_projectID) | (uint256(vesting_cycle) << 64);
    }

    /**
     * Sentence hash must be generated with the sentence_case_hash() function.
     */
    function fetch_sentence_info(uint256 sentence_hash) public view returns(StarPunishment memory)
    {
        return _star_punishment_registry[sentence_hash];
    }

    function star_sentence_cases_count(uint64 star_projectID) public view returns(uint64)
    {
        return _star_sanctions.list_count(star_projectID);
    }

    function get_star_sentence_case(uint64 star_projectID, uint64 index) public view returns(uint256)
    {
        if(_star_sanctions.list_count(star_projectID) <= index) return uint256(0);
        return _star_sanctions.get(star_projectID, index);
    }

    /////////////////////////////////////////////////////////////////////////////////////
    function current_star_vesting_cycle(
        uint64 star_projectID
    ) external view virtual override returns(uint64)
    {
        StarRevenue storage revenue = _star_revenue[star_projectID];
        return revenue.vesting_cycle;
    }

    /// Interface method
    function is_vesting_cycle_sanctioned(
        uint64 star_projectID,
        uint64 vesting_cycle
    ) external view virtual override returns(bool)
    {
        // PRE: A guilty star cannot change its vesting cycle
        uint256 sanction_hash = sentence_case_hash(star_projectID, vesting_cycle);
        StarPunishment storage caseinfo = _star_punishment_registry[sanction_hash];
        return caseinfo.guilty_star == star_projectID && caseinfo.vesting_cycle == vesting_cycle;
    }

    /////////////////////////////////////////////////////////////////////////////////////

    function _downgrade_sponsor(uint64 star_projectID) internal
    {        
        uint64 sponsorID = _star_sponsors[star_projectID];
        if(sponsorID == uint64(0)) return;
        StarPrestige storage sponsor_prestige = _star_prestige[sponsorID];
        
        if(sponsor_prestige.promotion_status > 0)
        {
            // Remove sponsorhip bonus
            sponsor_prestige.promotion_status = FREE_STATUS_ACCREDITED | FREE_STATUS_PARDONED;
        }

        // unlink sponsorship
        _star_sponsors[star_projectID] = uint64(0) ;
    }

    /**
     * Applies an economic penalization on Star project, and claims retribution from the insurance vault.
     * If the obliged ammount couldn't be covered by the portion of the insurance vault 
     * (equivalent to insurance_risk_threshold percentaje), then it triggers a global downpayment to the insurance vault
     * from the vesting commissions, compromising the commission sales for the current vesting cycle.
     * Returns the tuple StarIndemnization telling the indebted compensation, the sentence hash and the ammount to be paid from FREEDERATION to the indeminzed party.
     * A 0-valued sentence hash means no registry of the case.
     * The indebted compensation is greater than 0 If sanctioned star couldn't compensante the affected party, and it becames guilty. 
     */
    function punish_star_by_indemnization(
        uint64 star_projectID,        
        uint256 confiscated_commissions,
        StarSentenceParams memory sentence
    ) external onlyOwner validStarProject(star_projectID) returns(StarIndemnization memory)
    {
        StarPrestige storage condemned_prestige = _star_prestige[star_projectID];

        _check_accredited_star(star_projectID, condemned_prestige);
        
        StarRevenue storage revenue = _star_revenue[star_projectID];
        
        // Pay with confiscated commissions
        if(confiscated_commissions > 0)
        {
            revenue.vesting_commissions -= confiscated_commissions;            

            if(sentence.due_compensation <= confiscated_commissions)
            {
                // obligation satisfied                
                return StarIndemnization({
                    indemnified_party: sentence.indemnified_party,
                    instant_downpayment: confiscated_commissions,
                    indebted_amount: uint256(0),
                    sentence_hash: uint256(0)
                });
            }
            // pay with insurance
            revenue.insurance_vault += confiscated_commissions;            
        }
        
        uint256 insurance_risk_threshold = _star_pricing[star_projectID].insurance_risk_threshold;
        uint256 safe_insurance_amount = FREE_PERCENTAJE(revenue.insurance_vault, insurance_risk_threshold);

        if(sentence.due_compensation <= safe_insurance_amount)
        {
            // obligation satisfied (with insurance)
            revenue.insurance_vault -= sentence.due_compensation;

            return StarIndemnization({
                indemnified_party: sentence.indemnified_party,
                instant_downpayment: sentence.due_compensation,
                indebted_amount: uint256(0),
                sentence_hash: uint256(0)
            });
        }

        // confiscate the entire vesting commissions
        revenue.insurance_vault += revenue.vesting_commissions;
        revenue.vesting_commissions = uint256(0);
        uint64 current_vesting_cycle = revenue.vesting_cycle;

        uint256 current_indemnization = uint256(0);
        if(revenue.insurance_vault >= sentence.due_compensation)
        {
            // obligation satisfied
            current_indemnization = sentence.due_compensation;
            revenue.insurance_vault -= current_indemnization;
            revenue.vesting_cycle++;// allow to use vesting cycle in the future.            
        }
        else
        {
            // is guilty
            current_indemnization = revenue.insurance_vault;            
            revenue.insurance_vault = uint256(0);
        }
        
        // register the case

        uint256 indebted_amount = sentence.due_compensation - current_indemnization; // positive value

        uint256 punishment_hash = sentence_case_hash(star_projectID, current_vesting_cycle);
        _star_punishment_registry[punishment_hash] = StarPunishment({
            sentenceID: sentence.sentenceID,
            due_compensation: indebted_amount,
            indemnified_party: sentence.indemnified_party,
            guilty_star: star_projectID,
            vesting_cycle:current_vesting_cycle,
            time_event: block.timestamp,
            reputation_damage:indebted_amount > uint256(0)? true:false
        });

        _star_sanctions.insert(uint256(star_projectID), punishment_hash);

        if(indebted_amount == uint256(0))
        {
            // not guilty, but vesting commissions were confiscated
            return StarIndemnization({
                indemnified_party: sentence.indemnified_party,
                instant_downpayment: current_indemnization,
                indebted_amount: uint256(0),
                sentence_hash: punishment_hash
            });
        }

        // affect sponsor if any        
        _downgrade_sponsor(star_projectID);

        // declared guilty and register
        // condemned_prestige
        condemned_prestige.promotion_status = FREE_STATUS_GUILTY;

        // Mark punishment time event
        condemned_prestige.last_promotion_timestamp = block.timestamp;

        // remove from currect active list
        bool bl = _star_collections.remove_from_parent(STAR_LIST_ACCREDITED, uint256(star_projectID));
        assert(bl == true);

        // insert in the guilty pool
        _star_collections.insert(STAR_LIST_GUILTY, uint256(star_projectID));        

        return StarIndemnization({
            indemnified_party: sentence.indemnified_party,
            instant_downpayment: current_indemnization,
            indebted_amount: indebted_amount,
            sentence_hash: punishment_hash
        });
    }

    function star_can_apply_for_redemption(uint64 star_projectID, uint256 redemption_fee) public view returns(bool)
    {
        StarPrestige storage prestigeinfo = _star_prestige[star_projectID];
        if(prestigeinfo.promotion_status != FREE_STATUS_GUILTY || prestigeinfo.prestige_level < 1) return false;

        // check if it has repaid its obligations
        StarRevenue storage revenue = _star_revenue[star_projectID];
        uint256 sentence_hash = sentence_case_hash(star_projectID, revenue.vesting_cycle);
        StarPunishment storage punishment = _star_punishment_registry[sentence_hash];

        if(punishment.due_compensation > uint256(0)) return false;

        return revenue.tax_reserve >= redemption_fee;
    }

    /**
     * Returns the amount of funds charged for redemption if successfully submitted, equivalent to tax revenue
     */
    function prompt_star_for_redemption(
        uint64 star_projectID,
        uint256 minimum_redemption_fee
    ) external onlyOwner validStarProject(star_projectID) returns(uint256)
    {
        StarPrestige storage prestigeinfo = _star_prestige[star_projectID];
        if(prestigeinfo.promotion_status != FREE_STATUS_GUILTY || prestigeinfo.prestige_level < 1)
        {
            revert ErrDAO_StarCannotBeingRedimed(star_projectID);
        }


        // PRE: A guilty star cannot change its vesting cycle

        // check if it has repaid its obligations
        StarRevenue storage revenue = _star_revenue[star_projectID];
        uint256 sentence_hash = sentence_case_hash(star_projectID, revenue.vesting_cycle);
        StarPunishment storage punishment = _star_punishment_registry[sentence_hash];

        if(punishment.due_compensation > uint256(0))
        {
            revert ErrDAO_StarHasntPaidItsObligations(star_projectID);
        }
        else if(revenue.tax_reserve < minimum_redemption_fee)
        {
            revert ErrDAO_StarHasNotEnoughRevenueToRedemption(star_projectID);
        }

        prestigeinfo.promotion_status = FREE_STATUS_REDEMPTION;        

        uint256 tax_confiscation = revenue.tax_reserve;

        revenue.tax_reserve = uint256(0);

        bool bl = _star_collections.remove_from_parent(STAR_LIST_GUILTY, uint256(star_projectID));
        assert(bl == true);

        _star_collections.insert(STAR_LIST_REDEMPTION, uint256(star_projectID));

        return tax_confiscation;
    }

    function redeem_star_from_list(uint64 index, uint grace_period_duration) external onlyOwner
    {
        uint64 listcount = _star_collections.list_count(STAR_LIST_REDEMPTION);
        if(index >= listcount)
        {
            revert ErrDAO_WrongRedemptionIndex(index);
        }

        uint64 selected_star = uint64(_star_collections.get(STAR_LIST_REDEMPTION, index));
        StarPrestige storage prestige = _star_prestige[selected_star];
        
        assert(prestige.promotion_status == FREE_STATUS_REDEMPTION);

        prestige.promotion_status = FREE_STATUS_PARDONED | FREE_STATUS_ACCREDITED;        
        
        StarRevenue storage revenue = _star_revenue[selected_star];
        revenue.vesting_cycle++;// update vesting cycle

        bool bl = _star_collections.remove(STAR_LIST_REDEMPTION, index);
        assert(bl == true);

        _star_collections.insert(STAR_LIST_ACCREDITED, uint64(selected_star));

        // reduce periods lost        
        uint elapsed_time = block.timestamp - prestige.last_promotion_timestamp;
        if(elapsed_time > 0)
        {
            uint32 periods_lost = uint32(elapsed_time / grace_period_duration);
            if((periods_lost + FREE_ACCREDITED_AGE_INIT) >= prestige.prestige_level)
            {
                // set the minimum
                prestige.prestige_level = FREE_ACCREDITED_AGE_INIT;
            }
            else
            {
                prestige.prestige_level -= periods_lost;
            }
        }

        // update last promotion timestamp
        prestige.last_promotion_timestamp = block.timestamp;
    }


    /**
     * Registers indemnization required by the current punishment for the star_projectID, 
     * returns the destinatary address and the left balance of the obligation. 
     */
    function pay_guilty_star_obligation(
        uint64 star_projectID, uint256 payment
    ) external onlyOwner validStarProject(star_projectID) returns(StarIndemnization memory)
    {
        StarPrestige storage prestige = _star_prestige[star_projectID];
        if(prestige.promotion_status != FREE_STATUS_GUILTY)
        {
            revert ErrDAO_WrongGuiltyStar(star_projectID);
        }

        // PRE: A guilty star cannot change its vesting cycle

        // check if it has repaid its obligations
        StarRevenue storage revenue = _star_revenue[star_projectID];
        uint256 sentence_hash = sentence_case_hash(star_projectID, revenue.vesting_cycle);
        StarPunishment storage punishment = _star_punishment_registry[sentence_hash];
        if(punishment.due_compensation == uint256(0))
        {
            revert ErrDAO_ObligationAlreadyPaid(star_projectID, revenue.vesting_cycle);
        }

        if(punishment.due_compensation <= payment)
        {
            punishment.due_compensation = uint256(0);
        }
        else
        {
            punishment.due_compensation -= payment;            
        }

        // Acknowledge the payment
        return StarIndemnization({
            indemnified_party: punishment.indemnified_party,
            instant_downpayment: payment,
            indebted_amount: punishment.due_compensation,
            sentence_hash: sentence_hash
        });
    }


    /**
     * Applies an permanent penalization on Star project, and confiscates vested commissions, insurance and tax revenue.
     * from the vesting commissions, compromising the commission sales for the current vesting cycle.
     * Returns the tuple of the sentence hash and the ammount confiscated that will be paid to governance.
     */
    function punish_star_permanently(
        uint64 star_projectID,
        uint256 sentenceID
    ) external onlyOwner validStarProject(star_projectID) returns(uint256, uint256)
    {
        StarPrestige storage prestige = _star_prestige[star_projectID];
        if(prestige.promotion_status == FREE_STATUS_GUILTY || prestige.promotion_status == FREE_STATUS_REDEMPTION)
        {
            revert ErrDAO_CannotCondemGuiltyStar(star_projectID);
        }

        uint collection_type = prestige.promotion_status == FREE_STATUS_PROMOTING ? STAR_LIST_PROMOTING:
        (prestige.promotion_status == FREE_STATUS_UNACCREDITED ? STAR_LIST_NEBULOUS : STAR_LIST_ACCREDITED );

        // remove from collection
        bool bl = _star_collections.remove_from_parent(collection_type, star_projectID);
        assert(bl == true);

        _star_collections.insert(STAR_LIST_GUILTY, star_projectID);        
        
        /// Set guilty
        prestige.promotion_status = FREE_STATUS_GUILTY;
        prestige.prestige_level = 0;

        StarRevenue storage revenue = _star_revenue[star_projectID];

        // insert case
        // register the case
        uint256 punishment_hash = sentence_case_hash(star_projectID, revenue.vesting_cycle);
        _star_punishment_registry[punishment_hash] = StarPunishment({
            sentenceID: sentenceID,
            due_compensation:0,
            indemnified_party: address(0),
            guilty_star: star_projectID,
            vesting_cycle: revenue.vesting_cycle,
            time_event: block.timestamp,
            reputation_damage:true
        });

        _star_sanctions.insert(uint256(star_projectID), punishment_hash);

        // extract funds
        uint256 confiscated_funds = revenue.tax_reserve;
        revenue.tax_reserve = 0;

        confiscated_funds += revenue.insurance_vault;
        revenue.insurance_vault = 0;

        if(collection_type != STAR_LIST_ACCREDITED)
        {
            return (punishment_hash, confiscated_funds);
        }

        // extract commissions
        confiscated_funds += revenue.vesting_commissions;
        revenue.vesting_commissions = 0;

        // affect sponsor if any        
        _downgrade_sponsor(star_projectID);

        // remove name
        StarMeta storage metainfo = _star_meta[star_projectID];
        if(FREE_IsNullName(metainfo.name) == false)
        {
            _star_name_registry[metainfo.name] = uint64(0);
        }
        

        return (punishment_hash, confiscated_funds);
    }

    /////////////////////// Promotion of new projects /////////////////////////////////

    function star_can_apply_for_promotion(uint64 star_projectID, uint256 redemption_fee) public view returns(bool)
    {
        StarPrestige storage prestigeinfo = _star_prestige[star_projectID];
        if(prestigeinfo.promotion_status != FREE_STATUS_UNACCREDITED) return false;

        // check if it has repaid its obligations
        StarRevenue storage revenue = _star_revenue[star_projectID];        
        return revenue.tax_reserve >= redemption_fee;
    }

    /**
     * Returns the entire tax revenue if succeed.
     */
    function prompt_star_for_promotion(
        uint64 star_projectID,
        uint256 minimum_promotion_fee
    ) external onlyOwner validStarProject(star_projectID) returns(uint256)
    {
        StarPrestige storage prestigeinfo = _star_prestige[star_projectID];
        if(prestigeinfo.promotion_status != FREE_STATUS_UNACCREDITED)
        {
            revert ErrDAO_StarCannotBeingPromoted(star_projectID);
        }

        // check if it has repaid its obligations
        StarRevenue storage revenue = _star_revenue[star_projectID];
        if(revenue.tax_reserve < minimum_promotion_fee)
        {
            revert ErrDAO_StarHasNotEnoughRevenueToPromotion(star_projectID);
        }

        prestigeinfo.promotion_status = FREE_STATUS_PROMOTING;
        prestigeinfo.last_promotion_timestamp = block.timestamp;
        
        uint256 tax_confiscation = revenue.tax_reserve;
        revenue.tax_reserve = uint256(0);

        bool bl = _star_collections.remove_from_parent(STAR_LIST_NEBULOUS, uint256(star_projectID));
        assert(bl == true);

        _star_collections.insert(STAR_LIST_PROMOTING, uint256(star_projectID));

        return tax_confiscation;
    }


    function _promoting_to_accredited_util(
        uint64 star_projectID,
        uint old_collection_type,
        StarPrestige storage prestigeinfo) internal
    {
        prestigeinfo.promotion_status = FREE_STATUS_ACCREDITED;
        prestigeinfo.prestige_level = FREE_ACCREDITED_AGE_INIT;
        prestigeinfo.last_promotion_timestamp = block.timestamp;        
        
        StarRevenue storage revenue = _star_revenue[star_projectID];
        revenue.vesting_cycle++;        

        bool bl = _star_collections.remove_from_parent(old_collection_type, uint256(star_projectID));
        assert(bl == true);
        
        _star_collections.insert(STAR_LIST_ACCREDITED, uint256(star_projectID));
    }

    function promote_star_from_list(uint64 index) external onlyOwner
    {
        uint64 listcount = _star_collections.list_count(STAR_LIST_PROMOTING);
        if(index >= listcount)
        {
            revert ErrDAO_WrongPromotionIndex(index);
        }

        uint64 selected_star = uint64(_star_collections.get(STAR_LIST_PROMOTING, index));
        StarPrestige storage prestige = _star_prestige[selected_star];
        
        assert(prestige.promotion_status == FREE_STATUS_PROMOTING);

        _promoting_to_accredited_util(selected_star, STAR_LIST_PROMOTING, prestige);
    }

    function _promote_star_ex(uint64 star_projectID) internal
    {
        StarPrestige storage prestigeinfo = _star_prestige[star_projectID];

        uint collection_type = prestigeinfo.promotion_status == FREE_STATUS_PROMOTING ? STAR_LIST_PROMOTING:
        (prestigeinfo.promotion_status == FREE_STATUS_UNACCREDITED ? STAR_LIST_NEBULOUS : STAR_LIST_ACCREDITED );

        if(collection_type == STAR_LIST_ACCREDITED)
        {
            revert ErrDAO_StarCannotBeingPromoted(star_projectID);
        }

        _promoting_to_accredited_util(star_projectID, collection_type, prestigeinfo);
    }


    function promote_star_directly(
        uint64 star_projectID
    ) external onlyOwner validStarProject(star_projectID)
    {
        _promote_star_ex(star_projectID);
    }


    function promote_star_sponsor(
        uint64 star_projectID,
        uint64 sponsorID,
        uint32 minimum_sponsorship_prestige_level
    ) external onlyOwner validStarProject(star_projectID) validStarProject(sponsorID)
    {
        StarPrestige storage sponsorprestige = _star_prestige[sponsorID];

        if((sponsorprestige.promotion_status <= 0) ||
           (sponsorprestige.prestige_level < 1) ||
           (sponsorprestige.promotion_status & FREE_STATUS_PARDONED) != 0 ||
           (sponsorprestige.prestige_level < minimum_sponsorship_prestige_level))
        {
            revert ErrDAO_StarCannotHaveSponsorship(sponsorID);
        }
        

        // reward as sponsor
        sponsorprestige.promotion_status |= FREE_STATUS_SPONSORSHIP_BONUS;

        _promote_star_ex(star_projectID);
    }


    ////////////////////////////////////////////////////////////////////
    /////// Star funds contribution /////
    /**
     * Contributes with tax revenue, insurance and commissions.
     * Returns the total amount of accummulated contributions in the project revenue
     */
    function contribute_star_commissions(
        uint64 star_projectID,
        StarCommissionIncome memory contribution
    ) external onlyOwner validStarNotOblivion(star_projectID) returns(StarCommissionIncome memory)
    {
        StarRevenue storage revenue = _star_revenue[star_projectID];
        
        revenue.insurance_vault += contribution.insurance_payment;
        revenue.tax_reserve += contribution.tax_reserve_payment;
        revenue.vesting_commissions += contribution.vested_commissions_payment;

        return StarCommissionIncome({            
            insurance_payment:revenue.insurance_vault,
            tax_reserve_payment:revenue.tax_reserve,
            vested_commissions_payment:revenue.vesting_commissions
        });
    }

    function contribute_tax_reserve(
        uint64 star_projectID,
        uint256 payment
    ) external onlyOwner validStarNotOblivion(star_projectID) returns(uint256)
    {        
        StarRevenue storage revenue = _star_revenue[star_projectID];

        revenue.tax_reserve += payment;
        return revenue.tax_reserve;
    }

    function contribute_insurance(
        uint64 star_projectID,
        uint256 payment
    ) external onlyOwner validStarNotOblivion(star_projectID) returns(uint256)
    {        
        StarRevenue storage revenue = _star_revenue[star_projectID];

        revenue.insurance_vault += payment;
        return revenue.insurance_vault;
    }

    /**
     * Reverts on error or if ammount exceeded the available funds from liberated commissions
     * Returns the amount of funds left in the revenue balance.
     */
    function extract_liberated_commissions(
        uint64 star_projectID,
        uint256 ammount
    ) external onlyOwner validStarProject(star_projectID) returns(uint256)
    {
        StarRevenue storage revenue = _star_revenue[star_projectID];
        if(revenue.liberated_commissions < ammount)
        {
            revert ErrDAO_StarHasNotEnoughLiberatedCommissions(star_projectID, ammount);
        }

        revenue.liberated_commissions -= ammount;
        return revenue.liberated_commissions;
    }

}