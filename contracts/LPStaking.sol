// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./oracle_utils/LPValue.sol";
import "./interface/ICREDIWhale.sol";
import "./interface/IPriceData.sol";

contract LPStaking is Ownable, LPValue
{
    using SafeERC20 for IERC20;
    struct PoolInfo
    {
        address staking_token;
        uint96 maturity;
        address rewards_token;
        uint96 apy; // 100 = 1% , 0 --> paused
        address price_oracle;
        uint96 whales_bonus_apy;
    }

    struct StakeDetails
    {
        uint pool_id;
        address owner;
        uint96 maturity;
        uint stake_amount;
        uint reward_amount;
        uint required_CREDI;
    }

    uint96 constant public CLAIM_PERIOD = 40 days;
    ICREDIWhale immutable public CREDI_WHALE_ORACLE = ICREDIWhale(0x7b5b18B1928172e250Bb73c0543266aB182aB1Bb);

    PoolInfo[] private pools;
    mapping (uint => StakeDetails) private stakes;
    uint private stakes_count = 1;
    mapping (address => uint) public pending_payments;

    event RewardAdded(address indexed token, uint amount);
    event RewardWithdrawn(address indexed token, address indexed to, uint amount);
    event PoolCreated(uint indexed pool_id, address indexed staking_token, address indexed rewards_token, address price_oracle, uint96 maturity, uint96 apy, uint96 whales_bonus_apy);
    event APYChanged(uint indexed pool_id, uint96 apy);
    event BonusAPYChanged(uint indexed pool_id, uint96 whales_bonus_apy); 
    event Staked(address indexed owner, uint stake_id, uint indexed pool_id, uint96 maturity, uint stake_amount, uint rewards_amount, uint required_CREDI);
    event StakeWithdrawn(uint indexed pool_id, uint stake_id);
    event RewardPaid(uint indexed pool_id, uint stake_id);
    event RewardVoided(uint indexed pool_id, uint stake_id);

    modifier validate_pool(uint pool_id) 
    {
        require(pool_id > 0 && pool_id < pools.length, "LPStaking:Invalid Pool ID!");
        _;
    }

    modifier validate_stake(uint stake_id) 
    {
        require(stake_id > 0 && stake_id < stakes_count, "LPStaking:Invalid Stake ID!");
        _;
    }

    constructor(address _whale_oracle_addr) Ownable(_msgSender())
    {
        CREDI_WHALE_ORACLE = ICREDIWhale(_whale_oracle_addr);
        pools.push(PoolInfo({
            staking_token: address(0),
            maturity: 0,
            rewards_token: address(0),
            apy: 0,
            price_oracle: address(0),
            whales_bonus_apy: 0
        }));
    }

    function getPool(uint pool_id) external validate_pool(pool_id) view 
        returns (address staking_token,
            address rewards_token,
            address price_oracle,
            uint96 maturity,
            uint96 apy,
            uint96 whales_bonus_apy)
    {
        return (pools[pool_id].staking_token,
            pools[pool_id].rewards_token,
            pools[pool_id].price_oracle,
            pools[pool_id].maturity,
            pools[pool_id].apy,
            pools[pool_id].whales_bonus_apy);
    }
   
    function getStake(uint stake_id) external validate_stake(stake_id) view 
        returns (address owner,
        uint pool_id,
        uint96 maturity,
        uint stake_amount,
        uint reward_amount,
        uint required_CREDI)
    {
        return (stakes[stake_id].owner,
            stakes[stake_id].pool_id,
            stakes[stake_id].maturity,
            stakes[stake_id].stake_amount,
            stakes[stake_id].reward_amount,
            stakes[stake_id].required_CREDI);
    }

    function getPoolsCount() external view returns (uint) 
    {
        return pools.length - 1;
    }

    function time_now() private view returns(uint96)
    {
        return uint96(block.timestamp);
    }

    function createPool(address staking_token, address rewards_token, address price_oracle, uint reward_amount, uint96 maturity, uint96 apy, uint96 whales_bonus_apy) external onlyOwner returns(uint)
    {
        require(maturity > 0, "LPStaking:maturity must be greater than 0");
        require(IPriceData(price_oracle).quoteToken() == rewards_token, "LPStaking:rewards_token must be equal to price_oracle quote token");
        pools.push(PoolInfo({
            staking_token: staking_token,
            maturity: maturity,
            rewards_token: rewards_token,
            apy: apy,
            price_oracle: price_oracle,
            whales_bonus_apy: whales_bonus_apy
        }));
        uint pool_id = pools.length - 1;
        emit PoolCreated(pool_id, staking_token, rewards_token, price_oracle, maturity, apy, whales_bonus_apy);
        if(reward_amount > 0)
            addRewards(rewards_token, reward_amount);
        return pool_id;
    }

    function stake(uint pool_id, uint stake_amount, bytes calldata token0_price_data, bytes calldata token1_price_data) external validate_pool(pool_id)
    {
        PoolInfo storage pool = pools[pool_id];
        require(pool.apy > 0, "LPStaking:Pool is paused!");
        IERC20(pool.staking_token).safeTransferFrom(_msgSender(), address(this), stake_amount); 
        uint stake_value = lp_value(pool.staking_token, stake_amount, pool.price_oracle, token0_price_data, token1_price_data);
        uint reward_amount = stake_value*pool.apy/10000;
        uint required_CREDI = 0;
        if(CREDI_WHALE_ORACLE.isWhale(_msgSender()))
        {
            required_CREDI = CREDI_WHALE_ORACLE.whaleThreshold();
            reward_amount += stake_value*pool.whales_bonus_apy/10000;
        }

        uint96 maturity = time_now() + pool.maturity;
        stakes[stakes_count] = StakeDetails({
            owner: _msgSender(),
            pool_id: pool_id,
            maturity: maturity,
            stake_amount: stake_amount,
            reward_amount: reward_amount,
            required_CREDI: required_CREDI
        });
        pending_payments[pool.rewards_token] += reward_amount;
        emit Staked(_msgSender(), stakes_count, pool_id, maturity, stake_amount, reward_amount, required_CREDI);
        stakes_count++; 
    }

    function claim(uint stake_id) external validate_stake(stake_id)
    {      
        StakeDetails storage details = stakes[stake_id];
        require(details.owner == _msgSender(), "LPStaking:Caller is not the owner");
        PoolInfo storage pool = pools[details.pool_id];
        require(time_now() >= details.maturity, "LPStaking:Early Withdrawal is not permitted!"); 
        require(details.reward_amount > 0, "LPStaking:Nothing to claim");
        if(details.stake_amount > 0)
        {
            IERC20(pool.staking_token).safeTransfer(_msgSender(), details.stake_amount);
            details.stake_amount = 0;
        }

        IERC20(pool.rewards_token).safeTransfer(_msgSender(), details.reward_amount);
        pending_payments[pool.rewards_token] -= details.reward_amount;
        details.reward_amount = 0; 
        emit StakeWithdrawn(details.pool_id, stake_id);
        emit RewardPaid(details.pool_id, stake_id); 
    }

    function voidReward(uint stake_id) external onlyOwner validate_stake(stake_id)
    {
        StakeDetails storage details = stakes[stake_id];
        require(time_now() >= details.maturity + CLAIM_PERIOD); 
        PoolInfo storage pool = pools[details.pool_id];
        pending_payments[pool.rewards_token] -= details.reward_amount;
        details.reward_amount = 0;
        emit RewardVoided(details.pool_id, stake_id);
    }

    function withdrawStake(uint stake_id) external validate_stake(stake_id)
    {
        StakeDetails storage details = stakes[stake_id];
        require(details.owner == _msgSender(), "LPStaking:Caller is not the owner");
        PoolInfo memory pool = pools[details.pool_id];
        require(time_now() >= details.maturity, "LPStaking:Early Withdrawal is not permitted!"); 
        
        if(details.stake_amount > 0)
        {
            IERC20(pool.staking_token).safeTransfer(_msgSender(), details.stake_amount);
            details.stake_amount = 0;
            emit StakeWithdrawn(details.pool_id, stake_id);
        }  
    }

    function addRewards(address rewards_token, uint amount) public 
    {
        require (amount > 0, "LPStaking:amount must be greater than zero!");
        IERC20(rewards_token).safeTransferFrom(_msgSender(), address(this), amount);
        emit RewardAdded(rewards_token, amount);
    }

    function withdrawRewards(address rewards_token, address to, uint amount) external onlyOwner
    {
        require(IERC20(rewards_token).balanceOf(address(this)) >= amount + pending_payments[rewards_token], "Insufficient balance!");
        IERC20(rewards_token).safeTransfer(to, amount);
        emit RewardWithdrawn(rewards_token, to, amount);
    }

    function setAPY(uint pool_id, uint96 apy) external onlyOwner validate_pool(pool_id)
    {
        require(apy <= 100000, "LPStaking:max apy is 1000%");
        pools[pool_id].apy = apy;
        emit APYChanged(pool_id, apy);
    }

    function setBonusAPY(uint pool_id, uint96 whales_bonus_apy) external onlyOwner validate_pool(pool_id)
    {
        require(whales_bonus_apy <= 100000, "LPStaking:max bonus apy is 1000%");
        pools[pool_id].whales_bonus_apy = whales_bonus_apy;
        emit BonusAPYChanged(pool_id, whales_bonus_apy);
    }

}
