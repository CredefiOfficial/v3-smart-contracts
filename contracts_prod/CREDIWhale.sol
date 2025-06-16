// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interface/IERC20_Decimals.sol";
import "./interface/ICREDIWhale.sol";

contract CREDIWhale is Ownable, ICREDIWhale  
{
    address immutable public CREDI;
    uint private _whaleThreshold = 500000;

    constructor(address _CREDI) Ownable(_msgSender())
    { 
        CREDI = _CREDI;
        _whaleThreshold = _whaleThreshold*10**IERC20_Decimals(CREDI).decimals();
    }

    function isWhale(address user_address) external view returns (bool)
    {
        return IERC20(CREDI).balanceOf(user_address) >= _whaleThreshold;
    }

    function setWhaleThreshold(uint new_threshold) external onlyOwner
    {
        _whaleThreshold = new_threshold*10**IERC20_Decimals(CREDI).decimals();
    }

    function whaleThreshold() external view returns (uint)
    {
        return _whaleThreshold;
    }

}
