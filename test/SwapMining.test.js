const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const JSBI = require('jsbi')
const ethers = require('ethers')

const WBNB = artifacts.require('WBNB');
const BSWToken = artifacts.require('BSWToken');
const MockBEP20 = artifacts.require('libs/MockBEP20');

const SwapFeeReward = artifacts.require('SwapFeeReward');
const BiswapFactory = artifacts.require('BiswapFactory');
const BiswapRouter02 = artifacts.require('BiswapRouter02');
const BiswapPair = artifacts.require('BiswapPair');

const Oracle = artifacts.require('Oracle');

const perBlock = '100';
const startBlock = '100';
function normalDecimal(a){
    if (a === 0) return 0;
    return a / 1000000000000000000;
}
function toDecimal(a){
    return a * 1000000000000000000;
}
contract('MasterChef', ([alice, bob, carol, dev, refFeeAddr, feeAddr, minter]) => {
    beforeEach(async () => {
        this.deadline = function(){
            return ethers.BigNumber.from(Math.ceil(Date.now() / 1000) + 20*60).toHexString()
        }
        this.sleep = function(ms) {
            return new Promise(resolve => setTimeout(resolve, ms));
        };
        
        this.bsw = await BSWToken.new({ from: minter });
        this.wbnb = await WBNB.new({ from: minter });

        // this.usdt = await MockBEP20.new('USDT', 'USTD', '1000000', { from: minter });
        this.tokenA = await MockBEP20.new('Token A', 'TKA', JSBI.BigInt(toDecimal('1000000000000000')).toString(), { from: minter });
        this.tokenB = await MockBEP20.new('Token B', 'TKB', JSBI.BigInt(toDecimal('1000000000000000')).toString(), { from: minter });
        this.tokenC = await MockBEP20.new('Token C', 'TKC', JSBI.BigInt(toDecimal('1000000000000000')).toString(), { from: minter });

        this.factory = await BiswapFactory.new(minter, { from: minter });
        let INIT_CODE_HASH = await this.factory.INIT_CODE_HASH();
        await this.factory.setFeeTo(feeAddr, { from: minter });
        console.log(await this.factory.feeTo());
        this.router = await BiswapRouter02.new(this.factory.address, this.wbnb.address, { from: minter });
        

        this.oracle = await Oracle.new(this.factory.address, INIT_CODE_HASH, { from: minter });

        this.SwapFeeReward = await SwapFeeReward.new(
            this.factory.address,
            this.router.address,
            INIT_CODE_HASH,
            this.bsw.address,
            this.oracle.address,
            this.tokenC.address
        );
        await this.router.setSwapFeeReward(this.SwapFeeReward.address, { from: minter });
        await this.SwapFeeReward.addWhitelist(this.tokenA.address);
        await this.SwapFeeReward.addWhitelist(this.tokenB.address);
        await this.SwapFeeReward.addWhitelist(this.tokenC.address);

        await this.bsw.addMinter(this.SwapFeeReward.address, { from: minter });

        await this.tokenA.transfer(alice, JSBI.BigInt(toDecimal('1000000000000000')).toString(10), { from: minter });
        await this.tokenB.transfer(alice, JSBI.BigInt(toDecimal('1000000000000000')).toString(10), { from: minter });
        await this.tokenC.transfer(alice, JSBI.BigInt(toDecimal('1000000000000000')).toString(10), { from: minter });

        await this.tokenA.approve(this.router.address, JSBI.BigInt(toDecimal('1000000000000000')).toString(10), { from: alice });
        await this.tokenB.approve(this.router.address, JSBI.BigInt(toDecimal('1000000000000000')).toString(10), { from: alice });
        await this.tokenC.approve(this.router.address, JSBI.BigInt(toDecimal('1000000000000000')).toString(10), { from: alice });
        
        let amountLiqudityA = "284495381003432731316116";
        let amountLiqudityB = "15087710864450785846274";
        await this.router.addLiquidity(
            this.tokenA.address,
            this.tokenB.address,
            amountLiqudityA,
            amountLiqudityB,
            amountLiqudityA,
            amountLiqudityB,
            alice,
            this.deadline(),
            { from: alice }
        );
        amountLiqudityB = '141687832029454432573396';
        let amountLiqudityC = '85831437153686977543215154';
        await this.router.addLiquidity(
            this.tokenB.address,
            this.tokenC.address,
            amountLiqudityB,
            amountLiqudityC,
            amountLiqudityB,
            amountLiqudityC,
            alice,
            this.deadline(),
            { from: alice }
        )

        let pair1 = await this.SwapFeeReward.getPairAddress(this.tokenA.address, this.tokenB.address);
        let pair2 = await this.SwapFeeReward.getPairAddress(this.tokenB.address, this.tokenC.address);
        
        await this.SwapFeeReward.addPair("100", pair1);
        await this.SwapFeeReward.addPair("100", pair2);

        let tokeALp1 = await this.tokenA.balanceOf(pair1);
        let tokeBLp1 = await this.tokenB.balanceOf(pair1);
        let aliceTokenB = await this.tokenB.balanceOf(alice);

        console.log('alice tokenB balance: ', aliceTokenB.toString())
        console.log('balance tokenA in pair: ', tokeALp1.toString());
        console.log('balance tokenB in pair: ', tokeBLp1.toString());
        
        await this.oracle.update(this.tokenA.address, this.tokenB.address);
        await this.oracle.update(this.tokenB.address, this.tokenC.address);

        await time.advanceBlockTo('1100');

        let amountToSwap = 100;
        let path = [this.tokenA.address, this.tokenB.address];
        let amountsOut = await this.router.getAmountsOut(JSBI.BigInt(toDecimal(amountToSwap)).toString(10), path);
        let params = [
            amountsOut[0],
            amountsOut[1],
            path,
            alice,
            this.deadline()
        ];
        let status = await this.router.swapExactTokensForTokens(...params, { from: alice });

        let tokeALp1AfterSwap = await this.tokenA.balanceOf(pair1);
        let tokeBLp1AfterSwap = await this.tokenB.balanceOf(pair1);
        let aliceTokenBAfterSwap = await this.tokenB.balanceOf(alice);

        console.log('alice tokenB balance: ', aliceTokenB.sub(aliceTokenBAfterSwap).toString())
        console.log('balance tokenA in pair: ', tokeALp1AfterSwap.sub(tokeALp1).toString());
        console.log('balance tokenB in pair: ', tokeBLp1.sub(tokeBLp1AfterSwap).toString());
        console.log('----');
        amountsOut = await this.router.getAmountsOut(JSBI.BigInt(toDecimal('10')).toString(10), path);
        await this.router.addLiquidity(
            this.tokenA.address,
            this.tokenB.address,
            amountsOut[0],
            amountsOut[1],
            0,
            0,
            alice,
            this.deadline(),
            { from: alice }
        )

        let tokeALp1AfterLiquid = await this.tokenA.balanceOf(pair1);
        let tokeBLp1AfterLiquid = await this.tokenB.balanceOf(pair1);
        let aliceTokenBAfterLiquid = await this.tokenB.balanceOf(alice);

        console.log('alice tokenB balance: ', aliceTokenBAfterSwap.sub(aliceTokenBAfterLiquid).toString())
        console.log('balance tokenA in pair: ', tokeALp1AfterLiquid.sub(tokeALp1AfterSwap).toString());
        console.log('balance tokenB in pair: ', tokeBLp1AfterSwap.sub(tokeBLp1AfterLiquid).toString());
        console.log('----');

        console.log('balance: ', normalDecimal( (await this.SwapFeeReward.rewardBalance({ from: alice })).toString()));

        await this.SwapFeeReward.withdraw({ from: alice });


        console.log('balance reward: ', (await this.SwapFeeReward.rewardBalance({ from: alice })).toString());
        console.log('balance bsw: ', (await this.bsw.balanceOf(alice, { from: alice })).toString());
        console.log('total bsw: ', (await this.bsw.totalSupply({ from: alice })).toString());

    });
    it('real case', async () => {
    
    })

});
