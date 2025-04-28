// Right click on the script name and hit "Run" to execute
(async () => {
    try {
        console.log('Running Abi data sign test...')
        const account = (await web3.eth.getAccounts())[0];

//        console.log(web3.utils.randomHex(32))

        console.log("address", account);

        const type_hash = web3.utils.keccak256(web3.utils.utf8ToHex("PriceData(address base,address quote,uint256 price,uint8 decimals,uint96 issued_at,uint96 expiry)"));
        console.log(type_hash)
        const base = "0x0A5BCe3bc08608C9B4A4d88bA216fe203DA74861";
        const quote = "0xafD8A07AB35Cf9aCAbadB5f13a83d711DEbEC0B9";
        const price = "10000000000000000";
        const decimals = 18;
        const issued_at = Math.ceil(Date.now()/1000);
        const expiry = 1747993924;

        const data_abi_enc = web3.eth.abi.encodeParameters(["bytes32","address", "address", "uint256", "uint8", "uint96", "uint96"], [type_hash, base, quote, price, decimals, issued_at, expiry]);
        console.log("abi enc", data_abi_enc);

        const signature = await web3.eth.sign(data_abi_enc, account);
//        const signature = await web3.eth.personal.sign(data_abi_enc, account);
        console.log(signature)

        console.log(web3.eth.abi.encodeParameters(["bytes","bytes"], [data_abi_enc, signature]));

       // console.log( await web3.eth.accounts.signMessageWithPrivateKey(data_hash, "0xpk"))
    
    } catch (e) {
        console.log(e.message)
    }
})()

function toDataHash(data)
{
    // trqbva da se modificira signMessageWithPrivateKey da podpisva bez da he6ira i bez da slaga prefix
    return web3.utils.keccak256(web3.utils.encodePacked("\x19\x01", data));
}