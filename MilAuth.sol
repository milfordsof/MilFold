//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface MilAuthInterface {

    function isDev(address _who) external view returns (bool);

    function checkGameRegister(address _gameAddr) external view returns (bool);

}

contract MilAuth is MilAuthInterface {

    mapping(address => bool) private registeredGames_;         // (addr => registered) returns game registered or not

    mapping(address => bool) public devAdmin_;

    address public owner_;



    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // CONSTRUCTOR
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    constructor() {
        owner_ = msg.sender;
        devAdmin_[msg.sender] = true;
    }


    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // MODIFIERS
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

    modifier onlyOwner(){
        require(msg.sender == owner_, "onlyOwner failed - msg.sender is not a owner");
        _;
    }

    /**
     * @dev register game contract by address
     * @param _gameAddr game contract's address
     */
    function registerGame(address _gameAddr) external onlyOwner {
        require(address(_gameAddr) != address(0), "gameAddr is invalid");
        registeredGames_[_gameAddr] = true;
    }

    function isDev(address _who) external view returns (bool) {
        return (owner_ == _who);
    }

    function checkGameRegister(address _gameAddr) external view returns (bool) {
        return (registeredGames_[_gameAddr]);
    }

    function changeOwner(address _newOwner) external onlyOwner {
        owner_ = _newOwner;
    }

    function setDevAdmin(address _dev,bool flag) external onlyOwner{
        require(address(_dev) != address(0), "gameAddr is invalid");
        devAdmin_[_dev] = flag;
    }
}
