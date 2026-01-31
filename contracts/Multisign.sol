// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


contract MultiSign {

    struct Account {
        uint256 accountId;
        address AccountCreator;
        mapping(address => bool) verifiedOwners;
        uint256 balance;
        address[] bindAddress;
    }
    struct Sign {
        address[] Signers;
        mapping(address => bool) addressSigned;

    }

    uint256 nextId;
    mapping(uint256 => Account) accounts;

    constructor (){
        nextId = 1;
    }

    function createMultiSignAccount() external {
        Account storage NewAccount = accounts[nextId];
        NewAccount.accountId = nextId;
        NewAccount.AccountCreator = msg.sender;
        NewAccount.balance = 0;
        NewAccount.bindAddress = new address[](1);
        NewAccount.bindAddress[0] = msg.sender;
        NewAccount.verifiedOwners[msg.sender] = true;
        nextId++;
    }

    function addSignerToAccount() external{
        
    }
}