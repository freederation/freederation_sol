//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;
import "openzeppelin-contracts/contracts/access/Ownable.sol";


abstract contract FREE_Controllable is Ownable {
    
    event ControlAssigned(address indexed newController);


    mapping(address => bool) private _auth_controllers;

    constructor(address initialOwner) Ownable(initialOwner) {
        _auth_controllers[initialOwner] = true;
    }

    /**
     * Override from Owner, checks if also the controller have access
     * @dev Throws if the sender is not the owner nor the controller.
     */
    function _checkOwner() internal view virtual override {
        bool has_control = _auth_controllers[_msgSender()];
        require(has_control == true , "Ownable: caller is not the controller");
    }

    /**
     * @dev Returns the address of the current controller.
     */
    function controllerRole() public view virtual returns (bool) 
    {
        return _auth_controllers[_msgSender()];
    }

    
    /**
     * Public function for assigning control on this class. Only owner could grant the control access
     */
    function assignControllerRole(address newController) public virtual
    {
        require(owner() == _msgSender(), "Only Owner could assign the controller");
        _transferControlRole(newController);
    }	

    /**
     * @dev Transfers control role of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferControlRole(address newController) internal {        
        address _role = newController == address(0) ? owner() : newController;
        _auth_controllers[_role] = true;

        emit ControlAssigned(newController);
    }   
    
}
