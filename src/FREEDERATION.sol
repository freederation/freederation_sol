//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./dao/StarGovController.sol";
import "./dao/PlanetDB.sol";
import "./dao/IslandDB.sol";
import "./dao/NucleusToken.sol";
import "./DVRANDAO.sol";
import "./dao/IslandRingMarket.sol";

error ErrDAO_NotEnoughBountyForIslandRANDAO(uint256 required_bounty);

error ErrDAO_IslandAlreadyAskedRANDAO(uint256 islandID);

error ErrDAO_IslandDoesNotHaveRNDForRings(uint256 islandID);

error ErrDAO_IslandAlreadyObtainedRings(uint256 islandID);

struct FREEDERATIONParams
{
    ///  ********** Global parameters **************** ///
    ///
    /// Global tax percentaje from commissions (5%)
    uint256 global_tax_rate;


    /**
     * Minimum commissions ammount that an Star has to 
     * collect in taxes (~ 5% global tax) in order to be considerd "Worthy",
     * So it could being processed and get promoted during this periods.
     */
    uint256 minimum_tax_per_period;

    /**
     * Number of periods that has to be elapsed before
     * the guilty Star has to be punished by losing another grace period.
     */
    uint32 punishment_periods_before_payout;
    ///

    ///  ********** Global Promotion parameters **************** ///
    ///

    /**
     * Minimum amount of tax revenue that an Star has to collect in order 
     * to being nominated for the Promotion Lottery
     */
    uint256  minimum_promotion_tax_revenue;

    /**
     * Minimum number of planets that an Star has to subscribe in order 
     * to being nominated for the Promotion Lottery
     */
    uint32  minimum_promotion_planet_count;

    /**
     * Minimum grace periods that an Star has to endure in order
     * to being allowed to promote other unnaccredited projects.
     */
    uint32 minimum_sponsorship_prestige_level;

    /**
     * Duration of a Grace Period in order to evoluting to the next prestige level.
     */
    uint grace_period_duration;

    /**
     * Minimum bounty for Island RANDAO taks
     */
    uint256 minimum_island_randao_bounty;

    /**
     * Allowed rings per island
     */
    uint32 max_rings_x_island;

    uint32 max_rings_gen_iterations;
}

uint32 constant FREE_RING_MARKET_HANDLE_CODE = 5;


contract FREEDERATION is ReentrancyGuard, Ownable, IRingMarketListener
{    
    using Address for address;
    using Address for address payable;

    event StarProjectCreated(uint64 new_star_projectID, address owner);

    event StarIslandCollectedFunds(
        uint256 star_projectID,        
        uint256 planetID,
        uint256 islandID,
        uint256 project_budget,
        uint256 tax_revenue,
        uint256 insurance_ammount,
        uint256 vesting_commissions,
        uint256 contributed_funds
    );

    event StarPlanetCollectedFunds(
        uint256 star_projectID,
        uint256 planetID,
        uint256 project_budget,
        uint256 contributed_funds
    );

    event StarCollectedFunds(
        uint256 star_projectID,        
        uint256 project_budget,
        uint256 contributed_funds
    );

    event StarCollectedFundsTax(
        uint256 star_projectID,        
        uint256 tax_revenue,
        uint256 contributed_funds
    );

    event StarCollectedFundsInsurance(
        uint256 star_projectID,
        uint256 insurance,
        uint256 contributed_funds
    );

    event StarBudgetFundsClaimed(uint256 star_projectID, address receiver, uint256 payout);

    event StarBudgetTaskPayoutClaimed(uint256 taskID, address receiver, uint256 payout);

    event PlanetCommissionClaimed(
        uint64 star_projectID, 
        uint256 planet_shareID,
        address receiver,
        uint256 payout,
        uint256 commissions_left
    );

    event IslandGeneratedRings(uint64 star_projectID, uint256 islandID, uint32 num_rings);
    
    ///  ********** Global parameters **************** ///    
    FREEDERATIONParams private _global_params;
    ///  ********** **************************** **************** ///

    ///  ********** *****Extension Contracts ************ *********** ///
    StarGovernance private _star_governance_contract;
    StarProjectDB private _star_db_contract;
    StarGovController private _star_controller_contract;
    PlanetDB private _planets_db_contract;
    IslandDB private _islands_db_contract;
    FREE_NucleusToken private _nucleus_token_contract;
    DVRANDAO private _randao_contract;
    IslandRingMarket private _rings_market_contract;

    /*********************RANDAO*********************/ 

    /**
     * Maps islandID to RANDAO Campaigns
     */
    mapping(uint256 => uint256) _island_ring_rnd_campaigns;

    ///  ********** *********General FREEDERATION budget ************ ///    
    uint256 private _FREEDERATION_budget;

    ///  ********** *********Extension Data for Contracts ********* ///
    uint256 private _punishment_sentenceID;
    
    ///  ********** **************************** **************** ///

    constructor() Ownable(owner())
    {     
        address initialOwner = address(this);

        _global_params.global_tax_rate = uint256(500);
        _global_params.minimum_tax_per_period = uint256(20000000);
        _global_params.punishment_periods_before_payout = 2;
        _global_params.minimum_promotion_tax_revenue = uint256(40000000);
        _global_params.minimum_promotion_planet_count = 3;
        _global_params.minimum_sponsorship_prestige_level = FREE_AGE_FOR_SPONSORSHIP;
        _global_params.minimum_island_randao_bounty = _global_params.minimum_promotion_tax_revenue;

        _global_params.max_rings_x_island = 5;
        _global_params.max_rings_gen_iterations = 20;
        
        _FREEDERATION_budget = 0;

        _punishment_sentenceID = FREE_DEFAULT_TOKEN_ID;

        _star_governance_contract = new StarGovernance(initialOwner);
        _star_db_contract = new StarProjectDB(initialOwner);

        _star_controller_contract = new StarGovController(
            address(_star_governance_contract),
            address(_star_db_contract),
            _global_params.minimum_sponsorship_prestige_level, initialOwner
        );

        // connect controller contract
        _star_governance_contract.assignControllerRole(address(_star_controller_contract));
        _star_db_contract.assignControllerRole(address(_star_controller_contract));

        _planets_db_contract = new PlanetDB(initialOwner);
        _islands_db_contract = new IslandDB(initialOwner);
        _nucleus_token_contract = new FREE_NucleusToken(initialOwner);
        _randao_contract = new DVRANDAO(initialOwner);

        // Ring market will notify FREEDERATION when completing rings group        
        _rings_market_contract = new IslandRingMarket(address(this), FREE_RING_MARKET_HANDLE_CODE, initialOwner);
    }

    function stars_db_contract() public view returns(address)
    {
        return address(_star_db_contract);
    }

    function stars_governance_contract() public view returns(address)
    {
        return address(_star_governance_contract);
    }

    function stars_gov_controller_contract() public view returns(address)
    {
        return address(_star_controller_contract);
    }

    function planets_db_contract() public view returns(address)
    {
        return address(_planets_db_contract);
    }

    function islands_db_contract() public view returns(address)
    {
        return address(_islands_db_contract);
    }

    function nucleus_token_contract() public view returns(address)
    {
        return address(_nucleus_token_contract);
    }

    function randao_contract() public view returns(address)
    {
        return address(_randao_contract);
    }

    function rings_market_contract() public view returns(address)
    {
        return address(_rings_market_contract);
    }

    function get_FREEDERATION_params() public view returns(FREEDERATIONParams memory)
    {
        return _global_params;
    }

    function config_FREEDERATION_params(FREEDERATIONParams memory params) external onlyOwner nonReentrant
    {
        _global_params = params;
    }

    //////////////////////////Mint Nucleus Token ///////////////////////////////

    function mint_nucleus_token() external payable nonReentrant
    {
        address target = msg.sender;
        if(target == address(0))
        {
            revert ErrDAO_InvalidParams();
        }

        uint256 payment = msg.value;

        _nucleus_token_contract.nucleus_token_mint(target, payment);
        
        _FREEDERATION_budget += payment;
    }

    ///////////////////////// Star Project ////////////////////////////////////////
    function create_star_project(
        StarMeta memory project_info, 
        StarPlanetMinting memory minting_info
    ) external nonReentrant returns(uint64)
    {
        address target = msg.sender;
        if(target == address(0))
        {
            revert ErrDAO_InvalidParams();
        }

        // 1) Spend Nucleus Token
        // 2) Create project in Stars DB with meta info
        // 3) Assign project ownership in StarGovController contract
        // 4) Create project budget in  Star Governance.
        // 5) Create planet minting info in PlanetsDB

        _nucleus_token_contract.spend_nucleus_token(target); // reverts on error

        uint64 new_star_projectID = _star_db_contract.register_star_project(project_info); // reverts on error

        _star_controller_contract.set_star_ownership(new_star_projectID, target);

        _star_governance_contract.register_star_project(new_star_projectID);

        _planets_db_contract.register_star_project(new_star_projectID, minting_info);

        emit StarProjectCreated(new_star_projectID, target);

        return new_star_projectID;
    }

    /////////////////////// Mint Planet on Star Project /////////////////////////
    
    /**
     * Returns a tuple with an unique planet share: (planetID, planet_shareID)
     */
    function owner_mint_planet(
        uint64 star_projectID,
        bytes32 planet_name,
        uint256 commission_increment
    ) external nonReentrant returns(uint256, uint256)
    {
        address target = msg.sender;
        if(target == address(0))
        {
            revert ErrDAO_InvalidParams();
        }

        // check ownership
        if(_star_controller_contract.is_owner(star_projectID, target) == false)
        {
            revert ErrDAO_NotAuthorizedToStar(star_projectID, target);
        }      

        StarPlanetMinting memory minting = _planets_db_contract.star_planet_minting(star_projectID);

        PlanetEntryParams memory planet_params = PlanetEntryParams({
            planet_name: planet_name,
            star_projectID: star_projectID,
            commission_increment : commission_increment,
            star_prestige: FREE_PIONEER_SPONSOR_PLANET_CURVE,
            island_free_minting: minting.island_free_minting
        });

        return _planets_db_contract.owner_planet_minting(target, planet_params);
    }

    /**
     * Returns a tuple with an unique planet share: (planetID, planet_shareID)
     */
    function planet_minting_signature(
        uint64 star_projectID,
        bytes32 planet_name,
        uint256 commission_increment,
        SignatureAuthorization memory authorization
    ) external payable nonReentrant returns(uint256, uint256)
    {
        address target = msg.sender;
        if(target == address(0) || star_projectID <= FREE_DEFAULT_TOKEN_ID64)
        {
            revert ErrDAO_InvalidParams();
        }

        // Is this star in incubation phase?
        if(_star_db_contract.is_nebulous_star(star_projectID) == false)
        {
            revert ErrDAO_NotAllowedToMintPlanet(star_projectID, target);
        }

        // check ownership
        if(_star_controller_contract.is_owner_or_maintainer(star_projectID, authorization.pk_authorizer) == false)
        {
            revert ErrDAO_NotAuthorizedToStar(star_projectID, authorization.pk_authorizer);
        }

        uint256 payment = msg.value;

        StarPlanetMinting memory minting = _planets_db_contract.star_planet_minting(star_projectID);


        PlanetEntryParams memory planet_params = PlanetEntryParams({
            planet_name: planet_name,
            star_projectID: star_projectID,
            commission_increment : commission_increment,
            star_prestige: FREE_PIONEER_SPONSOR_PLANET_CURVE,
            island_free_minting: minting.island_free_minting
        });

        (uint256 planetID, uint256 shareID) = _planets_db_contract.planet_minting_signature(target, payment, planet_params, authorization);

        // Contribute with budget
        uint256 star_budget_balance = _star_governance_contract.contribute_star_treasury(star_projectID, payment);

        emit StarPlanetCollectedFunds(
            star_projectID,
            planetID,
            star_budget_balance,
            payment
        );

        return (planetID, shareID);
    }

    /**
     * Returns a tuple with an unique planet share: (planetID, planet_shareID)
     */
    function planet_minting_freely(
        uint64 star_projectID,
        bytes32 planet_name,
        uint256 commission_increment
    ) external payable nonReentrant returns(uint256, uint256)
    {
        address target = msg.sender;
        if(target == address(0) || star_projectID <= FREE_DEFAULT_TOKEN_ID64)
        {
            revert ErrDAO_InvalidParams();
        }

        // Is this star in incubation phase?
        if(_star_db_contract.is_nebulous_star(star_projectID) == false)
        {
            revert ErrDAO_NotAllowedToMintPlanet(star_projectID, target);
        }

        uint256 payment = msg.value;

        StarPlanetMinting memory minting = _planets_db_contract.star_planet_minting(star_projectID);

        PlanetEntryParams memory planet_params = PlanetEntryParams({
            planet_name: planet_name,
            star_projectID: star_projectID,
            commission_increment : commission_increment,
            star_prestige: FREE_PIONEER_SPONSOR_PLANET_CURVE,
            island_free_minting: minting.island_free_minting
        });

        (uint256 planetID, uint256 shareID) = _planets_db_contract.planet_minting_freely(target, payment, planet_params);

        // Contribute with budget
        uint256 star_budget_balance = _star_governance_contract.contribute_star_treasury(star_projectID, payment);

        emit StarPlanetCollectedFunds(
            star_projectID,
            planetID,
            star_budget_balance,
            payment
        );

        return (planetID, shareID);
    }

    ////////////////////////////////////////// Island Minting //////////////////////////////////

    function _obtain_valid_mint_project(uint256 planetID, address target) internal view returns(uint64)
    {
        if(target == address(0) || planetID <= FREE_DEFAULT_TOKEN_ID)
        {
            revert ErrDAO_InvalidParams();
        }

        PlanetInfo memory pinfo = _planets_db_contract.get_planet_info(planetID);
        if(pinfo.star_projectID <= FREE_DEFAULT_TOKEN_ID64 || pinfo.star_prestige == 0)
        {
            revert ErrDAO_InvalidParams();
        }

        if(_star_db_contract.is_accredited_star(pinfo.star_projectID) == false)
        {
            revert ErrDAO_StarIsNotAccredited(pinfo.star_projectID);
        }

        return pinfo.star_projectID;
    }

    function _finalize_island_minting(
        uint64 star_projectID,
        uint256 planetID,
        address target,        
        IslandMeta memory island_meta_info,
        IslandPriceCalculation memory price_calculation
    ) internal returns(uint256)
    {
        StarCommissionIncome memory income_balance = _star_db_contract.contribute_star_commissions(
            star_projectID,
            StarCommissionIncome({
                insurance_payment: price_calculation.insurance_contribution,
                tax_reserve_payment: price_calculation.freederation_tax_contribution,
                vested_commissions_payment: price_calculation.planet_commission
            })
        );

        // register island
        uint256 new_islandID = _islands_db_contract.create_island(target, star_projectID, planetID, island_meta_info);

        // register island on governance
        _star_governance_contract.register_island(star_projectID, new_islandID);

        _randao_contract.register_island(new_islandID, target);

        // contribute with project budget
        uint256 star_budget_contribution = price_calculation.island_sales_price -
                                           price_calculation.insurance_contribution -
                                           price_calculation.freederation_tax_contribution -
                                           price_calculation.planet_commission;

        uint256 star_budget_balance = _star_governance_contract.contribute_star_treasury(star_projectID, star_budget_contribution);
        
        _FREEDERATION_budget += price_calculation.freederation_tax_contribution;

        emit StarIslandCollectedFunds(
            star_projectID,        
            planetID,
            new_islandID,
            star_budget_balance,
            income_balance.tax_reserve_payment,
            income_balance.insurance_payment,
            income_balance.vested_commissions_payment,
            star_budget_contribution
        );

        return new_islandID;
    }
    
    function mint_island_freely(
        uint256 planetID,
        IslandMeta memory island_meta_info
    ) external payable nonReentrant returns(uint256)
    {
        address target = msg.sender;

        // obtain star project
        uint64 star_projectID = _obtain_valid_mint_project(planetID, target);

        // check free island minting
        if(_planets_db_contract.allows_free_island_minting(star_projectID) == false ||
           _planets_db_contract.get_island_minting_nonce(planetID) > 0)
        {
            revert ErrDAO_NotAllowedToMintIsland(planetID, target);
        }
        
        // obtain star pricing info
        StarPricing memory star_pricing = _star_db_contract.star_pricing(star_projectID);

        // calculate island selling price
        uint256 payment = msg.value;

        IslandPriceCalculation memory price_calculation = _planets_db_contract.calc_island_price(
            planetID, payment,
            IslandPricingParams({
                island_floor_price: star_pricing.island_floor_price,
                island_curve_price_rate: star_pricing.island_curve_price_rate,
                minimum_commission: star_pricing.minimum_commission,
                insurance_rate: star_pricing.insurance_rate,
                freederation_tax_rate: _global_params.global_tax_rate
            })
        );
        
        if(price_calculation.island_sales_price > payment)
        {
            revert ErrDAO_NotEnoughFundsForMintingIsland(star_projectID, planetID, price_calculation.island_sales_price);
        }

        // account contributions
        _planets_db_contract.mint_island_freely(
            planetID, 
            price_calculation.planet_commission,
            address(_star_db_contract)
        );

        return _finalize_island_minting(star_projectID, planetID, target, island_meta_info, price_calculation);
    }

    function mint_island_signature(
        uint256 planet_shareID,
        IslandMeta memory island_meta_info,
        SignatureAuthorization memory authorization
    ) external payable nonReentrant returns(uint256)
    {
        if(planet_shareID <= FREE_DEFAULT_TOKEN_ID)
        {
            revert ErrDAO_InvalidParams();
        }

        uint256 planetID = _planets_db_contract.get_share_planetID(planet_shareID);

        address target = msg.sender;

        // obtain star project
        uint64 star_projectID = _obtain_valid_mint_project(planetID, target);

        // obtain star pricing info
        StarPricing memory star_pricing = _star_db_contract.star_pricing(star_projectID);

        // calculate island selling price
        uint256 payment = msg.value;

        IslandPriceCalculation memory price_calculation = _planets_db_contract.calc_island_price(
            planetID, payment,
            IslandPricingParams({
                island_floor_price: star_pricing.island_floor_price,
                island_curve_price_rate: star_pricing.island_curve_price_rate,
                minimum_commission: star_pricing.minimum_commission,
                insurance_rate: star_pricing.insurance_rate,
                freederation_tax_rate: _global_params.global_tax_rate
            })
        );
        
        if(price_calculation.island_sales_price > payment)
        {
            revert ErrDAO_NotEnoughFundsForMintingIsland(star_projectID, planetID, price_calculation.island_sales_price);
        }

        // account contributions
        _planets_db_contract.mint_island_signature(
            planetID, 
            price_calculation.planet_commission,
            target,
            address(_star_db_contract),
            authorization
        );

        return _finalize_island_minting(star_projectID, planetID, target, island_meta_info, price_calculation);
    }

    ///////////////////////////// Contribution functions //////////////////////////
    function _check_star_contribution(uint64 star_projectID, address target, uint256 payment) internal view
    {
        if(star_projectID <= FREE_DEFAULT_TOKEN_ID64 || target == address(0) || payment == 0)
        {
            revert ErrDAO_InvalidParams();
        }
        // check project
        _star_db_contract.check_valid_project(star_projectID);
    }

    function contribute_star_treasury(
        uint64 star_projectID
    ) external payable nonReentrant
    {
        address target = msg.sender;
        uint256 payment = msg.value;

        _check_star_contribution(star_projectID, target, payment);

        // contribute with budget
        uint256 star_budget_balance = _star_governance_contract.contribute_star_treasury(star_projectID, payment);
        
        emit StarCollectedFunds(star_projectID, star_budget_balance, payment);
    }

    function contribute_star_tax_revenue(
        uint64 star_projectID
    ) external payable nonReentrant
    {
        address target = msg.sender;
        uint256 payment = msg.value;

        _check_star_contribution(star_projectID, target, payment);

        // contribute with budget
        uint256 tax_revenue_balance = _star_db_contract.contribute_tax_reserve(star_projectID, payment);        
        
        _FREEDERATION_budget += payment;

        emit StarCollectedFundsTax(star_projectID, tax_revenue_balance, payment);
    }

    function contribute_star_insurance(
        uint64 star_projectID
    ) external payable nonReentrant
    {
        address target = msg.sender;
        uint256 payment = msg.value;

        _check_star_contribution(star_projectID, target, payment);

        // contribute with budget
        uint256 insurance_balance = _star_db_contract.contribute_insurance(star_projectID, payment);
        
        emit StarCollectedFundsInsurance(star_projectID, insurance_balance, payment);
    }

    /////////////////////////////// Island Management /////////////////////////////////////

    function transfer_island_ownership(uint256 islandID, address new_owner) external nonReentrant
    {
        if(_islands_db_contract.is_island_owner(islandID, msg.sender) == false)
        {
            revert ErrDAO_NotAllowedToChangeIsland(islandID, msg.sender);
        }

        _islands_db_contract.transfer_island_ownership(islandID, msg.sender, new_owner);
        _randao_contract.change_island_owner(islandID, msg.sender, new_owner);
    }

    function delegate_island_power(uint256 islandID, uint256 delegate_islandID) external nonReentrant
    {
        if(_islands_db_contract.is_island_owner(islandID, msg.sender) == false)
        {
            revert ErrDAO_NotAllowedToChangeIsland(islandID, msg.sender);
        }

        _star_governance_contract.grant_power(islandID, delegate_islandID, 0);        
    }

    function delegate_island_power_points(uint256 islandID, uint256 delegate_islandID, uint32 weight_points) external nonReentrant
    {
        if(_islands_db_contract.is_island_owner(islandID, msg.sender) == false)
        {
            revert ErrDAO_NotAllowedToChangeIsland(islandID, msg.sender);
        }        

        _star_governance_contract.grant_power(islandID, delegate_islandID, weight_points);        
    }

    ////////////////////////////////////////// Governance //////////////////////////////////

    function _new_sentence_case() internal returns(uint256)
    {
        _punishment_sentenceID++;
        return _punishment_sentenceID;
    }

    /**
     * This method upgrade star project into accredited status
     */
    function promote_star_directly(uint64 star_projectID) external onlyOwner nonReentrant
    {
        _star_db_contract.promote_star_directly(star_projectID);
    }

    function punish_star_permanently(uint64 star_projectID) external onlyOwner nonReentrant
    {
        uint256 sentenceID = _new_sentence_case();
        _star_db_contract.punish_star_permanently(star_projectID, sentenceID);
    }


    function is_star_worthy_to_upgrade(uint64 star_projectID) public view returns(bool)
    {
        return _star_db_contract.is_worthy_to_upgrade(
            star_projectID,
            _global_params.minimum_promotion_tax_revenue,
            _global_params.grace_period_duration
        );
    }

    //// Star maintainers should call this method for upgrading star prestige level
    function upgrade_star_prestige(uint64 star_projectID) external nonReentrant
    {
        _FREEDERATION_budget += _star_db_contract.upgrade_prestige_level(
            star_projectID, 
            _global_params.minimum_sponsorship_prestige_level,
            _global_params.minimum_tax_per_period,
            _global_params.grace_period_duration
        );
    }

    /////////////// Island Governance Participation /////////////////////77

    function _destroy_island(uint256 islandID) internal
    {
        _islands_db_contract.destroy_island(islandID);
        _star_governance_contract.destroy_island_entry(islandID);
        _randao_contract.punish_island_reputation(islandID);
    }

    function star_session_commit_vote(
        uint256 islandID,
        uint256 voting_sessionID,
        bool approval
    ) external nonReentrant
    {
        // check right to use island
        if(_islands_db_contract.is_island_owner(islandID, msg.sender) == false)
        {
            revert ErrDAO_NotAllowedToChangeIsland(islandID, msg.sender);
        }

        (eVotingState vstate, eDeliberationKind vkind) = _star_controller_contract.commit_vote(islandID, voting_sessionID, approval);
        if(vstate == eVotingState.CASE_APPROVED && vkind == eDeliberationKind.ISLAND_CENSORSHIP_DELIBERATION)
        {
            uint256 target_island = _star_governance_contract.voting_session_subject(voting_sessionID);
            _islands_db_contract.destroy_island(target_island);
            _randao_contract.punish_island_reputation(target_island);
            // island already has been destroyed in governance
        }
    }

    ///////////////////// Payout from Star commissions //////////////////////////

    function claim_star_treasure_funds(
        uint64 star_projectID,
        uint256 ammount,
        address payable receiver
    ) external nonReentrant
    {
        _check_star_contribution(star_projectID, receiver, ammount); // reverts on error

        if(_star_controller_contract.is_owner(star_projectID, msg.sender) == false)
        {
            revert ErrDAO_NotAuthorizedToStar(star_projectID, msg.sender);
        }

        _star_governance_contract.extract_treasure_funds(star_projectID, ammount, receiver); // reverts on error

        // transfer funds
        Address.sendValue(receiver, ammount);

        emit StarBudgetFundsClaimed(star_projectID, receiver, ammount);    
    }


    function claim_star_finalized_task_bounty(uint256 taskID) external nonReentrant
    {
        // reverts on error
        (address receiver, uint256 payout) = _star_governance_contract.payout_fulfilled_task(taskID, msg.sender);

        // transfer funds
        Address.sendValue(payable(receiver), payout);

        emit StarBudgetTaskPayoutClaimed(taskID, receiver, payout);
    }
    
    function claim_planet_commissions(uint256 planet_shareID, address payable receiver) external nonReentrant
    {
        // reverts on error
        (uint256 payout, uint64 projectID) = _planets_db_contract.extract_commissions_payout(
            planet_shareID,
            msg.sender,
            address(_star_db_contract)
        );

        if(payout == 0)
        {
            revert ErrDAO_StarHasNotEnoughLiberatedCommissions(projectID, 0);
        }

        // obtain from liberated commissions
        uint256 vesting_funds_left = _star_db_contract.extract_liberated_commissions(projectID, payout);

        Address.sendValue(receiver, payout);

        emit PlanetCommissionClaimed(projectID, planet_shareID, receiver, payout, vesting_funds_left);
    }

    /////////////////// Island Treasure Ring manangement ///////////////

    /**
     * If 0, it tells that Island hasn't generated rings yet to it could trigger a new randao task.
     */
    function island_generated_rings(uint256 islandID) public view returns(uint32)
    {
        return _rings_market_contract.generated_rings_x_island(islandID);
    }

    /**
     * If 0, means that Island could trigger a new randao task.
     */
    function island_ring_rnd_campaign(uint256 islandID) public view returns(uint256)
    {
        return _island_ring_rnd_campaigns[islandID];
    }

    function island_ready_for_rings_generation(uint256 islandID) public view returns(bool)
    {
        uint32 already_rings_count = island_generated_rings(islandID);
        if(already_rings_count > 0) return false;
        uint256 campaignID = _island_ring_rnd_campaigns[islandID];
        if(campaignID == 0) return false;
        // check if campaign has finished
        return _randao_contract.get_campaigns_contract().is_campaign_finished(campaignID);        
    }

    function minimum_island_randao_bounty() public view returns(uint256)
    {
        return _global_params.minimum_island_randao_bounty;
    }

    /**
     * Caller should send the bounty for the task, and it should be the owner of the island.
     * If Island has already generated a campaign, this reverts on error.
     * Returns the newly generated campaign for island.
     * 
     */
    function trigger_island_randao_campaign(uint256 islandID) external payable nonReentrant returns(uint256)
    {
        address clientaddr = msg.sender;
        uint256 payment = msg.value;

        if(clientaddr == address(0) || payment == 0 || islandID <= FREE_DEFAULT_TOKEN_ID)
        {
            revert ErrDAO_InvalidParams();
        }

        if(_islands_db_contract.is_island_owner(islandID, clientaddr) == false)
        {
            revert ErrDAO_NotAllowedToChangeIsland(islandID, clientaddr);
        }

        if(payment < _global_params.minimum_island_randao_bounty)
        {
            revert ErrDAO_NotEnoughBountyForIslandRANDAO(_global_params.minimum_island_randao_bounty);
        }

        if(_island_ring_rnd_campaigns[islandID] > 0)
        {
            revert ErrDAO_IslandAlreadyAskedRANDAO(islandID);
        }

        if(island_generated_rings(islandID) > 0)
        {
            revert ErrDAO_IslandAlreadyObtainedRings(islandID);
        }
        
        uint256 new_campaignID = _randao_contract.create_new_task{value:payment}(islandID);
        _island_ring_rnd_campaigns[islandID] = new_campaignID;
        return new_campaignID;
    }

    function generate_island_treasure_rings(uint256 islandID) external nonReentrant returns(uint32)
    {
        address clientaddr = msg.sender;
        if(clientaddr == address(0) || islandID <= FREE_DEFAULT_TOKEN_ID)
        {
            revert ErrDAO_InvalidParams();
        }

        if(_islands_db_contract.is_island_owner(islandID, clientaddr) == false)
        {
            revert ErrDAO_NotAllowedToChangeIsland(islandID, clientaddr);
        }

        if(island_generated_rings(islandID) > 0)
        {
            revert ErrDAO_IslandAlreadyObtainedRings(islandID);
        }

        uint256 campaignID = _island_ring_rnd_campaigns[islandID];
        if(campaignID == 0)
        {
            revert ErrDAO_IslandDoesNotHaveRNDForRings(islandID);
        }

        // check if campaign has finished
        if(_randao_contract.get_campaigns_contract().is_campaign_finished(campaignID) == false)
        {
            revert ErrDAO_IslandDoesNotHaveRNDForRings(islandID);
        }

        uint64 star_projectID = _islands_db_contract.get_island_info(islandID).star_projectID;
        
        uint256 rnd_seed = _randao_contract.get_campaigns_contract().campaign_rnd_result(campaignID);

        uint32 generated_rings = _rings_market_contract.generate_random_rings(
            IslandRingGenParams({
                receiver: clientaddr,
                star_projectID:star_projectID,
                islandID: islandID,
                rnd_seed: rnd_seed,
                required_rings: _global_params.max_rings_x_island,
                max_iterations: _global_params.max_rings_gen_iterations
            })
        );
        
        if(generated_rings == 0)
        {
            // clear randao task and allow island to generate more rings in the future
            _island_ring_rnd_campaigns[islandID] = 0;
        }
        
        emit IslandGeneratedRings(star_projectID, islandID, generated_rings);

        return generated_rings;
    }

    /**
     * This method creates a new planet from the completed group of rings.
     * This also creates the participation shares for the planet.
     */
    function _complete_ring_group_planet(uint256 groupID) internal
    {
        (uint64 projectID, ) = IslandRingMarketLib.get_ring_codes_pair(groupID);
        if(_star_db_contract.is_accredited_star(projectID) == false)
        {
            revert ErrDAO_StarIsNotAccredited(projectID);
        }

        StarPricing memory spricing = _star_db_contract.star_pricing(projectID);
        StarPrestige memory sprestige =  _star_db_contract.star_prestige_info(projectID);
                
        // Create a planet with null name
        // Planet share controller could change planet metadata later
        uint256 newplanetID = _planets_db_contract.create_planet(PlanetEntryParams({
            planet_name : FREE_NULL_NAME,
            star_projectID : projectID,
            commission_increment: spricing.minimum_commission,
            star_prestige: sprestige.prestige_level,
            island_free_minting: false
        }));

        // create shares
        RingGroup memory rgroup = _rings_market_contract.ring_group_info(groupID);

        uint256 equity_shareID = rgroup.equity_list;
        assert(equity_shareID != 0);

        uint256 portion = 2000;// 20%

        // Create equity shares for planet
        while(equity_shareID != 0)
        {
            RingEquity memory requity = _rings_market_contract.ring_equity_info(equity_shareID);

            uint256 participation = requity.num_rings * portion;
            address share_owner = _rings_market_contract.equity_owner(equity_shareID);
            bool planet_control_delegate = equity_shareID == rgroup.leading_equity ? true : false;

            _planets_db_contract.create_planet_share(
                newplanetID,
                share_owner,
                participation,
                planet_control_delegate
            );

            equity_shareID = requity.next_equity;
        }
    }

    function onGroupEquityCompleted(uint256 groupID, uint32 handle_code) virtual override external
    {        
        if(handle_code == FREE_RING_MARKET_HANDLE_CODE)
        {
            if(msg.sender != address(_rings_market_contract))
            {
                revert ErrDAO_UnauthorizedAccess();
            }

            _complete_ring_group_planet(groupID);
        }
        else
        {
            revert ErrDAO_UnauthorizedAccess();
        }        
    }

}