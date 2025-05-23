// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPriceData.sol";

interface IP2PLending
{
   struct LoanConditions
    { 
        uint lots_required;
        uint lot_size;
        IPriceData price_oracle;
        uint96 duration;
        uint32 apy;
        uint32 target_relative_value;
        uint32 liquidation_relative_value;
        uint96 fill_deadline;
    }

    struct LoanState
    {
        address borrower;
        uint96 deadline;
        uint collateral_balance;
        uint USDC_balance;
        uint96 claim_deadline;
    }

    enum LoanStatus
    {
        UNDEFINED,
        FINANCING,
        FULLY_FUNDED,
        EXPIRED,
        ACTIVE,
        FINISHED
    }
    
    event CreateAsBorrower(uint indexed loan_id, uint lots_required, uint lot_size, address price_oracle, uint96 duration, uint32 apy, uint32 target_relative_value, uint32 liquidation_relative_value, uint96 fill_deadline);
    event CreateAsLender(uint indexed loan_id, address indexed lender, uint lots_required, uint lot_size, address price_oracle, uint96 duration, uint32 apy, uint32 target_relative_value, uint32 liquidation_relative_value, uint96 fill_deadline);
    event StateUpdated(uint indexed loan_id, address indexed borrower, uint96 deadline, uint collateral_balance, uint USDC_balance, uint96 claim_deadline);
    event FullyFunded(uint indexed loan_id, uint96 claim_deadline);
    event Lend(uint indexed loan_id, address indexed lender, uint lots);
    event Borrow(uint indexed loan_id, uint lots);
    event Repay(uint indexed load_id, uint USDC_amount);
    event WithdrawCollateral(uint indexed load_id);
    event WithdrawUSDC(uint indexed loan_id, address indexed lender, uint lots);
    event ClaimUSDC(uint indexed loan_id, address indexed lender, uint lots, uint USDC_amount); 
    event ClaimCollateral(uint indexed loan_id, address indexed lender, uint lots, uint collateral_amount);

    function getDebt(uint loan_id) external view returns(uint USDC_value);

    function getLoanStatus(uint loan_id) external view returns(LoanStatus status);

    function createAsBorrower(uint lots, uint max_collateral_out, uint32 collateral_value, uint32 duration_days, uint32 apy, uint32 fill_duration_days, bytes calldata offchain_price_data) external returns(uint loan_id);

    function createAsLender(uint lots, uint32 collateral_value, uint32 duration_days, uint32 apy) external returns(uint loan_id);

    function lend(uint loan_id, uint target_lots, uint min_lots) external returns(uint lots);

    function borrow(uint loan_id, uint min_lots, uint max_lots, bool transfer_collateral, uint max_collateral_out,  bytes calldata offchain_price_data) external returns(uint lots);
    
    function repay(uint loan_id) external;

    function withdrawCollateral(uint loan_id) external;

    function withdrawUSDC(uint loan_id, uint lots) external;

    function claimUSDC(uint loan_id) external;

    function claimCollateral(uint loan_id, bytes calldata offchain_price_data) external;

    function isCollateralClaimable(uint loan_id, bytes calldata offchain_price_data) external view returns(bool);

    function getRelativeCollateralValue(uint loan_id, bytes calldata offchain_price_data) external view returns(uint relatie_value);

    function USDCValueOf(uint loan_id, uint amount) external view returns(uint USDC_value);

    function getLoanInfo(uint loan_id) external view returns(LoanConditions memory conditions, LoanState memory state, uint supply);

    event SetLotSize(uint LOT_SIZE);
    event SetMinLotsAmount(uint32 MIN_LOTS_AMOUNT);
    event SetMinDuration(uint32 MIN_LOTS_AMOUNT);
    event SetMaxDuration(uint32 MIN_LOTS_AMOUNT);
    event SetMinFillDuration(uint32 MIN_FILL_DURATION);
    event SetMinAPY(uint32 MIN_APY);
    event SetMaxAPY(uint32 MAX_APY);
    event SetTargetRelativeValue(uint32 TARGET_RELATIVE_VALUE);
    event SetLiquidationRelativeValue(uint32 LIQUIDATION_RELATIVE_VALUE);
    event SetProtocolFee(uint32 PROTOCOL_FEE);
    event SetFeesCollector(address FEES_COLLECTOR);
    event SetPriceOracle(address PRICE_ORACLE);

}