// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interface/IERC20_Decimals.sol";
import "./interface/IP2PLending.sol";


contract P2PLending is IP2PLending, Ownable, ERC1155Supply, ReentrancyGuard
{
    using SafeERC20 for IERC20;
    
    uint96 constant public CLAIM_PERIOD = 1 days;
    uint8 constant public RATIOS_DECIMALS = 4;
    uint96 constant public WITHDRAW_COOLDOWN = 60 seconds;
    uint public LOT_SIZE = 1e9; // 10 USDC
    uint32 public MIN_LOTS_AMOUNT = 10;
    uint32 public MIN_DURATION = 7; // days
    uint32 public MAX_DURATION = 730; // days
    uint32 public MIN_FILL_DURATION = 1; // days   
    uint32 public MIN_APY = 100; // 100 = 1%
    uint32 public MAX_APY = 100000; // 1000% 
    uint32 public TARGET_RELATIVE_VALUE = 13000; // 130%
    uint32 public LIQUIDATION_RELATIVE_VALUE = 11500; // 115%
    uint32 public PROTOCOL_FEE = 150; // 1.5%
    address public FEES_COLLECTOR; 
    IPriceData public PRICE_ORACLE;

    address immutable public COLLATERAL;
    uint8 immutable private COLLATERAL_DECIMALS;
    IERC20 immutable public USDC; 

    mapping (uint => LoanConditions) private loan_conditions;
    mapping (uint => LoanState) private loan_state;
    uint private next_loan_id = 1;
    mapping (address => mapping(uint => uint96)) private _withdraw_cooldown;

    constructor(address _price_oracle_address, address _COLLATERAL, address _USDC, address _FEES_COLLECTOR, string memory _erc1155_uri) Ownable(_msgSender()) ERC1155(_erc1155_uri)
    { 
        PRICE_ORACLE = IPriceData(_price_oracle_address);
        COLLATERAL = _COLLATERAL;
        COLLATERAL_DECIMALS = IERC20_Decimals(COLLATERAL).decimals();
        USDC = IERC20(_USDC);
        FEES_COLLECTOR = _FEES_COLLECTOR;
    }

    modifier validate_loan(uint loan_id) 
    {
        require(loan_id > 0 && loan_id < next_loan_id, "Invalid Loan ID!");
        _;
    }

    function time_now() private view returns(uint96)
    {
        return uint96(block.timestamp);
    }

    function emit_state_updated(uint loan_id) private 
    {
        emit StateUpdated(loan_id, loan_state[loan_id].borrower, loan_state[loan_id].deadline, loan_state[loan_id].collateral_balance, loan_state[loan_id].USDC_balance, loan_state[loan_id].claim_deadline);
    }

    function usdc_to_collateral(uint usdc_amount, IPriceData price_oracle, bytes calldata offchain_price_data) internal returns(uint)
    {
        return price_oracle.useQuoteAmountToCollateralAmount(COLLATERAL, COLLATERAL_DECIMALS, usdc_amount, offchain_price_data);
    }

    function getDebt(uint loan_id) public view returns(uint)
    {
        LoanState storage state = loan_state[loan_id];
        if(state.deadline == 0 || state.collateral_balance == 0)
        {
            return 0;
        }
        LoanConditions storage conditions = loan_conditions[loan_id];
        uint USDC_required = totalSupply(loan_id)*conditions.lot_size;
        uint since_start = state.deadline > time_now() ? time_now() - (state.deadline - conditions.duration) : conditions.duration - 1;
        since_start = (since_start/(1 days) + 1)*(1 days);
        return USDC_required + since_start*conditions.apy*USDC_required/(10**RATIOS_DECIMALS)/(365 days);
    }

    function getLoanStatus(uint loan_id) public view returns(LoanStatus)
    {
        LoanConditions storage conditions = loan_conditions[loan_id];
        LoanState storage state = loan_state[loan_id];
        if(conditions.lots_required == 0)
        {
            return LoanStatus.UNDEFINED;
        }
        else if((state.borrower == address(0) && totalSupply(loan_id) == 0) 
            || (state.borrower != address(0) && state.collateral_balance == 0))
        {
            return LoanStatus.FINISHED;
        }
        else if(state.deadline == 0)
        {
            if(state.claim_deadline != 0 && state.claim_deadline < time_now())
            {
                return LoanStatus.EXPIRED;
            }
            else if(conditions.lots_required > totalSupply(loan_id))
            {
                return LoanStatus.FINANCING;
            }
            else
            {
                return LoanStatus.FULLY_FUNDED;
            }
        }
        else if(state.collateral_balance > 0)
        {
            if(totalSupply(loan_id) > 0)
            {
                return LoanStatus.ACTIVE;
            }
            else 
            {
                return LoanStatus.FINISHED;
            }
        }
        else
        {
            return LoanStatus.FINISHED;
        }
    }

    function createAsBorrower(uint lots, uint max_collateral_out, uint32 collateral_value, uint32 duration_days, uint32 apy, uint32 fill_duration_days, bytes calldata offchain_price_data) external nonReentrant returns(uint)
    {
        require(lots >= MIN_LOTS_AMOUNT 
            && collateral_value >= TARGET_RELATIVE_VALUE
            && duration_days >= MIN_DURATION && duration_days <= MAX_DURATION
            && apy >= MIN_APY && apy <= MAX_APY
            && fill_duration_days >= MIN_FILL_DURATION
            , "P2PLending:Invalid arguments!");
        uint USDC_amount = LOT_SIZE*lots;
        uint collateral_amount = collateral_value*usdc_to_collateral(USDC_amount, PRICE_ORACLE, offchain_price_data)/10**RATIOS_DECIMALS;
        require(max_collateral_out >= collateral_amount && collateral_amount > 0, "P2PLending:Increase max_collateral_out!");

        IERC20(COLLATERAL).safeTransferFrom(_msgSender(), address(this), collateral_amount);
        loan_conditions[next_loan_id] = LoanConditions({ 
            lots_required: lots,
            lot_size: LOT_SIZE,
            price_oracle: PRICE_ORACLE,
            duration: duration_days * (1 days),
            apy: apy,
            target_relative_value: collateral_value,
            liquidation_relative_value: LIQUIDATION_RELATIVE_VALUE,
            fill_deadline: time_now() + fill_duration_days * (1 days)
        });

        loan_state[next_loan_id] = LoanState({ 
            borrower: _msgSender(),
            deadline: 0,
            collateral_balance: collateral_amount,
            claim_deadline: 0,
            USDC_balance: 0    
        });
        
        emit CreateAsBorrower(next_loan_id, loan_conditions[next_loan_id].lots_required, loan_conditions[next_loan_id].lot_size, address(loan_conditions[next_loan_id].price_oracle), loan_conditions[next_loan_id].duration, loan_conditions[next_loan_id].apy, loan_conditions[next_loan_id].target_relative_value, loan_conditions[next_loan_id].liquidation_relative_value,loan_conditions[next_loan_id].fill_deadline);
        emit_state_updated(next_loan_id);
        return next_loan_id++;
    }

    function createAsLender(uint lots, uint32 collateral_value, uint32 duration_days, uint32 apy) external nonReentrant returns(uint)
    {
        require(lots >= MIN_LOTS_AMOUNT 
            && collateral_value >= TARGET_RELATIVE_VALUE
            && duration_days >= MIN_DURATION && duration_days <= MAX_DURATION
            && apy >= MIN_APY && apy <= MAX_APY
            , "P2PLending:Invalid arguments!");
        USDC.safeTransferFrom(_msgSender(), address(this), LOT_SIZE*lots);
        _mint(_msgSender(), next_loan_id, lots, "");
        
        loan_conditions[next_loan_id] = LoanConditions({ 
            lots_required: lots,
            lot_size: LOT_SIZE,
            price_oracle: PRICE_ORACLE,
            duration: duration_days * (1 days),
            apy: apy,
            target_relative_value: collateral_value,
            liquidation_relative_value: LIQUIDATION_RELATIVE_VALUE,
            fill_deadline: 0
        });

        loan_state[next_loan_id] = LoanState({ 
            borrower: address(0),
            deadline: 0,
            collateral_balance: 0,
            claim_deadline: 0,
            USDC_balance: 0     
        });

        emit CreateAsLender(next_loan_id, _msgSender(), loan_conditions[next_loan_id].lots_required, loan_conditions[next_loan_id].lot_size, address(loan_conditions[next_loan_id].price_oracle), loan_conditions[next_loan_id].duration, loan_conditions[next_loan_id].apy, loan_conditions[next_loan_id].target_relative_value, loan_conditions[next_loan_id].liquidation_relative_value,loan_conditions[next_loan_id].fill_deadline);
        return next_loan_id++;
    }

    function lend(uint loan_id, uint target_lots, uint min_lots) external nonReentrant validate_loan(loan_id) returns(uint)
    {
        require(target_lots > 0 && target_lots >= min_lots, "P2PLending require:target_lots>0 && lots>=min_lots");
        require(getLoanStatus(loan_id) == LoanStatus.FINANCING, "P2PLending:LoanStatus not equals FINANCING!");

        LoanConditions storage conditions = loan_conditions[loan_id];
        uint available_lots = conditions.lots_required - totalSupply(loan_id);
        require(available_lots >= min_lots, "P2PLending:Not enough available lots!");
        uint lots = Math.min(target_lots, available_lots);
        USDC.safeTransferFrom(_msgSender(), address(this), conditions.lot_size*lots);
        _mint(_msgSender(), loan_id, lots, "");
        require(totalSupply(loan_id) <= conditions.lots_required, "P2PLending require:supply<=lots_required");
        uint96 epoch_now = time_now();
        if(totalSupply(loan_id) == conditions.lots_required)
        {
            loan_state[loan_id].claim_deadline = epoch_now + CLAIM_PERIOD;
            emit FullyFunded(loan_id, loan_state[loan_id].claim_deadline);
        }
        else 
        {
            _withdraw_cooldown[_msgSender()][loan_id] = epoch_now + WITHDRAW_COOLDOWN;
        }

        emit Lend(loan_id, _msgSender(), lots);
        return lots;
    }

    function borrow(uint loan_id, uint min_lots, uint max_lots, bool transfer_collateral, uint max_collateral_out,  bytes calldata offchain_price_data) external nonReentrant validate_loan(loan_id) returns(uint)
    {
        LoanConditions storage conditions = loan_conditions[loan_id];
        LoanState storage state = loan_state[loan_id];
        {
        uint available_lots = totalSupply(loan_id);
        require(min_lots>0 && available_lots >= min_lots && available_lots <= max_lots,"P2PLending require:0<min_lots<=supply<=max_lots");
        LoanStatus status = getLoanStatus(loan_id);
        require(status == LoanStatus.FINANCING || status == LoanStatus.FULLY_FUNDED, "P2PLending:Cannot borrow!");     
        require(state.borrower == _msgSender() || state.borrower == address(0), "P2PLending:Caller is not owner!");
        
        conditions.lots_required = available_lots;
        state.borrower = _msgSender();
        state.deadline = time_now() + conditions.duration;
        }
        uint USDC_required = conditions.lots_required*conditions.lot_size;
        uint collateral_amount_100 = usdc_to_collateral(USDC_required, conditions.price_oracle, offchain_price_data);

        if(transfer_collateral)
        {
            uint target_collateral_amount = conditions.target_relative_value*collateral_amount_100/10**RATIOS_DECIMALS;
            if(target_collateral_amount > state.collateral_balance)
            {
                uint collateral_out = target_collateral_amount - state.collateral_balance;
                require(max_collateral_out >= collateral_out,"P2PLending:Increase max_collateral_out!");
                IERC20(COLLATERAL).safeTransferFrom(state.borrower, address(this), collateral_out);
            }
            else if(target_collateral_amount < state.collateral_balance)
            {
                IERC20(COLLATERAL).safeTransfer(state.borrower, state.collateral_balance - target_collateral_amount);
            }
            state.collateral_balance = target_collateral_amount;
        }
        require(state.collateral_balance >= TARGET_RELATIVE_VALUE*collateral_amount_100/10**RATIOS_DECIMALS, "P2PLending:Increase collateral!");
        {
            uint fee = PROTOCOL_FEE*USDC_required/(10**RATIOS_DECIMALS);
            USDC.safeTransfer(FEES_COLLECTOR, fee);
            USDC.safeTransfer(state.borrower, USDC_required - fee);
        }

        emit Borrow(loan_id, conditions.lots_required);
        emit_state_updated(loan_id); 
        return conditions.lots_required;
    }

    function repay(uint loan_id) external nonReentrant validate_loan(loan_id)
    {
        require(getLoanStatus(loan_id) == LoanStatus.ACTIVE, "P2PLending:LoanStatus must equals ACTIVE!");
        LoanState storage state = loan_state[loan_id];
        require(state.borrower == _msgSender(), "P2PLending:Caller is not owner!");
        uint required_USDC = getDebt(loan_id);
        USDC.safeTransferFrom(state.borrower, address(this), required_USDC);
        state.USDC_balance += required_USDC;
        IERC20(COLLATERAL).safeTransfer(state.borrower, state.collateral_balance);
        state.collateral_balance = 0;

        emit Repay(loan_id, required_USDC);
        emit_state_updated(loan_id);
    }

    function increaseCollateral(uint loan_id, uint collateral_amount) external nonReentrant validate_loan(loan_id)
    {
        require(getLoanStatus(loan_id) == LoanStatus.ACTIVE, "P2PLending:LoanStatus must equals ACTIVE!");
        LoanState storage state = loan_state[loan_id];
        require(state.borrower == _msgSender(), "P2PLending:Caller is not owner!");
        IERC20(COLLATERAL).safeTransferFrom(state.borrower, address(this), collateral_amount);
        state.collateral_balance += collateral_amount;

        emit IncreaseCollateral(loan_id, collateral_amount);
        emit_state_updated(loan_id);
    }

    function withdrawCollateral(uint loan_id) external nonReentrant validate_loan(loan_id)
    {
        LoanState storage state = loan_state[loan_id];
        require(state.borrower == _msgSender(), "P2PLending:Caller is not owner!");
        require(state.deadline == 0 && state.collateral_balance > 0, "P2PLending:Cannot Withdraw!");
        if(getLoanStatus(loan_id) == LoanStatus.FINANCING && loan_conditions[loan_id].fill_deadline < time_now())
        {
            IERC20(COLLATERAL).safeTransfer(state.borrower, state.collateral_balance);
        }
        else 
        {
            uint fee = PROTOCOL_FEE*state.collateral_balance/(10**RATIOS_DECIMALS);
            IERC20(COLLATERAL).safeTransfer(FEES_COLLECTOR, fee);
            IERC20(COLLATERAL).safeTransfer(state.borrower, state.collateral_balance - fee);
        }    
        state.collateral_balance = 0;
        state.USDC_balance = totalSupply(loan_id)*loan_conditions[loan_id].lot_size;

        emit WithdrawCollateral(loan_id);
        emit_state_updated(loan_id);
    }

    function withdrawUSDC(uint loan_id, uint lots) external nonReentrant validate_loan(loan_id)
    {
        require(lots > 0, "P2PLending:lots must be greater than zero!");
        LoanStatus status = getLoanStatus(loan_id);
        require(loan_state[loan_id].borrower == address(0) || status == LoanStatus.EXPIRED || (status == LoanStatus.FINANCING && time_now() > _withdraw_cooldown[_msgSender()][loan_id]), "P2PLending:Cannot withdraw!");
        _burn(_msgSender(), loan_id, lots);
        if(loan_state[loan_id].borrower == address(0))
        {
            uint supply_after_burn = totalSupply(loan_id);
            require(supply_after_burn == 0 || supply_after_burn >= MIN_LOTS_AMOUNT,"P2PLending:Supply below MIN_LOTS_AMOUNT!");
        }
        USDC.safeTransfer(_msgSender(), loan_conditions[loan_id].lot_size*lots);

        emit WithdrawUSDC(loan_id, _msgSender(), lots);
    }

    function claimUSDC(uint loan_id) external nonReentrant validate_loan(loan_id)
    {
        require(getLoanStatus(loan_id) == LoanStatus.FINISHED, "P2PLending:LoanStatus must equals FINISHED!");
        uint loan_tokens_amount = balanceOf(_msgSender(), loan_id);
        require(loan_tokens_amount > 0, "P2PLending:Nothing to claim!");
        LoanState storage state = loan_state[loan_id];    
        uint USDC_amount = loan_tokens_amount*state.USDC_balance/totalSupply(loan_id);   
        state.USDC_balance -= USDC_amount;
        _burn(_msgSender(), loan_id, loan_tokens_amount);
        USDC.safeTransfer(_msgSender(), USDC_amount);

        emit ClaimUSDC(loan_id, _msgSender(), loan_tokens_amount, USDC_amount);
        emit_state_updated(loan_id);
    }

    function claimCollateral(uint loan_id, bytes calldata offchain_price_data) external nonReentrant validate_loan(loan_id)
    {
        require(getLoanStatus(loan_id) == LoanStatus.ACTIVE, "P2PLending:LoanStatus must equals ACTIVE!");
        LoanConditions storage conditions = loan_conditions[loan_id];
        LoanState storage state = loan_state[loan_id];
        require(state.deadline < time_now() || conditions.price_oracle.useRelativeCollateralValue(COLLATERAL, RATIOS_DECIMALS, state.collateral_balance, COLLATERAL_DECIMALS, getDebt(loan_id), offchain_price_data) < conditions.liquidation_relative_value, "P2PLending:Cannot Liquidate!");      
        uint loan_tokens_amount = balanceOf(_msgSender(), loan_id);
        require(loan_tokens_amount > 0, "P2PLending:Nothing to claim!");
        
        uint collateral_amount = loan_tokens_amount*state.collateral_balance/totalSupply(loan_id); 
        state.collateral_balance -= collateral_amount;
        _burn(_msgSender(), loan_id, loan_tokens_amount);
        IERC20(COLLATERAL).safeTransfer(_msgSender(), collateral_amount);

        emit ClaimCollateral(loan_id, _msgSender(), loan_tokens_amount, collateral_amount);
        emit_state_updated(loan_id);
    }

    function isCollateralClaimable(uint loan_id, bytes calldata offchain_price_data) external view returns(bool)
    {
        if(!(loan_id > 0 && loan_id < next_loan_id)
            || getLoanStatus(loan_id) != LoanStatus.ACTIVE
            || !(loan_state[loan_id].deadline < time_now() || loan_conditions[loan_id].price_oracle.readRelativeCollateralValue(COLLATERAL, RATIOS_DECIMALS, loan_state[loan_id].collateral_balance, COLLATERAL_DECIMALS, getDebt(loan_id), offchain_price_data) < loan_conditions[loan_id].liquidation_relative_value))
        {
            return false;
        }
        else
        {
            return true;
        }
    }

    function getRelativeCollateralValue(uint loan_id, bytes calldata offchain_price_data) external validate_loan(loan_id) view returns(uint)
    {
        require(getLoanStatus(loan_id) == LoanStatus.ACTIVE, "P2PLending:LoanStatus must equals ACTIVE!");
        return loan_conditions[loan_id].price_oracle.readRelativeCollateralValue(COLLATERAL, RATIOS_DECIMALS, loan_state[loan_id].collateral_balance, COLLATERAL_DECIMALS, getDebt(loan_id), offchain_price_data);
    }

    function USDCValueOf(uint loan_id, uint amount) external validate_loan(loan_id) view returns(uint)
    {
        uint supply = totalSupply(loan_id);
        if(supply > 0)
        {
            uint loan_USDC_value = loan_state[loan_id].USDC_balance == 0 ? getDebt(loan_id) : loan_state[loan_id].USDC_balance;
            return amount*loan_USDC_value/supply;
        }
        else 
        {
            return 0;
        }
    }

    function getLoanInfo(uint loan_id) external validate_loan(loan_id) view returns(LoanConditions memory, LoanState memory, uint)
    {
        return (loan_conditions[loan_id], loan_state[loan_id], totalSupply(loan_id));
    }

    function setLotSize(uint _LOT_SIZE) external onlyOwner
    {
        LOT_SIZE = _LOT_SIZE;
        emit SetLotSize(LOT_SIZE);
    }

    function setMinLotsAmount(uint32 _MIN_LOTS_AMOUNT) external onlyOwner
    {
        MIN_LOTS_AMOUNT = _MIN_LOTS_AMOUNT;
        emit SetMinLotsAmount(MIN_LOTS_AMOUNT);
    }

    function setMinDuration(uint32 _MIN_DURATION) external onlyOwner
    {
        MIN_DURATION = _MIN_DURATION;
        emit SetMinDuration(MIN_DURATION);
    }

    function setMaxDuration(uint32 _MAX_DURATION) external onlyOwner
    {
        MAX_DURATION = _MAX_DURATION;
        emit SetMaxDuration(MAX_DURATION);
    }

    function setMinFillDuration(uint32 _MIN_FILL_DURATION) external onlyOwner
    {
        MIN_FILL_DURATION = _MIN_FILL_DURATION;
        emit SetMinFillDuration(MIN_FILL_DURATION);
    }

    function setMinAPY(uint32 _MIN_APY) external onlyOwner
    {
        MIN_APY = _MIN_APY;
        emit SetMinAPY(MIN_APY);
    }

    function setMaxAPY(uint32 _MAX_APY) external onlyOwner
    {
        MAX_APY = _MAX_APY;
        emit SetMaxAPY(MAX_APY);
    }

    function setTargetRelativeValue(uint32 _TARGET_RELATIVE_VALUE) external onlyOwner
    {
        TARGET_RELATIVE_VALUE = _TARGET_RELATIVE_VALUE;
        emit SetTargetRelativeValue(TARGET_RELATIVE_VALUE);
    }

    function setLiquidationRelativeValue(uint32 _LIQUIDATION_RELATIVE_VALUE) external onlyOwner
    {
        LIQUIDATION_RELATIVE_VALUE = _LIQUIDATION_RELATIVE_VALUE;
        emit SetLiquidationRelativeValue(LIQUIDATION_RELATIVE_VALUE);
    }

    function setProtocolFee(uint32 _PROTOCOL_FEE) external onlyOwner
    {
        PROTOCOL_FEE = _PROTOCOL_FEE;
        emit SetProtocolFee(PROTOCOL_FEE);
    }

    function setFeesCollector(address _FEES_COLLECTOR) external onlyOwner
    {
        FEES_COLLECTOR = _FEES_COLLECTOR;
        emit SetFeesCollector(FEES_COLLECTOR);
    }

    function setPriceOracle(address _PRICE_ORACLE) external onlyOwner
    {
        PRICE_ORACLE = IPriceData(_PRICE_ORACLE);
        emit SetPriceOracle(_PRICE_ORACLE);
    }

}
