const fs = require('node:fs');
const path = require('node:path');

//node --env-file=../../.env dl_source.js 84532
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
    84532: {
        name: 'Base Sepolia',
        apiKey: process.env.BASE_API_KEY,
        apiUrl: 'https://api-sepolia.basescan.org'
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
    const chainId = process.argv[2];
    if (!chainId || !NETWORKS[chainId]) {
        console.error('Please provide a valid chain ID as parameter.');
        console.error('Supported networks:');
        Object.entries(NETWORKS).forEach(([id, net]) => {
            console.error(`  ${id}: ${net.name}`);
        });
        process.exit(1);
    }

    const network = NETWORKS[chainId];
    const deploymentFile = `./../../deployments/${chainId}.json`;

    if (!fs.existsSync(deploymentFile)) {
        console.error(`No deployment file found for ${network.name}`);
        process.exit(1);
    }

    // Clear previous contracts directory
    if (fs.existsSync('./../../contracts/prev')) {
        fs.rmSync('./../../contracts/prev', { recursive: true, force: true });
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
})()

async function getAndWriteContract(contractAddress, network, level = 1) {
    let content = await fetch(`${network.apiUrl}/api?module=contract&action=getsourcecode&address=${contractAddress}&apikey=${network.apiKey}`)
    let json = await content.json();

    if (json.result[0].SourceCode != '') {
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
                    console.log(`Written ${file} for ${contractAddress}`);
                    // file written successfully
                } catch (err) {
                    console.error(`Error writing file ${file} for ${contractAddress}:`, err);
                }
            }
        } catch (e) {
            console.error(`Error parsing source code JSON for ${contractAddress}:`, e);
            // console.error("Raw SourceCode string:", json.result[0].SourceCode); // Uncomment for detailed debugging
            // console.error("Full API JSON response:", json); // Uncomment for detailed debugging
            try {
                // Fallback for single file source code
                const contractName = json.result[0].ContractName;
                if (!contractName) {
                   console.error(`Could not determine ContractName for single file write at ${contractAddress}. Skipping.`);
                   return;
                }
                if (!fs.existsSync(`./../../contracts/prev/`)) {
                    fs.mkdirSync(`./../../contracts/prev/`, { recursive: true });
                }
                fs.writeFileSync(`./../../contracts/prev/${json.result[0].ContractName}.sol`, json.result[0].SourceCode.replace(/@openzeppelin\/contracts-upgradeable\//g, "../lib/openzeppelin-contracts-upgradeable/contracts/"));
                // file written successfully
                console.log(`Written single file ${contractName}.sol for ${contractAddress}`);
            } catch (err) {
                console.error(`Error writing single file for ${contractAddress}:`, err);
            }
        }
    } else {
        console.log(`Skipping ${contractAddress} - Source code is empty in API response.`);
        // Optionally log the full response for debugging empty source codes:
        // console.log("API Response:", JSON.stringify(json, null, 2));
    }


    if (json.result[0].Implementation != '' && level <= 3) {
        const implementationAddress = json.result[0].Implementation;
        console.log(`Found implementation for ${contractAddress} at ${implementationAddress}. Making recursive call (level ${level + 1})...`);
        await new Promise((res) => setTimeout(res, 5000));
        await getAndWriteContract(implementationAddress, network, level + 1);
    } else if (level <= 3) {
        console.log(`No implementation address found for ${contractAddress} in API response, or level > 3.`);
    }
}
