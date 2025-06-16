// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../interface/IPriceData.sol";
import "../interface/IERC20_Decimals.sol";

abstract contract LPValue
{
    function token_value(address token_addr, uint amount, address oracle_addr, bytes calldata price_data) private returns(uint)
    {
        return IPriceData(oracle_addr).useAbsoluteCollateralValue(token_addr, amount, IERC20_Decimals(token_addr).decimals(), price_data);
    }

    function token_balances(uint lp_balance, uint lp_supply, uint112 reserve0, uint112 reserve1) private pure returns (uint, uint)
    {
        uint token0_balance = reserve0*lp_balance/lp_supply;
        uint token1_balance = reserve1*lp_balance/lp_supply;
        return (token0_balance, token1_balance);
    }

    function lp_value(address lp_addr, uint lp_amount, address oracle_addr, bytes calldata token0_price_data, bytes calldata token1_price_data) internal returns (uint)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(lp_addr);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        (uint token0_balance, uint token1_balance) = token_balances(lp_amount, pair.totalSupply(), reserve0, reserve1);
        return  token_value(pair.token0(), token0_balance, oracle_addr, token0_price_data) 
                +token_value(pair.token1(), token1_balance, oracle_addr, token1_price_data);
    }

}
