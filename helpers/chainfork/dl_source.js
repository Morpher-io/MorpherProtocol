const fs = require('node:fs');
const path = require('node:path');
(async () => {
    console.log("Downloading old contracts for comparison");
    await getAndWriteContract("0x1ce1efda5d52de421bd3bc1ccc85977d7a0a0f1e"); //MorpherState
    await new Promise((res) => setTimeout(res, 5000));
    await getAndWriteContract("0x21Fd95b46FC655BfF75a8E74267Cfdc7efEBdb6A"); //MorpherOracle
    // await new Promise((res) => setTimeout(res, 5000));
    // await getAndWriteContract("0x65C9e3289e5949134759119DBc9F862E8d6F2fBE"); //MorpherToken - getting downloaded via MorpherState
    await new Promise((res) => setTimeout(res, 5000));
    await getAndWriteContract("0x005cb9Ad7C713bfF25ED07F3d9e1C3945e543cd5"); 
})()

async function getAndWriteContract(contractAddress, level = 1) {
    //can load a few free requests before limiting without API key...
    let content = await fetch(`https://api.polygonscan.com/api?module=contract&action=getsourcecode&address=${contractAddress}&apikey=${process.env.POLYGON_KEY}`)
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