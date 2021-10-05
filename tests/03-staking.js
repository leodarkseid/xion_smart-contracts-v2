const {
    expectRevert,
} = require("@openzeppelin/test-helpers");
const {
    web3
} = require("@openzeppelin/test-helpers/src/setup");
const timeMachine = require('ganache-time-traveler');
const {
    assert
} = require("hardhat");

const rewardChest = artifacts.require("RewardChest");
const stakingModule = artifacts.require("StakingModule");
const vestingSpawner = artifacts.require("VestingSpawner");
const vesting = artifacts.require("Vesting");
const xgtToken = artifacts.require("XGTToken");
const freezer = artifacts.require("XGTFreezer");

const YEAR = 365 * 24 * 60 * 60;
const MONTH = 60 * 60 * 24 * 31;
const DAY = 60 * 60 * 24;

contract('Rewards', async (accounts) => {
    let admin = accounts[0];
    let users = [accounts[1], accounts[2], accounts[3]];

    let chestInstance;
    let stakingModuleInstance;
    let xgtInstance;
    let vestingSpawnerInstance;
    let freezerInstance;

    let snapshot;

    beforeEach(async () => {
        let snapshot = await timeMachine.takeSnapshot();
        snapshotId = snapshot['result'];
    });

    afterEach(async () => {
        await timeMachine.revertToSnapshot(snapshotId);
    });

    it("rewards check", async () => {
        let vestingContract = await vesting.new({
            from: admin
        });

        xgtInstance = await xgtToken.new({
            from: admin
        });

        vestingSpawnerInstance = await vestingSpawner.new(vestingContract.address, xgtInstance.address, admin, {
            from: admin
        });

        let mmAmount = web3.utils.toWei("1000000", "ether");

        chestInstance = await rewardChest.new({
            from: admin
        });

        await chestInstance.initialize(admin, xgtInstance.address, {
            from: admin
        });

        await xgtInstance.initialize(vestingSpawnerInstance.address, chestInstance.address, admin, mmAmount, {
            from: admin
        });

        freezerInstance = await freezer.new(xgtInstance.address, {
            from: admin
        });

        stakingModuleInstance = await stakingModule.new(xgtInstance.address, freezerInstance.address, chestInstance.address, {
            from: admin
        });

        // await stakingModuleInstance.initialize(xgtInstance.address, chestInstance.address, {
        //     from: admin
        // });

        await expectRevert(chestInstance.toggleModule(stakingModuleInstance.address, true, {
            from: users[0]
        }), "Ownable: caller is not the owner");

        await chestInstance.toggleModule(stakingModuleInstance.address, true, {
            from: admin
        });

        await expectRevert(stakingModuleInstance.setAuthorized(admin, true, {
            from: users[0]
        }), "Ownable: caller is not the owner");

        await stakingModuleInstance.setAuthorized(admin, true, {
            from: admin
        });

        let oneHundred = web3.utils.toWei("100", "ether");

        await xgtInstance.transfer(users[0], oneHundred, {
            from: admin
        });

        await xgtInstance.transfer(users[1], oneHundred, {
            from: admin
        });

        await xgtInstance.transfer(users[2], oneHundred, {
            from: admin
        });

        await expectRevert(stakingModuleInstance.deposit(oneHundred, {
            from: users[0]
        }), "ERC20: transfer amount exceeds allowance");

        await xgtInstance.approve(stakingModuleInstance.address, web3.utils.toWei("100", "ether"), {
            from: users[0]
        });

        await xgtInstance.approve(stakingModuleInstance.address, web3.utils.toWei("100", "ether"), {
            from: users[1]
        });

        let returnBefore = await stakingModuleInstance.getCurrentUserInfo(users[0]);
        assert.equal(returnBefore[0], 0, "info should be zero");
        assert.equal(returnBefore[1], 0, "info should be zero");
        assert.equal(returnBefore[2], 0, "info should be zero");

        await stakingModuleInstance.deposit(oneHundred, {
            from: users[0]
        });
        let balanceAfter = await stakingModuleInstance.getCurrentUserInfo(users[0])
        console.log(balanceAfter[0].toString())
        console.log(balanceAfter[1].toString())
        console.log(balanceAfter[2].toString())

        let userXGTBefore = await xgtInstance.balanceOf(users[0]);
        let contractXGTBefore = await xgtInstance.balanceOf(stakingModuleInstance.address);

        // await timeMachine.advanceTimeAndBlock(YEAR);
        for (let i = 0; i < 52; i++) {
            await timeMachine.advanceTimeAndBlock(7 * DAY - 1);
            await stakingModuleInstance.deposit(web3.utils.toWei("1.923", "ether"), {
                from: users[1]
            });
        }


        let userXGTAfter = await xgtInstance.balanceOf(users[0]);
        let contractXGTAfter = await xgtInstance.balanceOf(stakingModuleInstance.address);
        console.log(userXGTBefore.toString())
        console.log(userXGTAfter.toString())
        console.log(contractXGTBefore.toString())
        console.log(contractXGTAfter.toString())

        let contractXGTBeforeWithdraw = await xgtInstance.balanceOf(stakingModuleInstance.address);
        let userInfo = await stakingModuleInstance.getCurrentUserInfo(users[0]);
        console.log(userInfo[1].toString())
        await stakingModuleInstance.withdraw(web3.utils.toWei("50", "ether"), {
            from: users[0]
        })
        await stakingModuleInstance.withdrawAllForUser(users[0], {
            from: admin
        })
        let userInfo2 = await stakingModuleInstance.getCurrentUserInfo(users[1]);
        console.log("USER 2")
        console.log(userInfo2[0].toString())
        console.log(userInfo2[1].toString())
        console.log(userInfo2[2].toString())
        // await stakingModuleInstance.withdrawAllForUser(users[1], {
        //     from: admin
        // })
        console.log("USER 2")
        let userInfoAfter = await stakingModuleInstance.getCurrentUserInfo(users[0]);
        console.log(userInfoAfter[1].toString())
        let contractXGTAfterWithdraw = await xgtInstance.balanceOf(stakingModuleInstance.address);
        console.log(contractXGTBeforeWithdraw.toString())
        console.log(contractXGTAfterWithdraw.toString())
    });
});