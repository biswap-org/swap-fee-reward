pragma solidity 0.6.6;

contract MsgSender {

    function rewardBalance() public view returns(address){
        return msg.sender;
    }

}