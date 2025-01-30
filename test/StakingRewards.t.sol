// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StakingRewards} from "../src/StakingRewards.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract StakingRewardsTest is Test {
    StakingRewards public stakingRewards;
    MockERC20 public rewardsToken;
    MockERC20 public stakingToken;

    address owner = makeAddr("owner");
    address rewardsDistribution = makeAddr("rewardsDistribution");
    address Alice = makeAddr("Alice");
    address Bob = makeAddr("Bob");

    function setUp() public {
        rewardsToken = new MockERC20("Rewards", "RWD");
        stakingToken = new MockERC20("Staking", "STK");

        stakingRewards = new StakingRewards(owner, rewardsDistribution, address(rewardsToken), address(stakingToken));

        // Setup initial state for testing
        stakingToken.mint(Alice, 1000e18);
        vm.prank(Alice);
        stakingToken.approve(address(stakingRewards), type(uint256).max);
    }

    function testStake() public {
        _stakeAlice(888e18);
    }

    function testGetReward() public {
        _stakeAlice(888e18);

        vm.warp(block.timestamp + 5 days);
        stakingRewards.getReward();
    }

    function testWithdraw() public {
        uint256 amount = 888e18;
        _stakeAlice(amount);

        uint256 stakingBalBefore = stakingRewards.balanceOf(Alice);
        uint256 tokenBalBefore = stakingToken.balanceOf(Alice);

        uint256 withdrawAmount = amount / 2;

        vm.startPrank(Alice);
        stakingRewards.withdraw(withdrawAmount);
        vm.stopPrank();

        uint256 stakingBalAfter = stakingRewards.balanceOf(Alice);
        uint256 tokenBalAfter = stakingToken.balanceOf(Alice);

        assertEq(
            stakingBalAfter,
            stakingBalBefore - withdrawAmount,
            "stakingBalAfter should be stakingBalBefore - withdrawAmount"
        );
        assertEq(
            tokenBalAfter, tokenBalBefore + withdrawAmount, "tokenBalAfter should be tokenBalBefore + withdrawAmount"
        );
    }

    function _stakeAlice(uint256 amount) internal {
        vm.startPrank(Alice);
        stakingToken.approve(address(stakingRewards), type(uint256).max);
        stakingRewards.stake(amount);
        vm.stopPrank();

        uint256 totalSupply = stakingRewards.totalSupply();
        console.log("totalSupply", totalSupply);
        assertEq(totalSupply, amount, "totalSupply should be amount");

        uint256 balanceOfAlice = stakingRewards.balanceOf(Alice);
        console.log("balanceOfAlice", balanceOfAlice);
        assertEq(balanceOfAlice, amount, "balanceOfAlice should be amount");
    }

    function testExit() public {
        _stakeAlice(888e18);

        uint256 stakingBalBefore = stakingRewards.balanceOf(Alice);
        uint256 tokenBalBefore = stakingToken.balanceOf(Alice);

        vm.startPrank(Alice);
        vm.warp(block.timestamp + 5 days);
        stakingRewards.exit();
        vm.stopPrank();

        uint256 stakingBalAfter = stakingRewards.balanceOf(Alice);
        uint256 tokenBalAfter = stakingToken.balanceOf(Alice);

        assertEq(stakingBalAfter, 0, "stakingBalAfter should be 0");
        assertEq(
            tokenBalAfter,
            tokenBalBefore + stakingBalBefore,
            "tokenBalAfter should be tokenBalBefore + stakingBalBefore"
        );
    }
}
