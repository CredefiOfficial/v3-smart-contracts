// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";

contract SimpleProfitShare is Ownable, ReentrancyGuard
{
    using SafeERC20 for IERC20;
    struct PoolInfo
    {
        IERC20 staking_token;
        uint96 start_epoch;
        IERC20 rewards_token;
        uint96 end_epoch;       
        uint effective_xpoints;
        uint reward_rate;
        uint reward_rate_cumsum;
        uint96 last_update_epoch;
    }

    struct UserInfo
    {
        uint xpoints; // SUM(stake_amount_i*multiplier_i), i=0... user_stakes_count
        uint reward_amount;
        uint reward_rate_cumsum;
        uint stakes_count;
    }

    struct StakeDetails
    {
        uint stake_amount;
        uint96 maturity;
        uint32 multiplier;
    }
    
    uint96 constant public CLAIM_PERIOD = 40 days;
    uint constant public SCALE_FACTOR = 1e21;
    uint32 constant public multiplier_BASE = 1000;

    uint[] private xCREDI_tiers_threshold = [0, 10000*10**18, 25000*10**18, 50000*10**18];
    uint[] private xCREDI_tiers_multiplier = [1000, 1500, 2000, 3000];
    mapping (uint96 => uint32) public duration_multiplier;
    mapping (address => UserInfo) private users;
    mapping (address => mapping (uint => StakeDetails)) private stakes;
    PoolInfo public pool;

    event RewardAdded(uint amount);
    event RewardWithdrawn(address indexed to, uint amount);
    event PoolCreated(address staking_token, address rewards_token, uint96 start_epoch, uint scale_factor);
    event PoolUpdated(uint effective_xpoints, uint reward_rate, uint reward_rate_cumsum, uint96 last_update_epoch, uint96 end_epoch);
    event UserUpdated(address indexed owner, uint xpoints, uint reward_amount, uint reward_rate_cumsum);
    event StakeUpdated(uint stake_id, address indexed user, uint stake_amount, uint modulex_stake_id, uint96 maturity, uint96 lock_period);
    event StakeWithdrawn(uint stake_id, address indexed user, uint amount);
    event RewardPaid(address indexed user, uint amount);
    event SetDurationMultiplier(uint96 duration, uint32 multiplier);
    event SetXTierMultipliers(uint[] thresholds, uint[] multipliers);

    modifier validate_stake(address owner, uint stake_id) 
    {
        require(stake_id < users[owner].stakes_count + 1, "ProfitShare:Invalid Stake ID!");
        _;
    }
    
    constructor(uint96 start_epoch, uint96 end_epoch, uint reward_amount, address _xCREDI_addr, address _rewards_token) Ownable(_msgSender())
    {
        duration_multiplier[0] = multiplier_BASE; // perpetual
        require(time_now() < end_epoch, "ProfitShare:End time must be greater than time_now!");
        start_epoch = uint96(Math.max(start_epoch, time_now()));
        require(start_epoch < end_epoch, "ProfitShare:Start time must be less than end time!");     
        uint reward_rate = SCALE_FACTOR*reward_amount/(end_epoch - start_epoch);
        pool = PoolInfo({
            staking_token: IERC20(_xCREDI_addr),
            rewards_token: IERC20(_rewards_token),
            start_epoch: start_epoch,
            end_epoch: end_epoch,
            effective_xpoints: 0,
            reward_rate: reward_rate,
            reward_rate_cumsum: 0,
            last_update_epoch: start_epoch
        });
        emit PoolCreated(address(pool.staking_token), address(pool.rewards_token), pool.start_epoch, SCALE_FACTOR);
        emit PoolUpdated(pool.effective_xpoints, pool.reward_rate, pool.reward_rate_cumsum, pool.last_update_epoch, pool.end_epoch);
        emit SetDurationMultiplier(0, multiplier_BASE);
        setDurationMultiplier(30 days, 2000);
        setDurationMultiplier(90 days, 3000);
        setDurationMultiplier(180 days, 4000);
        setDurationMultiplier(360 days, 6000);
    }

    function update_pool_and_user(address owner, uint xpoints_staked, uint xpoints_unstaked) private
    {
        uint96 new_epoch = uint96(Math.max(pool.last_update_epoch, Math.min(time_now(), pool.end_epoch)));
        if (pool.effective_xpoints > 0 && new_epoch > pool.last_update_epoch)
        {
            pool.reward_rate_cumsum += (new_epoch - pool.last_update_epoch)*pool.reward_rate/pool.effective_xpoints;
        }
        pool.last_update_epoch = new_epoch;

        if(owner != address(0))
        {
            UserInfo storage user = users[owner];
            uint prev_user_eff_xpts = effective_xpoints(user.xpoints);
            if(user.xpoints > 0)
            {
                user.reward_amount += prev_user_eff_xpts*(pool.reward_rate_cumsum - user.reward_rate_cumsum)/SCALE_FACTOR;              
            }
            user.reward_rate_cumsum = pool.reward_rate_cumsum;
            user.xpoints = user.xpoints + xpoints_staked - xpoints_unstaked;
        
            pool.effective_xpoints = pool.effective_xpoints + effective_xpoints(user.xpoints) - prev_user_eff_xpts;
            emit UserUpdated(owner, user.xpoints, user.reward_amount, user.reward_rate_cumsum);
            emit PoolUpdated(pool.effective_xpoints, pool.reward_rate, pool.reward_rate_cumsum, pool.last_update_epoch, pool.end_epoch);
        }
    }

    function time_now() private view returns(uint96)
    {
        return uint96(block.timestamp);
    }

    function effective_xpoints(uint xpoints) internal view returns(uint)
    {
        uint tier_multiplier = xCREDI_tiers_multiplier[Arrays.upperBound(xCREDI_tiers_threshold, xpoints) - 1];
        return tier_multiplier*xpoints/multiplier_BASE;
    }

    function _stake(address owner, uint96 lock_period, uint amount, uint stake_id) internal
    {
        require(time_now() >= pool.start_epoch && time_now() < pool.end_epoch, "ProfitShare:Pool is not active!");
        uint32 multiplier = duration_multiplier[lock_period];
        uint xpoints = amount*multiplier/multiplier_BASE;
        require(xpoints > 0, "ProfitShare:amount and multiplier must be greater than 0!");

        update_pool_and_user(owner, xpoints, 0);
        StakeDetails storage user_stake = stakes[_msgSender()][stake_id];
        user_stake.stake_amount += amount;
        user_stake.maturity = time_now() + lock_period;
        user_stake.multiplier = multiplier;
     
        emit StakeUpdated(stake_id, owner, user_stake.stake_amount, 0, user_stake.maturity, lock_period);
    }

    function _unstake(address owner, uint amount, uint stake_id) internal
    {
        StakeDetails storage user_stake = stakes[owner][stake_id];
        require(user_stake.stake_amount >= amount, "ProfitShare:Insufficient balance!");
        uint xpoints = amount*user_stake.multiplier/multiplier_BASE;
        update_pool_and_user(owner, 0, xpoints);
        user_stake.stake_amount -= amount;

        emit StakeWithdrawn(stake_id, _msgSender(), amount);       
    }

    function _claim(address owner) internal 
    {
        UserInfo storage user = users[owner];
        if(user.reward_amount > 0)
        {
            pool.rewards_token.safeTransfer(owner, user.reward_amount);            
            emit RewardPaid(owner, user.reward_amount);
            user.reward_amount = 0;
        }
    }

    function _addRewards(uint amount) internal
    {
        require (amount > 0, "ProfitShare:amount must be greater than zero!");
        pool.rewards_token.safeTransferFrom(_msgSender(), address(this), amount);
        emit RewardAdded(amount);
    }

    function stake(uint96 lock_period, uint amount) external nonReentrant
    {
        pool.staking_token.safeTransferFrom(_msgSender(), address(this), amount); 
        uint stake_id = lock_period == 0 ? 0 : ++users[_msgSender()].stakes_count;
        _stake(_msgSender(), lock_period, amount, stake_id);  
    }

    function restake(uint stake_id, uint96 lock_period, uint amount) external nonReentrant validate_stake(_msgSender(), stake_id)
    {
        if(amount > 0)
        {
            pool.staking_token.safeTransferFrom(_msgSender(), address(this), amount); 
        }
        StakeDetails storage user_stake = stakes[_msgSender()][stake_id];
        require(user_stake.multiplier <= duration_multiplier[lock_period], "ProfitShare:Use longer lock_period!");
        uint new_stake_amount = amount + user_stake.stake_amount;
        _unstake(_msgSender(), user_stake.stake_amount, stake_id);
        if(stake_id == 0)
        {
            stake_id = ++users[_msgSender()].stakes_count;
        }
        _stake(_msgSender(), lock_period, new_stake_amount, stake_id);  
    }

    function unstake(uint stake_id, bool claim_rewards) external nonReentrant validate_stake(_msgSender(), stake_id)
    {
        StakeDetails storage user_stake = stakes[_msgSender()][stake_id];
        require(time_now() >= user_stake.maturity, "ProfitShare:Early Withdrawal is not permitted!");
        require(user_stake.stake_amount > 0, "ProfitShare:Nothing to claim");   
        pool.staking_token.safeTransfer(_msgSender(), user_stake.stake_amount);
        _unstake(_msgSender(), user_stake.stake_amount, stake_id);
        if(claim_rewards)
        {
            _claim(_msgSender());
        }
    }

    function unstakePerpetual(uint amount, bool claim_rewards) external nonReentrant
    {
        require(amount > 0, "Cannot unstake 0!");
        pool.staking_token.safeTransfer(_msgSender(), amount);
        _unstake(_msgSender(), amount, 0);
        if(claim_rewards)
        {
            _claim(_msgSender());
        }
    }

    function claimRewards() external nonReentrant 
    {
        update_pool_and_user(_msgSender(), 0, 0);
        _claim(_msgSender());
    }

    function extendRewards(uint96 duration, uint reward_amount, uint transfer_reward_amount) external onlyOwner
    {
        update_pool_and_user(address(0), 0, 0);
        uint96 now_epoch = time_now();
        if (now_epoch >= pool.end_epoch) 
        {
            pool.reward_rate = SCALE_FACTOR*reward_amount/duration;
        } 
        else
        {
            pool.reward_rate = (SCALE_FACTOR*reward_amount+(pool.end_epoch - now_epoch)*pool.reward_rate)/duration; 
        }
        pool.last_update_epoch = now_epoch;
        pool.end_epoch = now_epoch + duration;
        if(transfer_reward_amount > 0)
        {
            _addRewards(transfer_reward_amount);
        }
        emit PoolUpdated(pool.effective_xpoints, pool.reward_rate, pool.reward_rate_cumsum, pool.last_update_epoch, pool.end_epoch);
    }

    function addRewards(uint amount) external
    {
        _addRewards(amount);
    }

    function withdrawRewards(address to, uint amount) external onlyOwner
    {
        require (amount > 0, "ProfitShare:amount must be greater than zero!");
        require(time_now() >= pool.end_epoch + CLAIM_PERIOD || pool.effective_xpoints == 0);
        pool.rewards_token.safeTransfer(to, amount);
        emit RewardWithdrawn(to, amount);
    }

    function setDurationMultiplier(uint96 duration, uint32 multiplier) public onlyOwner
    {
        require(duration > 0 && (multiplier_BASE < multiplier || multiplier == 0));
        duration_multiplier[duration] = multiplier;
        emit SetDurationMultiplier(duration, multiplier);
    }

    function setXTierMultipliers(uint[] calldata _thresholds, uint[] calldata _mulitpliers) public onlyOwner
    {
        require(_thresholds.length == _mulitpliers.length && _mulitpliers.length > 0);
        xCREDI_tiers_threshold = Arrays.sort(_thresholds);
        xCREDI_tiers_multiplier = Arrays.sort(_mulitpliers);
        require(xCREDI_tiers_threshold[0] == 0 && xCREDI_tiers_multiplier[0] >= multiplier_BASE);
        emit SetXTierMultipliers(xCREDI_tiers_threshold, xCREDI_tiers_multiplier);
    }

    function getUserInfo(address owner) external view 
        returns (uint xpoints,
            uint xtier,
            uint reward_amount,
            uint reward_rate_cumsum,
            uint stakes_count)
    {
        UserInfo storage user = users[owner];
        return (
            user.xpoints,
            Arrays.upperBound(xCREDI_tiers_threshold, user.xpoints),
            user.reward_amount,
            user.reward_rate_cumsum,
            user.stakes_count);
    }

    function getStake(address owner, uint stake_id) external validate_stake(owner, stake_id) view 
        returns (
            uint stake_amount,
            uint modulex_stake_id,
            uint96 maturity,
            uint multiplier)
    {
        StakeDetails storage user_stake = stakes[owner][stake_id];
        return (
            user_stake.stake_amount,
            0,
            user_stake.maturity,
            user_stake.multiplier);
    }

    function getUserRewards(address owner) external view returns(uint)
    {
        UserInfo storage user = users[owner];
        uint96 new_epoch = uint96(Math.max(pool.last_update_epoch, Math.min(time_now(), pool.end_epoch)));
        uint reward_rate_cumsum = pool.reward_rate_cumsum;
        if (pool.effective_xpoints > 0 && new_epoch > pool.last_update_epoch)
        {
            reward_rate_cumsum = pool.reward_rate_cumsum + (new_epoch - pool.last_update_epoch)*pool.reward_rate/pool.effective_xpoints;
        }
        return user.reward_amount + effective_xpoints(user.xpoints)*(reward_rate_cumsum - user.reward_rate_cumsum)/SCALE_FACTOR;
    }

}
