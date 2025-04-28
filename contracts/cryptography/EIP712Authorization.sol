// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract EIP712Authorization is EIP712
{
    mapping (address => bool) private _signers;
    mapping (bytes => bool) private _signatures;
    event SignerChanged(address signer, bool is_authorized);

    constructor(string memory name, string memory version) EIP712(name, version)
    { }

    function validateTypedData(bytes32 structHash, bytes memory signature) internal returns (address)
    {
        require(_signatures[signature] == false, "EIP712Authorization:Used signature!");
        address signer = recoverSigner(structHash, signature);
        require(signer != address(0) && _signers[signer] == true, "EIP712Authorization:Not authorized!");
        _signatures[signature] = true;
        return signer;
    }

    function isAuthorizedSigner(address _signer) public view returns (bool)
    {
        return _signers[_signer];
    }

    function set_signer(address _signer, bool state) internal 
    {
        _signers[_signer] = state;
        emit SignerChanged(_signer, state);
    }

    function recoverSigner(bytes32 structHash, bytes memory signature) private view returns(address) {
        return ECDSA.recover(_hashTypedDataV4(structHash), signature);
    }

}
