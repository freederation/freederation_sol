// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.8;

import "forge-std/Test.sol";
import "../src/DVRANDAO.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

contract DVRANDAOTest is Test {
    using stdStorage for StdStorage;
    using FREE_StackArrayUtil for FREE_StackArray;
    using FREE_OwnershipArrayUtil for FREE_OwnershipArray;

    DVRANDAO private randao;
    mapping(uint32 => address) private _address_set;
    mapping(uint32 => uint256) private _private_keys_set;
    uint32 private _num_keys;
    uint256 private _task_ID;
    VRFCircleProblem _test_circle_problem;
    FREE_OwnershipArray _records_x_island;
    uint32 _islands_x_address_count;

    mapping(uint256 => VRFCircle) private _records_solutions;

    function setUp() public {
        address initialOwner = address(this);

        _num_keys = 0;
        _islands_x_address_count = 4;
        _task_ID = uint256(1);
        // Deploy NFT contract
        randao = new DVRANDAO(initialOwner);
        console.log("Contract DVRANDAO Deployed At", address(randao));

        // create a custom Circle Problem contract for testing
        _test_circle_problem = new VRFCircleProblem(randao.get_random_seed(), initialOwner);		
    }

    function _generate_key(uint256 pkey_hash) internal
    {
        string memory str_hash = Strings.toHexString(pkey_hash);
        console.log("- Private Key ", str_hash);
        _private_keys_set[_num_keys] = pkey_hash;
        address addrkey = vm.addr(pkey_hash);
        console.log("- Public Key ", addrkey);
        _address_set[_num_keys] = addrkey;
        _num_keys++;
    }

    function _generate_key_raw(uint256 private_key, address public_key) internal
    {		
        _private_keys_set[_num_keys] = private_key;
        _address_set[_num_keys] = public_key;
        _num_keys++;
    }

    function create_keys(uint32 total_keys) internal
    {		
        console.log("**Generating Keys", total_keys);
        // mnemonic need 12 word
        for(uint32 i = 0; i < total_keys; i++)
        {
            uint256 rnd_number = _test_circle_problem.next_rnd_number();
            _generate_key(rnd_number);
        }
    }

    function create_keys0() internal
    {
        console.log("Generating Keys Raw");
        
        _generate_key_raw(
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80),
            address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266)
        );

        _generate_key_raw(
            uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d),
            address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8)
        );

        _generate_key_raw(
            uint256(0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a),
            address(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC)
        );
    }

    function create_islands(uint32 islands_x_account) internal
    {
        console.log("\n*** Create Islands ***\n");
        _islands_x_address_count = islands_x_account;
        uint256 islandID = 1;		
        for(uint32 i = 0; i < _num_keys; i++)
        {
            address owner_pk = _address_set[i];
            for(uint32 j = 0; j < _islands_x_address_count; j++)
            {
                // create islands
                console.log("\nAttemmpting to create Island ", islandID, ", For Address ", owner_pk);
                randao.register_island(islandID, owner_pk);
                islandID++;
            }			
        }
    }

    function create_tasks(uint32 num_tasks) internal
    {
        console.log("\n*** Create Tasks ***\n");
        uint256  max_bounty = address(this).balance / 10000000000;

        for(uint32 i = 0; i < num_tasks; i++)
        {
            uint256 rnd_number = _test_circle_problem.next_rnd_number();
            uint256 bounty = rnd_number % max_bounty;
            console.log("\nAttemmpting to create a task ", _task_ID, ", With Bounty = ", bounty);
            randao.create_new_task{value:bounty}(_task_ID);
            _task_ID++;
        }
    }

    function create_test_problem(uint32 num_static_circles) internal
    {
        _test_circle_problem.restart_problem();
        _test_circle_problem.set_maximum_circle_count(num_static_circles == 0? 16 : num_static_circles);

        console.log("\n***Creating a dummy problem *** ");
        bool isfinished = false;
        uint32 iterations = 0;
        
        while(isfinished == false)
        {
            isfinished = _test_circle_problem.insert_new_circle();
            iterations++;
        }

        console.log("\n=> Problem created in ", iterations, " iterations.");
    }

    function calc_solution_signature(
        uint256 private_key, uint256 islandID, int64 cx, int64 cy, int64 radius
    ) internal returns(uint8, bytes32, bytes32) // (uint8 parity_v, bytes32 sign_r, bytes32 sign_s)
    {
        bytes32 circle_island_hash = randao.digital_record_signature_helper(islandID, cx, cy, radius);

        // obtain signature for new record
        bytes32 eth_digest = MessageHashUtils.toEthSignedMessageHash(circle_island_hash);// adapt to Ethereum signature format

        return vm.sign(private_key, eth_digest); // uint8 parity_v, bytes32 sign_r, bytes32 sign_s)

    }

    function _print_record_insertion_info(
        VRFCircle memory test_circle, uint8 parity_v, bytes32 sign_r, bytes32 sign_s) internal view
    {
        string[] memory strfields = new string[](6);
        strfields[0] = Strings.toString(uint(int(test_circle.x)));
        strfields[1] = Strings.toString(uint(int(test_circle.y)));
        strfields[2] = Strings.toString(uint(int(test_circle.radius)));
        strfields[3] = Strings.toHexString(uint(sign_r));
        strfields[4] = Strings.toHexString(uint(sign_s));
        strfields[5] = Strings.toHexString(uint(parity_v));

        console.log("-> * Test Circle = [x:", strfields[0]);
        console.log(", y:", strfields[1]);
        console.log(", radius:", strfields[2], "]");
        console.log("-> * With Signature = [sign_r:", strfields[3]);
        console.log(", sign_s:", strfields[4]);
        console.log(", parity:", strfields[5], "]");
    }

    function _insert_signed_record(
        uint256 islandID,
        address addr_owner,
        uint256 privk_owner,
        uint256 storage_fee,
        VRFCircle memory test_circle
    ) internal returns(uint256)
    {
        (uint8 parity_v, bytes32 sign_r, bytes32 sign_s) = calc_solution_signature(
            privk_owner, islandID, test_circle.x, test_circle.y, test_circle.radius);


        _print_record_insertion_info(test_circle, parity_v, sign_r, sign_s);		

        uint256 new_recordID = uint256(0);

        if(storage_fee == VRF_FEE_PROBLEM_SOLVING) //(campaign_status == eVRF_CAMPAIGN_STATUS.VRFCAMPAIGN_PROCESSING_PROBLEM)
        {
            console.log("\n ->Attempting to insert with contribution to problem solving...");
            new_recordID = randao.insert_record_solving_own(islandID, addr_owner, sign_r, sign_s, parity_v);
        }
        else if(storage_fee == VRF_FEE_BONUS)
        {
            console.log("\n ->Attempting to insert with bonus ...");
            new_recordID = randao.insert_record_bonus_own(islandID, addr_owner, sign_r, sign_s, parity_v);
        }
        else
        {
            console.log("\n ->Attempting to insert paying ", storage_fee, " ...");
            if(addr_owner.balance < storage_fee)
            {
                console.log("\n *** Island ", islandID, " don't have enough funds!!**\n");
                return uint256(0);
            }

            

            new_recordID = randao.insert_record_own{value:storage_fee}(
                islandID, addr_owner, sign_r, sign_s, parity_v
            );
        }

        return new_recordID;
    }

    function _insert_record_for_island(
        uint256 islandID, address addr_owner, uint256 privk_owner, 
        VRFCircleProblemSnapshot memory problem_dummy,
        uint256 seed_rng
    ) internal returns(uint256)
    {
        ( , uint32 island_index, uint256 storage_fee) = randao.suggested_record_indexparams(islandID);
                
        if(island_index == INVALID_INDEX32)
        {
            console.log("\n *** Island ", islandID, " is NOT allowed to insert records!!**\n");
            return seed_rng;
        }

        console.log("\n ** Generating circle for Island ", islandID);

        console.log("-> With seed ", seed_rng);

        uint32 max_iterations = 100;

        (VRFCircle memory test_circle, uint32 circle_numiterations, uint256 new_seed_rng) =
        VRFCircleProblemLib.generate_rnd_test_valid_circle(seed_rng, problem_dummy, max_iterations);

        console.log("\n -> Circle generated in ", circle_numiterations," iterations!");
        console.log("-> New updated seed ", new_seed_rng);

        if(test_circle.radius <= int64(0))
        {
            console.log("\n -> *** Cannot found circle. Max of iterations exceeded!! ");
            return new_seed_rng;
        }
        

        console.log("\n -> Attempting to insert circle for island ", islandID);		

        uint256 new_recordID = _insert_signed_record(islandID, addr_owner, privk_owner, storage_fee, test_circle);
        if(new_recordID == uint256(0)) 
        {
            return new_seed_rng;
        }

        console.log("\n->** Inserted New Record ", new_recordID, " // with index=", island_index);

        _records_solutions[new_recordID] = test_circle;

        _records_x_island.insert(islandID, new_recordID);        

        return new_seed_rng;
    }

    function _insert_records(uint32 records_x_island) internal
    {
        
        VRFCircleProblemSnapshot memory problem_dummy = _test_circle_problem.circle_problem_snapshot();
        uint256 seed_rng = _test_circle_problem.fetch_last_seed();
        console.log(
            "\n\n**** Generating ", 
            (records_x_island*_num_keys*_islands_x_address_count),
            " new records at campagin", randao.current_campaignID()
        );

        uint256 islandID = uint256(1);
        for(uint32 i = 0; i < _num_keys; i++)
        {
            address addr_owner =  _address_set[i];
            uint256 privk_owner =  _private_keys_set[i];

            for(uint32 j = 0; j < _islands_x_address_count; j++)
            {
                for(uint32 r = 0; r < records_x_island; r++)
                {
                    seed_rng = _insert_record_for_island(islandID, addr_owner, privk_owner, problem_dummy, seed_rng);
                }

                islandID++;
            }			
        }
    }
    

    function test0RecordSignature() public {
        
        create_keys(8);
        // set balance        
        vm.deal(_address_set[0], 1000 ether);
        vm.deal(_address_set[1], 1000 ether);
        vm.deal(_address_set[2], 1000 ether);

        // transfer funds        
        vm.deal(address(this), 1000 ether);

        // Create Islands
        create_islands(2);
        
        // create tasks
        create_tasks(10);

        // generate private key and insert record
        uint256 test_island = uint256(1);
        int64 cx = 236223201280;
        int64 cy = 24696061952;
        int64 radius = 5570035712;

        (uint8 parity_v, bytes32 sign_r, bytes32 sign_s) = calc_solution_signature(_private_keys_set[0], test_island, cx,cy,radius);

        // insert new record
        uint256 newrecord1 = randao.insert_record_own{value:VRF_RECORD_STORAGE_FEE}(test_island, _address_set[0], sign_r, sign_s, parity_v);

        // test record signature
        bool isvalid = randao.is_valid_record_signature(newrecord1, _address_set[0], cx, cy, radius);

        assertEq(isvalid, true);
    }

    struct TestProblemConfig
    {
        uint32 num_accounts;
        uint32 problem_static_circles;
        uint32 num_tasks;
        uint32 islands_x_account;
    }

    function _start_problem_config(TestProblemConfig memory config) internal
    {
        create_keys(config.num_accounts);
        create_test_problem(config.problem_static_circles);

        // set balance
        for(uint32 i = 0; i < _num_keys; i++)
        {
            vm.deal(_address_set[i], 1000 ether);
        }
        
        // transfer funds        
        vm.deal(address(this), 1000000 ether);

        // Create Islands
        create_islands(config.islands_x_account);
        
        // create tasks
        create_tasks(config.num_tasks);
    }

    function test1CircleCreation() public {
        TestProblemConfig memory prob_config = TestProblemConfig({
            num_accounts:8,
            problem_static_circles:32,
            num_tasks:8,
            islands_x_account:3
        });

        _start_problem_config(prob_config);

        _insert_records(2);
    }

    
}
