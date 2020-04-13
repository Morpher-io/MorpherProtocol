const MorpherToken = artifacts.require("MorpherToken");
const MorpherState = artifacts.require("MorpherState");

contract('MorpherToken', (accounts) => {
    it('test case 1', async () => {
        // ------ MorpherToken ------
        // addressOfDeployer: transfer(testAddress1, 10^23) 
        // testAddress1: transfer(testAddress2, 10^22)
        // testAddress2: transfer(testAddress1, 10^21)
        // testAddress1: approve(testAddress2, 10^21)
        // testAddress2: transferFrom(testAddress1, testAddress2, 10^20)
        const deployerAddress = accounts[0]; const testAddress1 = accounts[1]; const testAddress2 = accounts[2];

        const morpherToken = await MorpherToken.deployed();
        const morpherState = await MorpherState.deployed();

        // Grant access and enable transfers for test accounts.
        await morpherState.grantAccess(testAddress1);
        await morpherState.grantAccess(testAddress2);
        await morpherState.enableTransfers(testAddress1);
        await morpherState.enableTransfers(testAddress2);

        await morpherToken.transfer(testAddress1, '100000000000000000000000', { from: deployerAddress });
        await morpherToken.transfer(testAddress2, '10000000000000000000000', { from: testAddress1 });
        await morpherToken.transfer(testAddress1, '1000000000000000000000', { from: testAddress2 });
        await morpherToken.approve(testAddress2, '1000000000000000000000', { from: testAddress1 });
        await morpherToken.transferFrom(testAddress1, testAddress2, '100000000000000000000', { from: testAddress2 });
        
        // ASSERTS:
        // balanceOf(addressOfDeployer) == 10^27-10^23
        // balanceOf(testAddress1) == 10^23-10^22+10^21-10^20
        // balanceOf(testAddress2) == 10^22-10^21+10^20
        // allowance(testAddress1, testAddress2) = 10^21-10^20
        const deployerBalance = await morpherState.balanceOf(deployerAddress);
        const testAddress1Balance = await morpherState.balanceOf(testAddress1)
        const testAddress2Balance = await morpherState.balanceOf(testAddress2);
        const allowance = await morpherState.getAllowance(testAddress1, testAddress2);

        assert.equal(deployerBalance.toString(), '574900000000000000000000000'); // 5.749×10^26
        assert.equal(testAddress1Balance.toString(), '90900000000000000000000'); // 9.09x10^22
        assert.equal(testAddress2Balance.toString(), '9100000000000000000000'); // 9.1x10^21
        assert.equal(allowance.toString(), '900000000000000000000'); // 9x10^20
    });
});