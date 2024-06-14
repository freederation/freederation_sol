//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./VRFCircleProblem.sol";

interface IVRFLeadboard is IERC165
{
    /// Attributes
    function first_place() external view returns(uint256);
    function second_place() external view returns(uint256);
    function third_place() external view returns(uint256);

    function first_pk_owner() external view returns(address);
    function second_pk_owner() external view returns(address);
    function third_pk_owner() external view returns(address);

    function first_circle() external view returns(VRFCircle memory);
    function second_circle() external view returns(VRFCircle memory);
    function third_circle() external view returns(VRFCircle memory);

    /**
     * Reset the leadboard assining 0 to positions
     */
    function reset_leader_board() external;

    /**
    * Return position on the leaderboard.
    * Returns the Leaderboard ranking (1 -> first place; 2 -> second; 3 -> third).
    * Returns 0 if proposal couldn't be ranked. 
    */
    function insert_lb_candidate(uint256 record_candidate, address record_pk_owner, int64 cx, int64 cy, int64 radius) external returns(int32);


    function generate_seed_rnd(uint256 base_rnd_number) external view returns(uint256);
}


contract VRFLeadboard is IVRFLeadboard, ERC165, FREE_Controllable 
{
    /// First place leadboard record. 0 if not assigned yet
    uint256 private _first_place;
    /// second place leadboard record. 0 if not assigned yet
    uint256 private _second_place;
    /// third place leadboard record. 0 if not assigned yet
    uint256 private _third_place;

    address private _first_pk_owner;	
    address private _second_pk_owner;
    address private _third_pk_owner;

    VRFCircle private _first_circle;
    VRFCircle private _second_circle;
    VRFCircle private _third_circle;

    constructor(address initialOwner) FREE_Controllable(initialOwner)
    {
        _first_place = 0;
        _second_place = 0;
        _third_place = 0;
        _first_pk_owner = address(0);
        _second_pk_owner = address(0);
        _third_pk_owner = address(0);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IVRFLeadboard).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function first_place() external view virtual override returns(uint256)
    {
        return _first_place;
    }

    function second_place() external view virtual override returns(uint256)
    {
        return _second_place;
    }

    function third_place() external view virtual override returns(uint256)
    {
        return _third_place;
    }

    function first_pk_owner() external view virtual override returns(address)
    {
        return _first_pk_owner;
    }

    function second_pk_owner() external view virtual override  returns(address)
    {
        return _second_pk_owner;
    }

    function third_pk_owner() external view virtual override returns(address)
    {
        return _third_pk_owner;
    }

    function first_circle() external view virtual override returns(VRFCircle memory)
    {
        return _first_circle;
    }

    function second_circle() external view virtual override returns(VRFCircle memory)
    {
        return _second_circle;
    }

    function third_circle() external view virtual override returns(VRFCircle memory)
    {
        return _third_circle;
    }

       function reset_leader_board() external virtual override onlyOwner
    {
        _first_place = 0;
        _second_place = 0;
        _third_place = 0;
        _first_pk_owner = address(0);
        _second_pk_owner = address(0);
        _third_pk_owner = address(0);
    }

    function _lb_move_first_to_second() internal
    {
        _third_place = _second_place;
        _third_pk_owner = _second_pk_owner;
        _third_circle.x = _second_circle.x;
        _third_circle.y = _second_circle.y;
        _third_circle.radius = _second_circle.radius;

        _second_place = _first_place;
        _second_pk_owner = _first_pk_owner;
        _second_circle.x = _first_circle.x;
        _second_circle.y = _first_circle.y;
        _second_circle.radius = _first_circle.radius;
    }


    function _lb_move_second_to_third() internal
    {
        _third_place = _second_place;
        _third_pk_owner = _second_pk_owner;
        _third_circle.x = _second_circle.x;
        _third_circle.y = _second_circle.y;
        _third_circle.radius = _second_circle.radius;
    }


    /**
    * Return position on the leaderboard.
    * Returns the Leaderboard ranking (1 -> first place; 2 -> second; 3 -> third).
    * Returns 0 if proposal couldn't be ranked. 
    */
    function insert_lb_candidate(
        uint256 record_candidate, address record_pk_owner, int64 cx, int64 cy, int64 radius)
    external virtual override onlyOwner returns(int32)
    {
        if(_first_place == 0)
        {
            // a winner by default
            _first_place = record_candidate;
            _first_pk_owner = record_pk_owner;
            _first_circle.x = cx;
            _first_circle.y = cy;
            _first_circle.radius = radius;
            return 1;
        }

        if(_first_circle.radius < radius)
        {
            // its a winner
            _lb_move_first_to_second();
            _first_place = record_candidate;
            _first_pk_owner = record_pk_owner;
            _first_circle.x = cx;
            _first_circle.y = cy;
            _first_circle.radius = radius;
            return 1;
        }

        if(_second_place == 0)
        {
            _second_place = record_candidate;
            _second_pk_owner = record_pk_owner;
            _second_circle.x = cx;
            _second_circle.y = cy;
            _second_circle.radius = radius;
            return 2;
        }
        else if(_second_circle.radius < radius) 
        {
            _lb_move_second_to_third();
            _second_place = record_candidate;
            _second_pk_owner = record_pk_owner;
            _second_circle.x = cx;
            _second_circle.y = cy;
            _second_circle.radius = radius;
            return 2;
        }


        if(_third_place == 0 || _third_circle.radius < radius)
        {
            _third_place = record_candidate;
            _third_pk_owner = record_pk_owner;
            _third_circle.x = cx;
            _third_circle.y = cy;
            _third_circle.radius = radius;
            return 3;
        }

        return 0;
    }


    function generate_seed_rnd(uint256 base_rnd_number) external view virtual override returns(uint256)
    {		
        if(_first_place == 0)
        {
            return uint256(0);
        }

        // for storing results
        bytes32 [4] memory retbytes = [bytes32(0), bytes32(0), bytes32(0), bytes32(0)];
                
        if(_second_place == 0)
        {
            // calculate random with only the winner
            retbytes[0] = keccak256(abi.encodePacked(base_rnd_number, _first_place));
            retbytes[1] = keccak256(abi.encodePacked(
                _first_circle.x, _first_circle.y,
                _first_circle.radius, _first_pk_owner));			
        }
        else
        {         
            
            if(_third_place == 0)
            {
                retbytes[0] = keccak256(abi.encodePacked(base_rnd_number, _first_place, _second_place));

                retbytes[1] = keccak256(abi.encodePacked(
                    _first_circle.x, _first_circle.y, _first_circle.radius, _second_pk_owner)
                );

                retbytes[2] = keccak256(abi.encodePacked(
                    _second_circle.x, _second_circle.y,
                    _second_circle.radius, _first_pk_owner));
            }
            else
            {
                retbytes[0] = keccak256(abi.encodePacked(base_rnd_number, _first_place, _second_place, _third_place));

                retbytes[1] = keccak256(abi.encodePacked(
                    _first_circle.x, _first_circle.y,
                     _first_circle.radius, _third_pk_owner));

                retbytes[2] = keccak256(abi.encodePacked(
                    _second_circle.x, _second_circle.y,
                    _second_circle.radius, _first_pk_owner));

                retbytes[3] = keccak256(abi.encodePacked(
                    _third_circle.x, _third_circle.y,
                    _third_circle.radius, _second_pk_owner));
            }
        }

        // configure new seed
        return uint256(keccak256(abi.encodePacked(retbytes)));
    }

}

