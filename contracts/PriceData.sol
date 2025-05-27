// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts@1.2.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./oracle_utils/OffChainPriceOracle.sol";
import "./interface/IERC20_Decimals.sol";
import "./interface/IPriceData.sol";

contract PriceData is IPriceData, Ownable, OffChainPriceOracle
{
    mapping (address => address[]) public path_mul;
    mapping (address => address[]) public path_div;
    mapping (address => bool) public isOnchainOracle;

    uint8 constant public PRECISION = 20;
    address immutable public QUOTE_ADDRESS;
    uint8 immutable public QUOTE_DECIMALS;
    
    event OnChainOracleAdded(address indexed base_token, address[] mul_path, address[] div_path);
    event PriceLog(address indexed base_token, uint price, uint decimals);

    constructor(address _quote_addr) Ownable(_msgSender())
    {
        QUOTE_ADDRESS = _quote_addr;
        QUOTE_DECIMALS = IERC20_Decimals(QUOTE_ADDRESS).decimals();
    }

    function calc_chainlink_price(address base_addr, uint8 target_decimals) private view returns(uint)
    {
        address[] memory mul = path_mul[base_addr];
        address[] memory div = path_div[base_addr];
        require(mul.length + div.length > 0, "Unsupported token!");
        uint curr_price = 10 ** target_decimals;
        for(uint i=0; i<mul.length; i++)
        {
            AggregatorV3Interface dataFeed = AggregatorV3Interface(mul[i]);
            uint oracle_decimals = dataFeed.decimals();
            (/* uint80 roundID */, int answer, /*uint startedAt*/, /*uint timeStamp*/,/*uint80 answeredInRound*/) = dataFeed.latestRoundData();
            require(oracle_decimals > 0 && answer > 0, "Bad oracle data!");
            curr_price = curr_price*uint(answer)/(10**oracle_decimals);
        }
        for(uint i=0; i<div.length; i++)
        {
            AggregatorV3Interface dataFeed = AggregatorV3Interface(div[i]);
            uint oracle_decimals = dataFeed.decimals();
            (/* uint80 roundID */, int answer, /*uint startedAt*/, /*uint timeStamp*/,/*uint80 answeredInRound*/) = dataFeed.latestRoundData();
            require(oracle_decimals > 0 && answer > 0, "Bad oracle data!");
            curr_price = curr_price*(10**oracle_decimals)/uint(answer);
        }
        return curr_price;
    }

    function readPrice(address base_addr, uint8 target_decimals, bytes calldata offchain_data) public view returns(uint)
    {
        if(base_addr == QUOTE_ADDRESS)
        {
            return 10 ** target_decimals;
        }
        require(target_decimals > 0);
        
        if(isOnchainOracle[base_addr])
        {
            return calc_chainlink_price(base_addr, target_decimals);
        }
        else
        {
            uint curr_price = 10 ** target_decimals;
            (address _base_addr, address _quote_addr, uint256 oracle_price, uint8 oracle_decimals,,) = decode_data(offchain_data);
            require(_base_addr == base_addr && _quote_addr == QUOTE_ADDRESS && oracle_decimals > 0, "Bad offchain oracle data!");
            curr_price = curr_price * oracle_price/10**oracle_decimals;
            return curr_price;
        }       
    }

    function usePrice(address base_addr, uint8 target_decimals, bytes calldata offchain_data) public returns(uint)
    {
        if(base_addr == QUOTE_ADDRESS)
        {
            emit PriceLog(base_addr, 1, target_decimals);
            return 10 ** target_decimals;
        }
        require(target_decimals > 0);
        uint curr_price;
        if(isOnchainOracle[base_addr])
        {         
            curr_price = calc_chainlink_price(base_addr, target_decimals);
        }
        else
        {
            curr_price = 10 ** target_decimals;
            (address _base_addr, address _quote_addr, uint256 oracle_price, uint8 oracle_decimals,,) = decode_data_and_update_expiry(offchain_data);
            require(_base_addr == base_addr && _quote_addr == QUOTE_ADDRESS && oracle_decimals > 0, "Bad offchain oracle data!");
            curr_price = curr_price * oracle_price/10**oracle_decimals;
        }
        emit PriceLog(base_addr, curr_price, target_decimals);
        return curr_price;
    }

    function readAbsoluteCollateralValue(address base_addr, uint base_amount, uint8 base_decimals, bytes calldata offchain_data) public view returns(uint) 
    {
        uint price = readPrice(base_addr, PRECISION, offchain_data);
        return base_amount*price/(10**base_decimals)*(10**QUOTE_DECIMALS)/(10**PRECISION);
    }

    function useAbsoluteCollateralValue(address base_addr, uint base_amount, uint8 base_decimals, bytes calldata offchain_data) public returns(uint) 
    {
        uint price = usePrice(base_addr, PRECISION, offchain_data);
        return base_amount*price/(10**base_decimals)*(10**QUOTE_DECIMALS)/(10**PRECISION);
    }

    function readQuoteAmountToCollateralAmount(address base_addr, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external view returns(uint) 
    {
        uint price = readPrice(base_addr, PRECISION, offchain_data);
        return (10**PRECISION)*quote_amount/price*(10**base_decimals)/(10**QUOTE_DECIMALS);
    }

    function useQuoteAmountToCollateralAmount(address base_addr, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external returns(uint) 
    {
        uint price = usePrice(base_addr, PRECISION, offchain_data);
        return (10**PRECISION)*quote_amount/price*(10**base_decimals)/(10**QUOTE_DECIMALS);
    }

    function readRelativeCollateralValue(address base_addr, uint8 result_decimals, uint base_amount, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external view returns(uint) 
    {
        uint value = readAbsoluteCollateralValue(base_addr, base_amount, base_decimals, offchain_data);
        return (10**result_decimals)*value/quote_amount;
    }

    function useRelativeCollateralValue(address base_addr, uint8 result_decimals, uint base_amount, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external returns(uint) 
    {
        uint value = useAbsoluteCollateralValue(base_addr, base_amount, base_decimals, offchain_data);
        return (10**result_decimals)*value/quote_amount;
    }

    function readCollateralValues(address base_addr, uint8 result_decimals, uint base_amount, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external view returns(uint, uint)
    {
        uint absolute_value = readAbsoluteCollateralValue(base_addr, base_amount, base_decimals, offchain_data);
        return (absolute_value, (10**result_decimals)*absolute_value/quote_amount); 
    }

    function useCollateralValues(address base_addr, uint8 result_decimals, uint base_amount, uint8 base_decimals, uint quote_amount, bytes calldata offchain_data) external returns(uint, uint)
    {
        uint absolute_value = useAbsoluteCollateralValue(base_addr, base_amount, base_decimals, offchain_data);
        return (absolute_value, (10**result_decimals)*absolute_value/quote_amount); 
    }

    function setOracles(address base_addr, address[] calldata mul, address[] calldata div) external onlyOwner
    {
        require(!isOnchainOracle[base_addr], "Oracle is already set!");
        path_mul[base_addr] = mul;
        path_div[base_addr] = div;
        isOnchainOracle[base_addr] = true;
        emit OnChainOracleAdded(base_addr, mul, div);
    }

    function setSigner(address signer, bool state) external onlyOwner 
    {
        set_signer(signer, state);
    }

    function quoteToken() external view returns(address)
    {
        return QUOTE_ADDRESS;
    }

}
