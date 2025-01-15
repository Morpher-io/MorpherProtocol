const fs = require('node:fs');
const path = require('node:path');

const NETWORKS = {
    1: {
        name: 'Ethereum Mainnet',
        apiKey: process.env.ETHERSCAN_KEY,
        apiUrl: 'https://api.etherscan.io'
    },
    11155111: {
        name: 'Ethereum Sepolia',
        apiKey: process.env.ETHERSCAN_KEY,
        apiUrl: 'https://api-sepolia.etherscan.io'
    },
    137: {
        name: 'Polygon Mainnet',
        apiKey: process.env.POLYGON_KEY,
        apiUrl: 'https://api.polygonscan.com'
    },
    80002: {
        name: 'Polygon Amoy',
        apiKey: process.env.POLYGON_KEY,
        apiUrl: 'https://api-amoy.polygonscan.com'
    }
};

(async () => {
    // Clear previous contracts directory
    if (fs.existsSync('./../../contracts/prev')) {
        fs.rmSync('./../../contracts/prev', { recursive: true, force: true });
    }
    
    // Process each network
    for (const [chainId, network] of Object.entries(NETWORKS)) {
        const deploymentFile = `./../../deployments/${chainId}.json`;
        
        if (!fs.existsSync(deploymentFile)) {
            console.log(`Skipping ${network.name} - no deployment file found`);
            continue;
        }

        console.log(`\nProcessing ${network.name}...`);
        const deployment = JSON.parse(fs.readFileSync(deploymentFile, 'utf8'));
        
        for (const [contractName, address] of Object.entries(deployment)) {
            if (address && address !== "0x0") {
                console.log(`Downloading ${contractName} at ${address}`);
                await getAndWriteContract(address, network);
                await new Promise((res) => setTimeout(res, 5000)); // Rate limit delay
            }
        }
    }
})()

async function getAndWriteContract(contractAddress, network, level = 1) {
    let content = await fetch(`${network.apiUrl}/api?module=contract&action=getsourcecode&address=${contractAddress}&apikey=${network.apiKey}`)
    let json = await content.json();

    try {
        //multi part json file, remove the double curly brackets at the beginning and end, no idea why they are here {{ ... }}
        let multiPartSourceCode = JSON.parse(json.result[0].SourceCode.substring(1, json.result[0].SourceCode.length - 1));
        const files = Object.keys(multiPartSourceCode.sources)
        for (const file of files) {
            
            try {
                if (!fs.existsSync(`./../../contracts/prev/${path.dirname(file.replace('@openzeppelin/', 'contracts/@openzeppelin/'))}`)) {
                    fs.mkdirSync(`./../../contracts/prev/${path.dirname(file.replace('@openzeppelin/', 'contracts/@openzeppelin/'))}`, { recursive: true });
                }

                fs.writeFileSync(`./../../contracts/prev/${file.replace('@openzeppelin/', 'contracts/@openzeppelin/')}`, multiPartSourceCode.sources[file].content);
                console.log(`Written ${file}`);
                // file written successfully
            } catch (err) {
                console.error(err);
            }
        }
    } catch (e) {
        console.error(e);
        console.error(json);
        try {
            if (!fs.existsSync(`./../../contracts/prev/`)) {
                fs.mkdirSync(`./../../contracts/prev/`, { recursive: true });
            }
            fs.writeFileSync(`./../../contracts/prev/${json.result[0].ContractName}.sol`, json.result[0].SourceCode);
            // file written successfully
            console.log(`Written ${json.result[0].ContractName}.sol`)
        } catch (err) {
            console.error(err);
        }
    }



    if (json.result[0].Implementation != '' && level < 2) {
        await new Promise((res) => setTimeout(res, 5000))
        await getAndWriteContract(json.result[0].Implementation);
    }
}
