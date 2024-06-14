import { expect, assert } from "chai";
import { FixedNumber, ethers, BigNumber} from "ethers";
import {FREE_RANDAO, FREE_RANDAO__factory, VRFController,
        VRFCircleProblem, VRFCircleProblem__factory} from "../typechain-types";
import {stringify} from "json5";
import {simulation} from "./util/VRFCircleProblem";
import {AccountInventory} from "./util/AccountInventory";



/**
 * This Test needs a local running blockchain network, as it requires an existing wallet address
 */

const WALLET_ADDRESS_PK = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const NETWORK_ADDRESS_URL = "http://127.0.0.1:8545/";
const USE_PRIVATE_KEY = false;
const TARGET_WALLET0 = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8";

interface IslandEntry
{
    address:string;
    islandID:BigNumber;
}

let generate_islands_fn = async function(island_ids:Array<IslandEntry>, contract:FREE_RANDAO){
    
    let tasks = [];
    for(let obj of island_ids)
    {
        let task = await contract.register_island(obj.islandID, obj.address);
        assert(task != null);		
        tasks.push(task.wait());
    }

    return Promise.all(tasks).then((results) => {
        for(let rs of results)
        {
            assert(rs != null);
            console.log("\n *** Island Created: \n\n", stringify(rs));
        }
    });
};

let generate_islands_fn1 = async function(island_ids:Array<IslandEntry>, contract:FREE_RANDAO){
    
    let tasks = island_ids.map(
        (obj:IslandEntry) => {
            return contract.register_island(obj.islandID, obj.address).then(txres => txres.wait());
        }
    );
    
    let txresults = Promise.all(tasks).then(
        results => {
            for(let rs of results)
            {
                assert(rs != null);
                console.log("\n *** Island Created: \n\n", stringify(rs));
            }
        }
    );	
    
};

interface CampaignEntry
{
    task:BigNumber;
    payment:PayableOverrides;
}

let generate_campaign_creations_fn = async function(campaign_set:Array<CampaignEntry>, contract:FREE_RANDAO){
    
    let tasks = [];
    for(let obj of campaign_set)
    {
        let task = await contract.create_new_task(obj.task, obj.payment);
        assert(task != null);		
        tasks.push(task.wait());
    }

    let eventhandle = contract.filters.NewCampaign;

    return Promise.all(tasks).then((results) => {

        let event_tasks = [];

        for(let rs of results)
        {
            assert(rs != null);
            console.log("\n *** Campaign Transaction: \n\n", stringify(rs));

            event_tasks.push(contract.queryFilter(eventhandle, rs.blockNumber, rs.blockNumber));
        }

        return Promise.all(event_tasks).then((events_set) => {
            for(const evlist of events_set)
            {
                for(const ev of evlist)
                {
                    console.log("\n *** Campaign Created: \n\n", stringify(ev.args));
                }				
            }
        });

    });
};
////////////////////////////// Testing ////////////////////////////

describe("FREE_RANDAO", function () {
    // connect to network
    let provider:ethers.providers.Provider|null = null;

    let signer:ethers.Signer|null = null;

    let network = null;

    before(async function(){

        try{
            provider = new ethers.providers.JsonRpcProvider(NETWORK_ADDRESS_URL);
        }catch(e){
            console.log("Error Provider instance ", e);
            provider = null;
        }

        assert(provider != null);

        console.log("Check if connected:\n");    

        try{
            network = await provider?.getNetwork();
        }catch(e){
            network = null;
            console.log("No network connected!!");
            console.log("|------------------------------------|");
            console.log(e);
            console.log("|------------------------------------|");
        }

        assert(network != null);

        // list accounts
        console.log("List accounts:\n");

        let accounts = await provider?.listAccounts();

        console.log(accounts);    

        try{
            if(USE_PRIVATE_KEY){
                signer = new ethers.Wallet(WALLET_ADDRESS_PK, provider);
            }
            else{
                signer = provider.getSigner(0);
            }

        }catch(e){
            console.log("Cannot initialize Wallet signer.")
            console.log("|------------------------------------|");
            console.log(e);
            console.log("|------------------------------------|");
        }

        assert(signer != null);

        let signer_address:string = null;

        try{
            signer_address = await signer?.getAddress();
        }catch(e){
            console.log("Cannot connect wallet with address.")
            console.log("|------------------------------------|");
            console.log(e);
            console.log("|------------------------------------|");
        }

        assert(signer_address != null);

        console.log("connected to signer with address: ", signer_address);

        let balance:BigNumber = await signer.getBalance();

        console.log("Account balance : ", balance.toString());

        assert(balance.isZero() == false);

    });
    

    ///////////////////// Test Campaign registering /////////////////////

    it("Test Campaigns", async function () {

        
        console.log("\n\n|-----------------INSTANCE CONTRACT -------------------|");

        const FREE_RFac = new FREE_RANDAO__factory(signer);
        const dvrcontract = await FREE_RFac.deploy();
        await dvrcontract.deployed();

        console.log("** Contract FREE_RANDAO deployed with address", dvrcontract.address);

        console.log("|----------------- Obtain 2 addresses -------------------|");

        let account1 = null; let account2 = null;
        let account1_address:string = null; let account2_address:string = null;

        try{

            account1 = provider.getSigner(1);
            account2 = provider.getSigner(2);

        }catch(e)
        {
            console.log("Cannot obtain signers.")
            console.log("|------------------------------------|");
            console.log(e);
            console.log("|------------------------------------|");
        }

        try{

            account1_address = await account1?.getAddress();
            account2_address = await account2?.getAddress();

        }catch(e)
        {
            console.log("Cannot obtain signer addresses.")
            console.log("|------------------------------------|");
            console.log(e);
            console.log("|------------------------------------|");
        }
        
        console.log("Address1: ", account1_address);
        console.log("Address2: ", account2_address);

        console.log("|-----------------Register Island -------------------|");

        let islands_tasks = [
            {islandID:BigNumber.from(1), address: account1_address},
            {islandID:BigNumber.from(2), address: account2_address},
            {islandID:BigNumber.from(3), address: account1_address}
        ];
        
        console.log("\nn|-----------------Transaction info (Island Creations) -------------------|");    
        
        await generate_islands_fn(islands_tasks, dvrcontract);

        console.log("\n\n|-----------------Task Creation -------------------|");

        let campaign_tasks = [
            {
                task:BigNumber.from(664),
                payment:{value: ethers.utils.parseEther("0.08")}
            },
            {
                task:BigNumber.from(574),
                payment:{value: ethers.utils.parseEther("0.18")}
            },
            {
                task:BigNumber.from(116),
                payment:{value: ethers.utils.parseEther("0.101")}
            }
        ];
        
        console.log("\n|-----------------Transaction info (Tasks) -------------------|");
        
        await generate_campaign_creations_fn(campaign_tasks, dvrcontract);

    });
    it("Test Problem Formation", async function () {

        console.log("\n\n|-----------------INSTANCE CircleProblem CONTRACT -------------------|");

        const VRFProblemFac = new VRFCircleProblem__factory(signer);
        
        console.log("** Create seed for circle problem **");

        const rnd_data_bytes = ethers.utils.randomBytes(32);
        const rng_seed = BigNumber.from(rnd_data_bytes);

        console.log("** Seed = ", rng_seed.toHexString());

        const vrfproblem_contract = await VRFProblemFac.deploy(rng_seed);
        await vrfproblem_contract.deployed();

        console.log("** Contract VRFCircleProblem deployed with address", vrfproblem_contract.address);

        let problem_max_circles_count = await vrfproblem_contract.get_maximum_circle_count();

        console.log(`\n|---------------Inser ${problem_max_circles_count} Circles in Problem -------------------|`);
        
        let has_finished = false;
        let num_iterations = 0;
        const insert_eventhandle = vrfproblem_contract.filters.AttemptInsertingCircle;

        do{
            let txres = await vrfproblem_contract.insert_new_circle();
            assert(txres != null);
            await txres.wait();

            let event_buffer = await vrfproblem_contract.queryFilter(insert_eventhandle, txres.blockNumber, txres.blockNumber);

            assert(event_buffer != null && event_buffer.length >= 1);

            has_finished = event_buffer[0].args[0];
            let _circle_count = event_buffer[0].args[1];

            console.log(`Inserion. Finished? ${has_finished}, circles=${_circle_count}`);

            num_iterations++;
        }while(has_finished == false);
        
        console.log(`Finished Problem in ${num_iterations} iterations!!`);
        console.log("\n|-----------------Extract problem information -------------------|\n");

        let problem_snapshot = await vrfproblem_contract.circle_problem_snapshot();

        console.log(stringify(problem_snapshot));

        console.log("\n|----------------- Create Local snapshot -------------------|");

        let client_problem = new simulation.VRFCircleProblem();
        client_problem.config_from_snapshot(problem_snapshot);
        console.log(client_problem.toString());

        console.log("\n|----------------- Generate RND Valid Circle -------------------|");

        let test_circle_info = client_problem.generate_test_circle(rng_seed.toBigInt(), 100);

        console.log("\n\n** Circle generated in ", test_circle_info.num_iterations, " iterations!");
        console.log(`{x:${test_circle_info.circle.x}, y:${test_circle_info.circle.y}, radius:${test_circle_info.circle.radius}}`);
        console.log("** Next seed ", test_circle_info.rng_seed.toString());

        console.log("\n|----------------- Test Circle against contract -------------------|");

        let tx_circlevalid = await vrfproblem_contract.validate_solution(
            BigNumber.from(test_circle_info.circle.x), 
            BigNumber.from(test_circle_info.circle.y),
            BigNumber.from(test_circle_info.circle.radius)
        );

        if(tx_circlevalid == true)
        {
            console.log("YESSS!!!!");
        }

        assert(tx_circlevalid == true);
        
    });
    it("Test Records Signature", async function () {
        
        console.log("\n\n|-----------------INSTANCE CONTRACT AGAIN -------------------|");

        const FREE_RFac2 = new FREE_RANDAO__factory(signer);
        const dvrcontract2 = await FREE_RFac2.deploy();
        await dvrcontract2.deployed();

        console.log("** Contract FREE_RANDAO2 deployed with address", dvrcontract2.address);

        let newbalance:BigNumber = await signer.getBalance();
        console.log("Account balance : ", newbalance.toString());

        // create random accounts

        let account_inventory = new AccountInventory();

        await account_inventory.generate_accounts_and_islands(10, 4, dvrcontract2, provider);

        // verify
        let success_islands = await account_inventory.check_islands_ownership(dvrcontract2);
        assert(success_islands == true);

        // inyect funds
        newbalance = await signer.getBalance();
        console.log("Account balance Before Inyecting funds: ", newbalance.toString());

        await account_inventory.inyect_funds(signer, ethers.utils.parseEther("0.1"));

        newbalance = await signer.getBalance();
        console.log("Account balance After Inyecting funds : ", newbalance.toString());

        // insert records
        await account_inventory.insert_random_records(dvrcontract2);


        // verify records
        console.log("\n|-------------- VERIFYING RECORDS SIGNATURE (local) ---------------|");

        let bval = account_inventory.verify_records_signature();

        if(bval == true)
        {
            console.log("***** All records verified successfully!! **** ")
        }

        console.log("|------------------- --------------------------- ---------------|");

        assert(bval == true);

        // verify records
        console.log("\n|-------------- VERIFYING RECORDS SIGNATURE (DAO) ---------------|");

        bval = await account_inventory.verify_records_signature_on_dao(dvrcontract2);

        if(bval == true)
        {
            console.log("***** All records verified successfully!! **** ")
        }

        console.log("|------------------- --------------------------- ---------------|");

        assert(bval == true);

    });
    it("Just Waiting for fun", async function () {
        let val = 0;
        const fn = new Promise(function(resolve){
            setTimeout(resolve, 2000);
            val = 1;
        });

        await fn;

        expect(val == 1);
    });
});
