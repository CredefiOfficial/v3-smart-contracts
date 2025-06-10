// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract MarketingStaking is Ownable, ReentrancyGuard
{
    using SafeERC20 for IERC20;
    struct PoolInfo
    {
        IERC20 staking_token;
        uint96 start_epoch;
        IERC20 rewards_token;
        uint96 end_epoch;       
        uint stake_amount;
        uint reward_rate;
        uint reward_rate_cumsum;
        uint available_rewards;
        uint96 last_update_epoch;
    }

    struct StakeDetails
    {
        uint stake_amount;
        uint reward_amount;
        uint reward_rate_cumsum;
    }

    uint96 constant public CLAIM_PERIOD = 40 days;
    uint constant public SCALE_FACTOR = 1e21;
    PoolInfo[] private pools;
    mapping (address => mapping (uint => StakeDetails)) public stakes;

    event RewardAdded(uint indexed pool_id, uint amount);
    event RewardWithdrawn(uint indexed pool_id, address indexed to, uint amount);
    event PoolCreated(uint indexed pool_id, address staking_token, address rewards_token, uint96 start_epoch, uint96 end_epoch, uint scale_factor);
    event PoolUpdated(uint indexed pool_id, uint stake_amount, uint reward_rate, uint reward_rate_cumsum, uint96 last_update_epoch);
    event StakeUpdated(uint indexed pool_id, address indexed user, uint stake_amount, uint reward_amount, uint reward_rate_cumsum);
    event StakeWithdrawn(uint indexed pool_id, address indexed user, uint amount);
    event RewardPaid(uint indexed pool_id, address indexed user, uint amount);

    modifier validate_pool(uint pool_id) 
    {
        require(pool_id > 0 && pool_id < pools.length, "MarketingStaking:Invalid Pool ID!");
        _;
    }
    
    constructor() Ownable(_msgSender())
    { 
        pools.push(PoolInfo({
            staking_token: IERC20(address(0)),
            rewards_token: IERC20(address(0)),
            start_epoch: 0,
            end_epoch: 0,
            stake_amount: 0,
            reward_rate: 0,
            reward_rate_cumsum: 0,
            last_update_epoch: 0,
            available_rewards: 0
        }));
    }

    function getPool(uint pool_id) external validate_pool(pool_id) view 
        returns (address staking_token,
            address rewards_token,
            uint96 start_epoch,
            uint96 end_epoch,
            uint stake_amount,
            uint reward_rate,
            uint reward_rate_cumsum,
            uint96 last_update_epoch,
            uint available_rewards)
    {
        PoolInfo storage pool = pools[pool_id];
        return (address(pool.staking_token),
            address(pool.rewards_token),
            pool.start_epoch,
            pool.end_epoch,
            pool.stake_amount,
            pool.reward_rate,
            pool.reward_rate_cumsum,
            pool.last_update_epoch,
            pool.available_rewards);
    }
  
    function getPoolsCount() external view returns (uint) 
    {
        return pools.length - 1;
    }

    function time_now() private view returns(uint96)
    {
        return uint96(block.timestamp);
    }

    function createPool(address staking_token, address rewards_token, uint96 start_epoch, uint96 end_epoch, uint reward_amount, uint transfer_reward_amount) external onlyOwner returns(uint)
    {
        require(time_now() < end_epoch, "MarketingStaking:End time must be greater than time_now!");
        start_epoch = uint96(Math.max(start_epoch, time_now()));
        require(start_epoch < end_epoch, "MarketingStaking:Start time must be less than end time!");     
        uint reward_rate = SCALE_FACTOR*reward_amount/(end_epoch - start_epoch);
        pools.push(PoolInfo({
            staking_token: IERC20(staking_token),
            rewards_token: IERC20(rewards_token),
            start_epoch: start_epoch,
            end_epoch: end_epoch,
            stake_amount: 0,
            reward_rate: reward_rate,
            reward_rate_cumsum: 0,
            last_update_epoch: start_epoch,
            available_rewards: transfer_reward_amount
        }));
        uint pool_id = pools.length - 1;
        emit PoolCreated(pool_id, staking_token, rewards_token, start_epoch, end_epoch, SCALE_FACTOR);
        if(transfer_reward_amount > 0)
        {
            IERC20(rewards_token).safeTransferFrom(_msgSender(), address(this), transfer_reward_amount);
            emit RewardAdded(pool_id, transfer_reward_amount);
        }
        return pool_id;
    }

    function updatePool(uint pool_id, address user) internal
    {
        PoolInfo storage pool = pools[pool_id];
        uint96 new_epoch = uint96(Math.max(pool.last_update_epoch, Math.min(time_now(), pool.end_epoch)));
        if (pool.stake_amount > 0 && new_epoch > pool.last_update_epoch)
        {
            pool.reward_rate_cumsum += (new_epoch - pool.last_update_epoch)*pool.reward_rate/pool.stake_amount;
        }
        pool.last_update_epoch = new_epoch;

        if(user != address(0))
        {
            StakeDetails storage user_stake = stakes[user][pool_id];
            if(user_stake.stake_amount > 0)
            {
                user_stake.reward_amount += user_stake.stake_amount*(pool.reward_rate_cumsum - user_stake.reward_rate_cumsum)/SCALE_FACTOR;              
            }
            user_stake.reward_rate_cumsum = pool.reward_rate_cumsum;
        }
    }

    function stake(uint pool_id, uint stake_amount) external nonReentrant validate_pool(pool_id)
    {
        PoolInfo storage pool = pools[pool_id];
        require(time_now() >= pool.start_epoch && time_now() < pool.end_epoch, "MarketingStaking:Pool is not active!");
        require(stake_amount > 0, "MarketingStaking:stake_amount must be greater than 0!");

        pool.staking_token.safeTransferFrom(_msgSender(), address(this), stake_amount); 
        updatePool(pool_id, _msgSender());
        StakeDetails storage user_stake = stakes[_msgSender()][pool_id];
        user_stake.stake_amount += stake_amount;
        pool.stake_amount += stake_amount;
        emit StakeUpdated(pool_id, _msgSender(), user_stake.stake_amount, user_stake.reward_amount, user_stake.reward_rate_cumsum);
        emit PoolUpdated(pool_id, pool.stake_amount, pool.reward_rate, pool.reward_rate_cumsum, pool.last_update_epoch);       
    }

    function getUserRewards(uint pool_id, address user) external view validate_pool(pool_id) returns(uint)
    {
        StakeDetails storage user_stake = stakes[user][pool_id];
        PoolInfo storage pool = pools[pool_id];
        uint epoch_now = Math.max(pool.last_update_epoch, Math.min(time_now(), pool.end_epoch));
        uint reward_rate_cumsum = pool.reward_rate_cumsum;
        if (pool.stake_amount > 0 && epoch_now > pool.last_update_epoch)
        {
            reward_rate_cumsum = pool.reward_rate_cumsum + (epoch_now - pool.last_update_epoch)*pool.reward_rate/pool.stake_amount;
        }
        return user_stake.reward_amount + user_stake.stake_amount*(reward_rate_cumsum - user_stake.reward_rate_cumsum)/SCALE_FACTOR;
    }

    function claim(uint pool_id) external nonReentrant validate_pool(pool_id)
    {
        updatePool(pool_id, _msgSender());
        StakeDetails storage details = stakes[_msgSender()][pool_id];
        PoolInfo storage pool = pools[pool_id];
        require(time_now() >= pool.end_epoch, "MarketingStaking:Early Withdrawal is not permitted!"); 
        require(details.reward_amount > 0, "MarketingStaking:Nothing to claim");
        require(pool.available_rewards >= details.reward_amount, "MarketingStaking:Insufficient balance!");
        if(details.stake_amount > 0)
        {
            pool.staking_token.safeTransfer(_msgSender(), details.stake_amount);
            pool.stake_amount -= details.stake_amount;
            emit StakeWithdrawn(pool_id, _msgSender(), details.stake_amount);
            details.stake_amount = 0;
        }

        pool.rewards_token.safeTransfer(_msgSender(), details.reward_amount);
        pool.available_rewards -= details.reward_amount;
        emit RewardPaid(pool_id, _msgSender(), details.reward_amount);
        details.reward_amount = 0;
        details.reward_rate_cumsum = 0;
        emit StakeUpdated(pool_id, _msgSender(), details.stake_amount, details.reward_amount, details.reward_rate_cumsum);
        emit PoolUpdated(pool_id, pool.stake_amount, pool.reward_rate, pool.reward_rate_cumsum, pool.last_update_epoch);
    }

    function withdrawStake(uint pool_id) external nonReentrant validate_pool(pool_id)
    {
        updatePool(pool_id, _msgSender());
        StakeDetails storage details = stakes[_msgSender()][pool_id];
        PoolInfo storage pool = pools[pool_id];
        require(time_now() >= pool.end_epoch, "MarketingStaking:Early Withdrawal is not permitted!"); 
        
        if(details.stake_amount > 0)
        {
            pool.staking_token.safeTransfer(_msgSender(), details.stake_amount);
            pool.stake_amount -= details.stake_amount;
            emit StakeWithdrawn(pool_id, _msgSender(), details.stake_amount);
            details.stake_amount = 0;
            emit StakeUpdated(pool_id, _msgSender(), details.stake_amount, details.reward_amount, details.reward_rate_cumsum);
            emit PoolUpdated(pool_id, pool.stake_amount, pool.reward_rate, pool.reward_rate_cumsum, pool.last_update_epoch);
        }  
    }

    function addRewards(uint pool_id, uint amount) external nonReentrant validate_pool(pool_id) 
    {
        require (amount > 0, "MarketingStaking:amount must be greater than zero!");
        PoolInfo storage pool = pools[pool_id];
        pool.rewards_token.safeTransferFrom(_msgSender(), address(this), amount);
        pool.available_rewards += amount;
        emit RewardAdded(pool_id, amount);
    }

    function withdrawRewards(uint pool_id, address to, uint amount) external onlyOwner validate_pool(pool_id)
    {
        require (amount > 0, "MarketingStaking:amount must be greater than zero!");
        PoolInfo storage pool = pools[pool_id];
        require(pool.available_rewards >= amount, "MarketingStaking:Insufficient balance!");
        require(time_now() >= pool.end_epoch + CLAIM_PERIOD || pool.stake_amount == 0);
        pool.rewards_token.safeTransfer(to, amount);
        pool.available_rewards -= amount;
        emit RewardWithdrawn(pool_id, to, amount);
    }

}
