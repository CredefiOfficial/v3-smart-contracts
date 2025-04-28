// Right click on the script name and hit "Run" to execute
(async () => {
    try {
        console.log('Running test...')
        const account = (await web3.eth.getAccounts())[0];

        console.log("address", account)
        const contractName = 'WhalesStaking' // Change this for other contract
        const artifactsPath = `browser/contracts/artifacts/${contractName}_metadata.json` // Change this for different path
    
        const metadata = JSON.parse(await remix.call('fileManager', 'getFile', artifactsPath))
        const contract_address = "0x4a9C121080f6D9250Fc0143f41B595fD172E31bf";
        const contract = new web3.eth.Contract(metadata.output.abi, contract_address)

        var pools = await contract.methods.getPool(0).call();
        console.log(pools)

    } catch (e) {
        console.log(e.message)
    }
})()
