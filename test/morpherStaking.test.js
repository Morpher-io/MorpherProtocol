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
            return ev.userAddress === account1 && ev.amount.toString() === '100000000000000000000000'; //poolshares cannot be easily defined, as they change with the rounding errors of the days * interestRate passed
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

        await truffleAssert.fails(staking.stake(95, { from: account1 }), truffleAssert.ErrorType.REVERT, 'MorpherStaking: stake amount lower than minimum stake');
    });

});

contract('MorpherStaking: Administrative Actions', (accounts) => {
    const [deployer, account1, account2] = accounts;
    it('moving staking admin to another address', async () => {

        const staking = await MorpherStaking.deployed();
        const stakingAdmin = await staking.stakingAdmin();
        await staking.setStakingAdmin(account1);
        let result = await staking.setMinimumStake(web3.utils.toWei('1','ether'), { from: account1 });
        await truffleAssert.eventEmitted(result, 'SetMinimumStake');
        await truffleAssert.fails(staking.setInterestRate(web3.utils.toWei('100','ether'), { from: account2 }), truffleAssert.ErrorType.REVERT, 'MorpherStaking: can only be called by Staking Administrator.');
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


contract('MorpherStaking: Interest Rate Actions', (accounts) => {
    const [deployer, account1, account2] = accounts;
    it('has a default interest rate', async() => {
        const staking = await MorpherStaking.deployed();
        const interestRate = await staking.interestRate();
        assert.equal(interestRate.toString(), '15000');
    })
    it('add Interest Rate', async () => {

        const staking = await MorpherStaking.deployed();
        const result = await staking.addInterestRate('30000', Math.round((Date.now() / 1000) + (60*60*24)));
        await truffleAssert.eventEmitted(result, "InterestRateAdded")
    });

    it('add Interest Rate with a past validFrom rate fails', async () => {
        const staking = await MorpherStaking.deployed();
        await truffleAssert.fails(staking.addInterestRate('50000', Math.round(Date.now() / 1000)), truffleAssert.ErrorType.REVERT, 'MorpherStaking: Interest Rate Valid From must be later than last interestRate');
        
    });

    it('change interest rate', async () => {
        const staking = await MorpherStaking.deployed();
        const result = await staking.changeInterestRateValue(0, 20000);
        await truffleAssert.eventEmitted(result, "InterestRateRateChanged");
        const interestRateAfterChange = await staking.interestRate();
        assert.equal(interestRateAfterChange.toString(), '20000');
        await staking.changeInterestRateValue(0, 15000);

    });

    it('deactivate/activate Interest Rate', async () => {
        const staking = await MorpherStaking.deployed();
        const result = await staking.changeInterestRateActive(0, false);
        await truffleAssert.eventEmitted(result, "InterestRateActiveChanged");
        const interestRateAfterChange = await staking.interestRates(0);
        assert.equal(interestRateAfterChange.active, false);
        await staking.changeInterestRateActive(0, true);
    });

    it('is possible to change the valid From date of interest rates', async() =>{
        const staking = await MorpherStaking.deployed();
        
        const firstInterestRate = await staking.interestRates(0);
        const result = await staking.changeInterestRateValidFrom(1, Math.round((Date.now()/1000) - ((Date.now() / 1000) - firstInterestRate.validFrom.toNumber())/2)); //set back the valid from to halfway in the past, so the average right now should be (15000+30000)/2=22500
        await truffleAssert.eventEmitted(result, "InterestRateValidFromChanged");
    })

    it('position interest rate for past position', async () => {
        const staking = await MorpherStaking.deployed();
        const firstInterestRate = await staking.interestRates(0);
        const result = await staking.getInterestRate(firstInterestRate.validFrom); //get the interest rate from a position opened at the creation date of the first interest rate
        //it should be a weighted average of 15000 and 30000, which in this case is 50:50 with a little rounding error
        if(result.toString() == '22499') {
            assert.equal(result.toString(), '22499');
        } else {
            assert.equal(result.toString(), '22500');
        }
    });

});
