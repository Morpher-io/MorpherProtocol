const MorpherAdministratorProxy = artifacts.require("MorpherAdministratorProxy");
const MorpherState = artifacts.require("MorpherState");

const truffleAssert = require('truffle-assertions');

let marketsToEnable = ["STOCK_AFRM", "STOCK_AAPL", "STOCK_MSFT", "CRYPTO_YFI", "STOCK_ETSY", "STOCK_DASH", "STOCK_UPST", "STOCK_POSH", "STOCK_AFRM", "STOCK_PLUG", "STOCK_SPCE", "STOCK_TR", "STOCK_ZM", "STOCK_SRNE", "STOCK_SAVE", "STOCK_PTON", "STOCK_PLTR", "CRYPTO_FIL", "CRYPTO_CRO", "CRYPTO_LINK", ];

contract('Admin Proxy', (accounts) => {
    it('test admin bulk markets enable', async () => {

        const morpherAdminProxy = await MorpherAdministratorProxy.deployed();
        const morpherState = await MorpherState.deployed();

        let adminAddressFromState = await morpherState.getAdministrator();
        if(adminAddressFromState != morpherAdminProxy.address) {
            await morpherState.setAdministrator(morpherAdminProxy.address);
        }
        

        let marketHashes = [];
        
        for(let i = 0; i < marketsToEnable.length; i++) {
            marketHashes.push(web3.utils.sha3(marketsToEnable[i]));
        }

        let txResult = await morpherAdminProxy.bulkActivateMarkets(marketHashes);
        console.log("Activating", marketsToEnable.length, "Markets cost", txResult.receipt.gasUsed, "Gas");

        for(let i = 0; i < marketHashes.length; i++) {
            let isActive = await morpherState.getMarketActive(marketHashes[i]);
            assert.equal(isActive, true);
        }

        
        if(adminAddressFromState != morpherAdminProxy.address) {
            await morpherState.setAdministrator(adminAddressFromState);
        }

    });

    
    it('test normal markets enable', async () => {

        const morpherAdminProxy = await MorpherAdministratorProxy.deployed();
        const morpherState = await MorpherState.deployed();
        const morpherStateThroughAdminProxy = await MorpherState.at(morpherAdminProxy.address);

        let adminAddressFromState = await morpherState.getAdministrator();
        if(adminAddressFromState != morpherAdminProxy.address) {
            await morpherState.setAdministrator(morpherAdminProxy.address);
        }
        //deactivate everything first
        for(let i = 0; i < marketsToEnable.length; i++) {
            await morpherStateThroughAdminProxy.deActivateMarket(web3.utils.sha3(marketsToEnable[i]));
        }

        let gasUsedSum = 0;
        
        for(let i = 0; i < marketsToEnable.length; i++) {
            let txResult = await morpherStateThroughAdminProxy.activateMarket(web3.utils.sha3(marketsToEnable[i]));
            gasUsedSum += txResult.receipt.gasUsed;
        }

        console.log("Activating", marketsToEnable.length, "Markets cost", gasUsedSum, "Gas");

        if(adminAddressFromState != morpherAdminProxy.address) {
            await morpherState.setAdministrator(adminAddressFromState);
        }

    });
});