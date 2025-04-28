// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICREDIWhale 
{
    function isWhale(address user_address) external view returns (bool);
    function whaleThreshold() external view returns (uint); 
}