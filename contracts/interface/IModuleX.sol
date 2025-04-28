// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IModuleX
{
    function getCREDIAddress() external view returns(address);

    function getxCREDIAddress() external view returns(address);

    function getStakesCount() external view returns(uint);
    
    function calculateReward(uint stake_amount) external returns(uint);

    function stake(uint96 lock_period, uint amount) external returns(uint stake_id, uint xCREDI_reward);

    function claim(uint stake_id) external returns(uint xCREDI_reward);

}
