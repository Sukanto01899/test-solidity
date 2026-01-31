// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


contract MultiSign {
    address[] owners;
    mapping(address => bool) realSigner;
    address owner;
    uint256 nextId;

    constructor (){
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not owner");
        _;
    }

    function addSigner(address _signer) external onlyOwner() {
        require(!realSigner[_signer], "Signer already added!");

        owners.push(_signer);
        realSigner[_signer] = true;
    }

   

    struct Withdraw{
        uint256 id;
        bool isCompleted;
        uint256 amount;
        mapping(address => bool) signedBy;
        address createdBy;
        address to;
    }
    mapping(uint256 => Withdraw) withdrawals;

    function InitWithdraw(uint256 _amount, address _to) external{
        require(realSigner[msg.sender], "You are not signer!");
        require(address(this).balance >= _amount, "Insufficient balance");

        withdrawals[nextId].id = nextId;
        withdrawals[nextId].isCompleted = false;
        withdrawals[nextId].amount = _amount;
        withdrawals[nextId].createdBy = msg.sender;
        withdrawals[nextId].to = _to;

        nextId++;
    }


    function addSign(uint256 _withdrawId) public{

        Withdraw storage getWithdrawals = withdrawals[_withdrawId];
        address sign = msg.sender;

        require(realSigner[sign], "Not valid signer");
        require(!getWithdrawals.signedBy[sign], "Already signed");
    }
}