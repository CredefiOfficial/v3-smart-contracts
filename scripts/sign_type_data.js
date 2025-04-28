// Right click on the script name and hit "Run" to execute
(async () => {
    try {
        console.log('Running Credi sign test...')
        const account = (await web3.eth.getAccounts())[0];

//        console.log(web3.utils.randomHex(32))

        console.log("address", account)

        const name = "CREDIWhalesStaking";
        const version = "1.0";
        const chain_id = await web3.eth.getChainId();
        const contract_address = "0x6270a116bFC60ee9c719c0E8277140De4B75317a";
        const salt = "0xbc359f5dccf5c5e94aa42b0e7ef42abe753b0ae17f8e63d5809f3b8e938adc75";
        
        const domain_separator = domainSeparator(name, version, chain_id, contract_address, salt); 
        
        console.log("domain", domain_separator);
        console.log( web3.utils.keccak256(web3.utils.utf8ToHex("TestCall(address sender,uint256 money)")));
//        console.log( mintWithHash("0xF1F6720d4515934328896D37D356627522D97B49", 3, 777, [1]))
        var typed_data = toTypedDataHash(domain_separator, TestCall("0x7E8b3674735b99Def2c685d945038001dB18a6E3", 100));
        console.log("data hash", TestCall("0x7E8b3674735b99Def2c685d945038001dB18a6E3", 100))
        console.log("typed data", typed_data);
        
        //console.log( await web3.eth.sign(typed_data, account))

       // console.log( await web3.eth.accounts.signMessageWithPrivateKey(typed_data, "0xpk"))
    
    } catch (e) {
        console.log(e.message)
    }
})()

function TestCall(sender, money)
{
    return  web3.utils.keccak256(web3.eth.abi.encodeParameters(["bytes32", "address", "uint256"],[
            web3.utils.keccak256(web3.utils.utf8ToHex("TestCall(address sender,uint256 money)")),
            sender,
            money]));
}

function mintWithHash(to, tokenId, withdrawId, metadata)
{
//    console.log("mint with hash type hash", web3.utils.keccak256(web3.utils.utf8ToHex("mintWithHash(address to,uint256 tokenId,uint256 withdrawId)")))
    return metadata.length == 0 ? 
        web3.utils.keccak256(web3.eth.abi.encodeParameters(["bytes32", "address", "uint256", "uint256"], [
            web3.utils.keccak256(web3.utils.utf8ToHex("mintWithHash(address to,uint256 tokenId,uint256 withdrawId)")),
            to,
            tokenId,
            withdrawId
        ])) :
        web3.utils.keccak256(web3.eth.abi.encodeParameters(["bytes32", "address", "uint256", "uint256", "bytes32"], [
            web3.utils.keccak256(web3.utils.utf8ToHex("mintWithHash(address to,uint256 tokenId,uint256 withdrawId,uint256[] metadata)")),
            to,
            tokenId,
            withdrawId,
            web3.utils.keccak256(web3.eth.abi.encodeParameter(`uint256[${metadata.length}]`, metadata))
        ]))
}

function domainSeparator(name, version, chainId, verifyingContract, salt)
{
    const type_hash = web3.utils.keccak256(web3.utils.utf8ToHex("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)"));
    const name_hash = web3.utils.keccak256(web3.utils.utf8ToHex(name));
    const version_hash = web3.utils.keccak256(web3.utils.utf8ToHex(version));
    return web3.utils.keccak256(web3.eth.abi.encodeParameters(["bytes32", "bytes32", "bytes32", "uint256", "address", "bytes32"], [type_hash, name_hash, version_hash, chainId, verifyingContract, salt])); 
}

function toTypedDataHash(domainSeparator, structHash)
{
    return web3.utils.keccak256(web3.utils.encodePacked("\x19\x01", domainSeparator, structHash));
}