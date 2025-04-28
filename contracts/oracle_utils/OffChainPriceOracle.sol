// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

abstract contract OffChainPriceOracle
{
    mapping (address => bool) private _signers;
    mapping (bytes32 => uint96) private _last_iat;
    bytes32 PRICE_DATA_TYPE_HASH = 0x4e24c8b160ad2b512b9e6bd61624e0c216f7fc373cb977ad891206a7db1b9dc1;

    event SignerChanged(address signer, bool is_authorized);

    function decode_data(bytes calldata data) internal view returns(address, address, uint256, uint8, uint96, uint96)
    {
        require(data.length > 0, "OffChainOracle:Invalid data!");
        (bytes memory price_data, bytes memory signature) = abi.decode(data, (bytes, bytes));     
        (bytes32 type_hash, address base, address quote, uint256 price, uint8 decimals, uint96 issued_at, uint96 expiry) = abi.decode(price_data, (bytes32, address, address, uint256, uint8, uint96, uint96));  
        require(type_hash == PRICE_DATA_TYPE_HASH, "OffChainOracle:Invalid TYPE_HASH!");
        bytes32 pair_hash = keccak256(abi.encodePacked(base, quote));
        require(uint96(block.timestamp) <= expiry && _last_iat[pair_hash] <= issued_at, "OffChainOracle:Expired data!");
        validate_signature(price_data, signature);
        return (base, quote, price, decimals, issued_at, expiry);
    }

    function decode_data_and_update_expiry(bytes calldata data) internal returns(address, address, uint256, uint8, uint96, uint96)
    {
        (address base, address quote, uint256 price, uint8 decimals, uint96 issued_at, uint96 expiry) = decode_data(data);
        _last_iat[keccak256(abi.encodePacked(base, quote))] = issued_at;
        return (base, quote, price, decimals, issued_at, expiry);
    }

    function validate_signature(bytes memory data, bytes memory signature) internal view
    {
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(data), signature);
        require(isAuthorizedSigner(signer), "OffChainOracle:Not authorized!");
    }

    function set_signer(address _signer, bool state) internal 
    {
        _signers[_signer] = state;
        emit SignerChanged(_signer, state);
    }

    function isAuthorizedSigner(address _signer) public view returns (bool)
    {
        return _signer != address(0) && _signers[_signer] == true;
    }

}
