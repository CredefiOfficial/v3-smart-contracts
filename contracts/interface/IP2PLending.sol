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

    function getRelativeCollateralValue(uint loan_id, bytes calldata offchain_price_data) external view returns(uint relatie_value);

    function USDCValueOf(uint loan_id, uint amount) external view returns(uint USDC_value);

    function getLoanInfo(uint loan_id) external view returns(LoanConditions memory conditions, LoanState memory state, uint supply);

}