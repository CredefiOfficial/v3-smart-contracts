// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceData
{
    function readPrice(address base_addr, uint8 target_decimals, bytes calldata offchain_data) external view returns(uint);
   
    function usePrice(address base_addr, uint8 target_decimals, bytes calldata offchain_data) external returns(uint);
   
    function readAbsoluteCollateralValue(address base_addr, uint base_amount, uint8 base_decimals, bytes calldata offchain_data) external view returns(uint);
   
    function useAbsoluteCollateralValue(address base_addr, uint base_amount, uint8 base_decimals, bytes calldata offchain_data) external returns(uint);
  
    function readQuoteAmountToCollateralAmount(address base_addr, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external view returns(uint);
    
    function useQuoteAmountToCollateralAmount(address base_addr, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external returns(uint);
    
    function readRelativeCollateralValue(address base_addr, uint8 result_decimals, uint base_amount, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external view returns(uint);
   
    function useRelativeCollateralValue(address base_addr, uint8 result_decimals, uint base_amount, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external returns(uint);
   
    function readCollateralValues(address base_addr, uint8 result_decimals, uint base_amount, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external view returns(uint absolute_value, uint relative_value);
   
    function useCollateralValues(address base_addr, uint8 result_decimals, uint base_amount, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external returns(uint absolute_value, uint relative_value);
     
    function setOracles(address base_addr, address[] calldata mul, address[] calldata div) external;
   
    function setSigner(address signer, bool state) external;

    function quoteToken() external view returns(address); 
   
}
