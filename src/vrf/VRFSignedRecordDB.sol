//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./VRFCircleProblem.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

// VRF state flags
uint32 constant VRF_RECORD_STATE_AVAILABLE = INVALID_INDEX32;
uint32 constant VRF_RECORD_STATE_REVEALED = VRF_RECORD_STATE_AVAILABLE - 1;
uint32 constant VRF_RECORD_STATE_FAULTED = VRF_RECORD_STATE_AVAILABLE - 2;

error ErrVRF_CannotCommitProposalsAtThisMoment();

error ErrVRF_CannotRevealProposalsAtThisMoment();

error ErrVRF_RecordHasAlreadySpent(uint256 recordID);

error ErrVRF_RecordNotaProposal(uint256 recordID);

error ErrVRF_RecordCampaignInconsistency(uint256 recordID);

error ErrVRF_RecordCommittedCampaignEarly(uint256 recordID);

error ErrVRF_InvalidRecordOwnerAddress(uint256 recordID, address owner);

error ErrVRF_RecordNotAssignedToIsland(uint256 recordID);


struct VRFSignedRecord
{
    uint256 island_tokenID;/// Island holds reputation
   
    address pk_owner;/// public key of the owner of the Island   
   
    uint256 campaingID;// Current campaing where this record has been originated
    uint32 island_campaign_index;// index on the campaign where the island has commited this record
   
    /**
    * Index of the proposal. Also reveals the state of the record when being played:
    * - VRF_RECORD_STATE_AVAILABLE indicates that this record hasn't been commited for proposals yet.
    * - VRF_RECORD_STATE_REVEALED indicates that this record has been used for random generation.
    * - VRF_RECORD_STATE_FAULTED indicates that this record has been proposed but faulted on the revelation phase.
    */
    uint32 proposal_index;

    bytes32 signature_r;// signature param point of the message
    bytes32 signature_s;// signature of the message
    uint8 parity_v;/// Parity of the signature
}

library VRFSignedRecordLib
{
    /**
    * This method defines the way of how signatures are created for VRF, based on campaign parameters.
    */
    function calc_record_params_buffer(uint256 islandID, uint256 campaingID, uint32 island_campaign_index, int64 cx, int64 cy, int64 radius) internal pure returns(bytes memory)
    {
        return abi.encode(islandID, campaingID, island_campaign_index, cx,  cy, radius);
    }

       /**
    * This method defines the way of how signatures are created for VRF, based on campaign parameters.
    */
    function calc_record_params_hash(uint256 islandID, uint256 campaingID, uint32 island_campaign_index, int64 cx, int64 cy, int64 radius) internal pure returns(bytes32)
    {
        return keccak256(calc_record_params_buffer(islandID, campaingID, island_campaign_index, cx,  cy, radius));
    }
}

interface IVRFSignedRecordDB is IERC165
{
    function get_current_recordID() external view returns(uint256);
    function available_records() external view returns(uint256);

    function get_record_island(uint256 recordID) external view returns (uint256);
    function get_record_owner(uint256 recordID) external view returns (address);
    function get_record_campaign(uint256 recordID) external view returns (uint256);
    function get_record_island_campaign_index(uint256 recordID) external view returns (uint32);
    function get_record_proposal_index(uint256 recordID) external view returns (uint32);
    function get_record_info(uint256 recordID) external view returns(VRFSignedRecord memory);	

    function record_available_for_commitment(uint256 recordID, uint256 current_campaignID) external view returns (bool);


    /**
     * returns the newly generated record
     */
    function insert_new_record(
        uint256 islandID, address pk_owner, uint256 campaignID, uint32 island_campaign_index, 
        bytes32 signature_r, bytes32 signature_s, uint8 parity_v) external returns(uint256);

    
    /**
     * This method is called within a proposal commitment.
     * It returns a tuple with the following information:
     * (uint32 proposal_index, uint256 islandID, address owner_address, uint256 campaignID )
     */
    function get_record_commit_proposal_fields(uint256 recordID) external view returns(uint32, uint256, address, uint256);


    /**
     * This method is called when revealing a proposal
     * It returns a tuple with the following information:
     * (uint32 proposal_index, uint256 islandID )
     */
    function get_record_reveal_proposal_fields(uint256 recordID) external view returns(uint32, uint256);
    /**
     * When updating a signed record, it no longer becomes available.
     * This decrements the _available_records variable.
     */
    function record_commit_proposal(uint256 recordID, uint32 index) external;

    /**
     * This just changes the proposal index.
     */
    function set_record_proposal_index(uint256 recordID, uint32 index) external;

    /**
     * This is called after the record has commited a proposal, Changes the proposal index.
     */
    function update_record_revelation_status(uint256 recordID, bool success) external;


    /**
     * This method raises a reverting error if the record is not available for revelation.
     * Also if address doesn't match with the owner.
     */
    function assert_proposal_revelation_status(uint256 recordID, address pk_owner) external;

    /**
     * Test record signature revelation. Read only.
     */
    function is_valid_record_signature(uint256 recordID, address pk_owner, int64 cx, int64 cy, int64 radius) external view returns(bool);	
}

contract VRFSignedRecordDB is IVRFSignedRecordDB, ERC165, FREE_Controllable 
{
    /**
    * A one-based Array set which matchs the Island VRF record ID with the record information
    */
    mapping(uint256 => VRFSignedRecord) private _signed_records;

    /**
    * A consecutive index for records. Starts with 1.
    */ 
    uint256 private _current_recordID;
    uint256 private _available_records;

    constructor(address initialOwner) FREE_Controllable(initialOwner)
    {
        _current_recordID = uint256(0);
        _available_records = uint256(0);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IVRFSignedRecordDB).interfaceId || super.supportsInterface(interfaceId);
    }

    function get_current_recordID() external view virtual override returns(uint256)
    {
        return _current_recordID;
    }

    function available_records() external view virtual override returns(uint256)
    {
        return _available_records;
    }

    function get_record_island(uint256 recordID) external view virtual override returns (uint256)
    {
        VRFSignedRecord storage fetch_record = _signed_records[recordID];
        return fetch_record.island_tokenID;
    }

    function get_record_owner(uint256 recordID) external view virtual override returns (address)
    {
        VRFSignedRecord storage fetch_record = _signed_records[recordID];
        return fetch_record.pk_owner;
    }

    function get_record_campaign(uint256 recordID) external view virtual override returns (uint256)
    {
        VRFSignedRecord storage fetch_record = _signed_records[recordID];
        return fetch_record.campaingID;
    }

    function get_record_island_campaign_index(uint256 recordID) external view virtual override returns (uint32)
    {
        VRFSignedRecord storage fetch_record = _signed_records[recordID];
        return fetch_record.island_campaign_index;
    }

    function get_record_proposal_index(uint256 recordID) external view virtual override returns (uint32)
    {
        VRFSignedRecord storage fetch_record = _signed_records[recordID];
        return fetch_record.proposal_index;
    }

    function get_record_info(uint256 recordID) external view virtual override returns(VRFSignedRecord memory)
    {
        return  _signed_records[recordID];
    }

    function record_available_for_commitment(uint256 recordID, uint256 current_campaignID) external view virtual override returns (bool)
    {
        if (recordID > _current_recordID) return false;
        VRFSignedRecord storage recordobj = _signed_records[recordID];
        if (recordobj.proposal_index != VRF_RECORD_STATE_AVAILABLE) return false;
        return recordobj.campaingID < current_campaignID;
    }

    function insert_new_record(
        uint256 islandID, address pk_owner, uint256 campaignID, uint32 island_campaign_index, 
        bytes32 signature_r, bytes32 signature_s, uint8 parity_v)
        external virtual override onlyOwner returns(uint256)
    {
        // increment record index
        _current_recordID++;
        _available_records++;

        VRFSignedRecord storage newrecord_obj = _signed_records[_current_recordID];

        newrecord_obj.island_tokenID = islandID;
        newrecord_obj.pk_owner = pk_owner;
        newrecord_obj.campaingID = campaignID;
        newrecord_obj.island_campaign_index = island_campaign_index;
        newrecord_obj.proposal_index = VRF_RECORD_STATE_AVAILABLE;
        newrecord_obj.signature_r = signature_r;
        newrecord_obj.signature_s = signature_s;
        newrecord_obj.parity_v = parity_v;
        return _current_recordID;
    }

    /**
     * This method is called within a proposal commitment.
     * It returns a tuple with the following information:
     * (uint32 proposal_index, uint256 islandID, address owner_address, uint256 campaignID )
     */
    function get_record_commit_proposal_fields(uint256 recordID)
    external view virtual override
    returns(uint32, uint256, address, uint256)
    {
        VRFSignedRecord storage record_obj = _signed_records[recordID];
        return (
            record_obj.proposal_index,
            record_obj.island_tokenID,
            record_obj.pk_owner,
            record_obj.campaingID
        );
    }

    function get_record_reveal_proposal_fields(uint256 recordID) 
    external view virtual override returns(uint32, uint256)
    {
        VRFSignedRecord storage record_obj = _signed_records[recordID];
        return (record_obj.proposal_index,record_obj.island_tokenID);
    }

    /**
     * When updating a signed record, it no longer becomes available.
     */
    function record_commit_proposal(uint256 recordID, uint32 index) external virtual override onlyOwner
    {
        VRFSignedRecord storage record_obj = _signed_records[recordID];
        record_obj.proposal_index = index;
        _available_records--;
    }

    function set_record_proposal_index(uint256 recordID, uint32 index) external virtual override onlyOwner
    {
        VRFSignedRecord storage record_obj = _signed_records[recordID];
        record_obj.proposal_index = index;
    }

    function update_record_revelation_status(uint256 recordID, bool success) external virtual override onlyOwner
    {
        VRFSignedRecord storage record_obj = _signed_records[recordID];
        record_obj.proposal_index = success ? VRF_RECORD_STATE_REVEALED : VRF_RECORD_STATE_FAULTED;
    }

    /**
     * This method raises a reverting error if the record is not available for revelation.
     * Also if address doesn't match with the owner.
     */
    function assert_proposal_revelation_status(uint256 recordID, address pk_owner) external virtual override onlyOwner
    {
        if (recordID == uint256(0) || pk_owner == address(0)) {
            revert Err_InvalidAddressParams();
        }

        VRFSignedRecord storage recordobj = _signed_records[recordID];

        if (recordobj.pk_owner != pk_owner) 
        {
            revert ErrVRF_InvalidRecordOwnerAddress(recordID, pk_owner);
        }
        // Does this record already present in the reveal process?
        uint32 proposal_index = recordobj.proposal_index;
        if (
            proposal_index == VRF_RECORD_STATE_AVAILABLE ||
            proposal_index == VRF_RECORD_STATE_REVEALED ||
            proposal_index == VRF_RECORD_STATE_FAULTED
        ) 
        {
            revert ErrVRF_RecordNotaProposal(recordID);
        }
    }

    /**
     * Test record signature revelation. Read only.
     */
    function is_valid_record_signature(
            uint256 recordID, address pk_owner,
            int64 cx, int64 cy, int64 radius) 
            external view virtual override returns(bool)
    {
        VRFSignedRecord storage recordobj = _signed_records[recordID];

        if(recordobj.pk_owner != pk_owner || pk_owner == address(0)) return false;

        bytes32 chash = keccak256(
            VRFSignedRecordLib.calc_record_params_buffer(
                recordobj.island_tokenID,
                recordobj.campaingID,
                recordobj.island_campaign_index,
                cx, cy, radius
            )
        );
          
        bytes32 eth_digest = MessageHashUtils.toEthSignedMessageHash(chash);// adapt to Ethereum signature format

        (address recovered, ECDSA.RecoverError error, ) = ECDSA.tryRecover(
            eth_digest, 
            recordobj.parity_v,
            recordobj.signature_r,
            recordobj.signature_s
        );

        if (error == ECDSA.RecoverError.NoError && recovered == pk_owner) 
        {
            return true;
        }
        return false;
    }
}