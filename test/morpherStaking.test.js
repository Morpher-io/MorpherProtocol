const MorpherToken = artifacts.require("MorpherToken");
const MorpherStaking = artifacts.require("MorpherStaking");

const truffleAssert = require('truffle-assertions');
const BN = require("bn.js");


contract('MorpherStaking: increase/decrease staked amount', (accounts) => {
    const [deployer, account1] = accounts;

    it('staking is possible', async () => {


        const token = await MorpherToken.deployed();
        const staking = await MorpherStaking.deployed();
        await token.transfer(account1, web3.utils.toWei('1000000', 'ether'), { from: deployer }); //fill up some tokens
        let result = await staking.stake(web3.utils.toWei('100000', 'ether'), { from: account1 });
        await truffleAssert.eventEmitted(result, 'Staked', (ev) => {
            return ev.userAddress === account1 && ev.amount.toString() === '100000000000000000000000' && ev.poolShares.toString() === '1000000000000000';
        });

    });

    it('stake should be accurate', async () => {
        const staking = await MorpherStaking.deployed();
        let stake = await staking.getStake(account1);
        assert.equal(stake.toString(), '1000000000000000', 'Stake is not accurate');
    });

    it('decreasing is impossible because of lock in period', async () => {
        const staking = await MorpherStaking.deployed();
        await truffleAssert.fails(staking.unstake(1, { from: account1 }), truffleAssert.ErrorType.REVERT, 'MorpherStaking: cannot unstake before lockup expiration');
    });

    it('decreasing is impossible if lockup changed', async () => {
        const staking = await MorpherStaking.deployed();
        await staking.setLockupPeriodRate(0);
        await truffleAssert.fails(staking.unstake(1, { from: account1 }), truffleAssert.ErrorType.REVERT, 'MorpherStaking: cannot unstake before lockup expiration');
    });

    it('decreasing is possible if lockup changed and re-staked', async () => {
        const staking = await MorpherStaking.deployed();
        const totalAmount = await staking.totalShares();
        await staking.setLockupPeriodRate(0);
        let result = await staking.stake('100000000', { from: account1 }); //buy exactly one share
        await truffleAssert.eventEmitted(result, 'Staked', (ev) => {
            return ev.lockedUntil <= Math.round(Date.now() / 1000);
        });
        result = await staking.unstake(1, { from: account1 });
        await truffleAssert.eventEmitted(result, 'Unstaked', (ev) => {
            return ev.userAddress === account1 && ev.amount.toString() === '100000000' && ev.poolShares.toString() === '1';
        });

        const totalAmountAfterUnstake = await staking.totalShares();
        assert.equal(totalAmount.toString(), totalAmountAfterUnstake.toString());
    });



    it('minimumStake is accounted for', async () => {
        const staking = await MorpherStaking.deployed();

        await staking.unstake(await staking.getStake(account1), { from: account1 }); //unstake everything

        assert.equal('0', (await staking.getStake(account1)).toString());
        let result = await staking.setMinimumStake(100);
        await truffleAssert.eventEmitted(result, 'SetMinimumStake');

        await truffleAssert.fails(staking.stake(99, { from: account1 }), truffleAssert.ErrorType.REVERT, 'MorpherStaking: stake amount lower than minimum stake');
    });

});

contract('MorpherStaking: Administrative Actions', (accounts) => {
    const [deployer, account1, account2] = accounts;
    it('moving staking admin to another address', async () => {

        const staking = await MorpherStaking.deployed();
        const stakingAdmin = await staking.stakingAdmin();
        await staking.setStakingAdmin(account1);
        let result = await staking.setInterestRate(20000, { from: account1 });
        await truffleAssert.eventEmitted(result, 'SetInterestRate');
        await truffleAssert.fails(staking.setInterestRate(20000, { from: account2 }), truffleAssert.ErrorType.REVERT, 'MorpherStaking: can only be called by Staking Administrator.');
    });

    it('moving staking admin can only be done by owner', async () => {
        const staking = await MorpherStaking.deployed();
        await truffleAssert.fails(staking.setStakingAdmin(deployer, { from: account1 }), truffleAssert.ErrorType.REVERT, 'Ownable: caller should be owner.');
    });

    it('morpherStateAddress can only be set by owner', async () => {
        const staking = await MorpherStaking.deployed();
        await truffleAssert.fails(staking.setMorpherStateAddress(deployer, { from: account1 }), truffleAssert.ErrorType.REVERT, 'Ownable: caller should be owner.');
    });

    it('setLockupPeriodRate can only be called by staking admin', async () => {
        const staking = await MorpherStaking.deployed();

        let result = await staking.setLockupPeriodRate((60 * 60 * 24), { from: account1 });
        await truffleAssert.eventEmitted(result, 'SetLockupPeriod');
        let lockUpPeriod = await staking.lockupPeriod();
        assert.equal(lockUpPeriod.toString(), (60 * 60 * 24).toString());
    });

    it('setMinimumStake can only be called by staking admin', async () => {
        const staking = await MorpherStaking.deployed();

        let result = await staking.setMinimumStake(100, { from: account1 });
        await truffleAssert.eventEmitted(result, 'SetMinimumStake');
        let minimumStake = await staking.minimumStake();
        assert.equal(minimumStake.toString(), '100');
    });

});
