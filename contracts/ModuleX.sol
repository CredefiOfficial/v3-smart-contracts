// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/IModuleX.sol";

contract ModuleX is IModuleX, Ownable 
{
    using SafeERC20 for IERC20;

    struct StakeDetails
    {
        address owner;
        uint96 maturity;
        uint stake_amount;
        uint reward_amount;
    }

    bool public stopped = false; 
    uint96 constant public MATURITY = 180 minutes; // 180 days;
    uint immutable private DIFFICULTY; // Initial DIFFICULTY
    uint immutable public DIFFICULTY_INTERVAL;
    IERC20 immutable public CREDI;
    IERC20 immutable public xCREDI;
    
    mapping (uint => StakeDetails) private stakes;
    uint private stakes_count = 1;
    uint public total_staked = 0;
    uint public pending_payments = 0;

    event RewardAdded(uint amount);
    event RewardWithdrawn(address indexed to, uint amount);
    event Staked(address indexed user, uint stake_id, uint96 maturity, uint stake_amount, uint rewards_amount);
    event CREDIWithdrawn(uint stake_id, uint amount);
    event RewardPaid(uint stake_id);
    event Stopped();

    modifier validate_stake(uint stake_id) 
    {
        require(stake_id > 0 && stake_id < stakes_count, "ModuleX:Invalid Stake ID!");
        _;
    }

    constructor(address _credi_addr, address _xcredi_addr, uint _DIFFICULTY, uint _DIFFICULTY_INTERVAL) Ownable(_msgSender())
    { 
        CREDI = IERC20(_credi_addr);
        xCREDI = IERC20(_xcredi_addr);
        DIFFICULTY_INTERVAL = _DIFFICULTY_INTERVAL;
        DIFFICULTY = _DIFFICULTY;
    }
    
    function getCREDIAddress() external view returns(address)
    {
        return address(CREDI);
    }

    function getxCREDIAddress() external view returns(address)
    {
        return address(xCREDI);
    }

    function getStakesCount() external view returns(uint)
    {
        return stakes_count - 1;
    }

    function getStake(uint stake_id) external validate_stake(stake_id) view 
        returns (
        address owner,
        uint maturity,
        uint stake_amount,
        uint reward_amount)
    {
        return (
            stakes[stake_id].owner,
            stakes[stake_id].maturity,
            stakes[stake_id].stake_amount,
            stakes[stake_id].reward_amount);
    }

    function time_now() private view returns(uint96)
    {
        return uint96(block.timestamp);
    }

    function calculateReward(uint stake_amount) public view returns(uint)
    { 
        uint SCALE_FACTOR = 1e18;
        uint curr_total = total_staked + stake_amount;
        uint low_d = total_staked/DIFFICULTY_INTERVAL;
        uint high_d = curr_total/DIFFICULTY_INTERVAL;
        if(low_d == high_d)
        {
            return stake_amount/(low_d + DIFFICULTY);
        }
        else 
        {
            uint low_r = SCALE_FACTOR*((low_d + 1)*DIFFICULTY_INTERVAL - total_staked)/(low_d + DIFFICULTY);
            uint high_r = SCALE_FACTOR*(curr_total - high_d*DIFFICULTY_INTERVAL)/(high_d + DIFFICULTY);
            uint middle_r = 0;
            for(uint i=low_d + 1; i < high_d; i++)
            {
                middle_r += SCALE_FACTOR*DIFFICULTY_INTERVAL/(i + DIFFICULTY);
            }
            return (low_r + middle_r + high_r)/SCALE_FACTOR;
        }
    }

    function getDifficulty() external view returns(uint)
    {
        return total_staked/DIFFICULTY_INTERVAL + DIFFICULTY;
    }

    function stake(uint96 lock_period, uint stake_amount) external returns(uint, uint)
    {
        require(!stopped, "ModuleX:STOPPED!");
        require(stake_amount > 0, "ModuleX:Stake amount must be greater than 0!");
        require(lock_period >= MATURITY, "ModuleX:Use longer lock_period!");
        CREDI.safeTransferFrom(_msgSender(), address(this), stake_amount); 
        uint96 maturity = time_now() + lock_period;
        uint reward_amount = calculateReward(stake_amount);
        uint stake_id = stakes_count;
        stakes[stake_id] = StakeDetails({
            owner: _msgSender(),
            maturity: maturity,
            stake_amount: stake_amount,
            reward_amount: reward_amount
        });
        
        total_staked += stake_amount; 
        pending_payments += reward_amount;
        emit Staked(_msgSender(), stake_id, maturity, stake_amount, reward_amount);
        stakes_count++;
        return(stake_id, reward_amount);
    }

    function claim(uint stake_id) external validate_stake(stake_id) returns(uint)
    {
        StakeDetails storage details = stakes[stake_id];
        require(details.owner == _msgSender(), "ModuleX:Caller is not the owner");
        require(time_now() >= details.maturity, "ModuleX:Early Withdrawal is not permitted!"); 
        require(details.reward_amount > 0, "ModuleX:Nothing to claim");
        uint reward_amount = details.reward_amount;
        xCREDI.safeTransfer(_msgSender(), reward_amount);     
        pending_payments -= reward_amount;
        details.reward_amount = 0; 
        emit RewardPaid(stake_id); 
        return reward_amount;
    }

    function withdrawCREDI(uint stake_id, uint amount) external onlyOwner validate_stake(stake_id)
    {
        require (amount > 0, "ModuleX:amount must be greater than zero!");
        StakeDetails storage details = stakes[stake_id];
        require(time_now() <= details.maturity, "ModuleX:Burnt tokens!"); 
        require(amount <= details.stake_amount, "ModuleX:Insufficient balance!"); 
        CREDI.safeTransfer(_msgSender(), details.stake_amount);
        details.stake_amount -= amount;
        emit CREDIWithdrawn(stake_id, amount);
    }

    function batchWithdrawCREDI(uint[] calldata stake_ids) external onlyOwner
    {
        uint total_amount = 0;
        for(uint i = 0; i < stake_ids.length; i++)
        {
            require(stake_ids[i] < stakes_count, "ModuleX:Invalid Stake ID!");
            StakeDetails storage details = stakes[stake_ids[i]];
            require(time_now() <= details.maturity, "ModuleX:Burnt tokens!");
            total_amount += details.stake_amount;
            details.stake_amount = 0;          
            emit CREDIWithdrawn(stake_ids[i], details.stake_amount);
        }
        require(total_amount > 0, "ModuleX:Total amount is 0!"); 
        CREDI.safeTransfer(_msgSender(), total_amount);
    }

    function addRewards(uint amount) external 
    {
        require (amount > 0, "ModuleX:amount must be greater than zero!");
        xCREDI.safeTransferFrom(_msgSender(), address(this), amount);
        emit RewardAdded(amount);
    }

    function withdrawRewards(address to, uint amount) external onlyOwner
    {
        require(xCREDI.balanceOf(address(this)) >= amount + pending_payments, "ModuleX:Insufficient balance!");
        xCREDI.safeTransfer(to, amount);
        emit RewardWithdrawn(to, amount);
    }

    function stop() external onlyOwner
    {
        stopped = true;
        emit Stopped();
    }

}
