// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RewardsDistributionRecipient} from "./RewardsDistributionRecipient.sol";
import {Pausable} from "./Pausable.sol";
import {Owned} from "./Owned.sol";
import {Test, console} from "forge-std/Test.sol";

contract StakingRewardsOptimized is Pausable, RewardsDistributionRecipient, ReentrancyGuard {
    // *✦✧✶✧✦.* SLOT 5 *.✦✧✶✧✦ //
    IERC20 public stakingToken;
    uint32 public periodFinish;
    uint32 public lastUpdateTime;
    uint32 public rewardsDuration = 7 days;

    // *✦✧✶✧✦.* SLOT 6 *.✦✧✶✧✦ //
    IERC20 public rewardsToken;

    // *✦✧✶✧✦.* SLOT 7 *.✦✧✶✧✦ //
    uint256 public rewardRate = 0;

    // *✦✧✶✧✦.* SLOT 8 *.✦✧✶✧✦ //
    uint256 public rewardPerTokenStored;

    // *✦✧✶✧✦.* SLOT 9 *.✦✧✶✧✦ //
    mapping(address => uint256) public userRewardPerTokenPaid;

    // *✦✧✶✧✦.* SLOT 10 *.✦✧✶✧✦ //
    mapping(address => uint256) public rewards;

    // *✦✧✶✧✦.* SLOT 11 *.✦✧✶✧✦ //
    uint256 private _totalSupply;

    // *✦✧✶✧✦.* SLOT 12 *.✦✧✶✧✦ //
    mapping(address => uint256) private _balances;

    uint256 private constant SLOT_PACKED = 5;
    uint256 private constant SLOT_REWARDS_TOKEN = 6;
    uint256 private constant SLOT_REWARD_RATE = 7;
    uint256 private constant SLOT_REWARD_PER_TOKEN_STORED = 8;
    uint256 private constant SLOT_USER_REWARD_PER_TOKEN_PAID = 9;
    uint256 private constant SLOT_REWARDS = 10;
    uint256 private constant SLOT_TOTAL_SUPPLY = 11;
    uint256 private constant SLOT_BALANCES = 12;

    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /*                       CUSTOM ERRORS                    */
    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    error AmountStakedIsZero();
    error AmountWithdrawnIsZero();
    error RewardPeriodNotFinished();
    error RewardTooHigh();
    error TokenStakedIsInvalid();
    error SafeERC20FailedOperation();

    uint256 private constant AmountStakedIsZeroSelector = 0x6e0ff7cf;
    uint256 private constant AmountWithdrawnIsZeroSelector = 0xc5c5eb74;
    uint256 private constant RewardPeriodNotFinishedSelector = 0x9634abc1;
    uint256 private constant RewardTooHighSelector = 0x474c2471;
    uint256 private constant TokenStakedIsInvalidSelector = 0x7444d4aa;
    uint256 private constant SafeERC20FailedOperationSelector = 0x70c9c181;

    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /*                         EVENTS                         */
    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    event RewardAdded(uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    uint256 private constant RewardsDurationUpdatedSig =
        0xfb46ca5a5e06d4540d6387b930a7c978bce0db5f449ec6b3f5d07c6e1d44f2d3;
    uint256 private constant RewardAddedSig = 0xde88a922e0d3b88b24e9623efeb464919c6bf9f66857a65e2bfcf2ce87a9433d;
    uint256 private constant RecoveredSig = 0x8c1256b8896378cd5044f80c202f9772b9d77dc85c8a6eb51967210b09bfaa28;
    uint256 private constant StakedSig = 0x9e71bc8eea02a63969f509818f2dafb9254532904319f9dbda79b67bd34a5f3d;
    uint256 private constant WithdrawnSig = 0x7084f5476618d8e60b11ef0d7d3f06914655adb8793e28ff7f018d4c76d505d5;
    uint256 private constant RewardPaidSig = 0xe2403640ba68fed3a2f88b7557551d1993f84b99bb10ff833f0cf8db0c5e0486;

    constructor(address _owner, address _rewardsDistribution, address _rewardsToken, address _stakingToken)
        payable
        Owned(_owner)
        ReentrancyGuard()
    {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        rewardsDistribution = _rewardsDistribution;
    }

    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /*                         VIEWS                          */
    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    function getValuesBySlot(uint256 slot)
        external
        view
        returns (address _stakingToken, uint32 _periodFinish, uint32 _lastUpdateTime, uint32 _rewardsDuration)
    {
        assembly {
            let combined := sload(slot)

            _stakingToken := and(combined, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            _periodFinish := and(shr(160, combined), 0xFFFFFFFF)
            _lastUpdateTime := and(shr(192, combined), 0xFFFFFFFF)
            _rewardsDuration := shr(224, combined)
        }
    }

    function getSlotNumber()
        external
        pure
        returns (
            uint256 _stakingToken,
            uint256 totalSupply,
            uint256 balances,
            uint256 _rewardPerTokenStored,
            uint256 _rewardRate,
            uint256 _rewards,
            uint256 _rewardsToken
        )
    {
        assembly {
            _stakingToken := stakingToken.slot
            totalSupply := _totalSupply.slot
            balances := _balances.slot
            _rewardPerTokenStored := rewardPerTokenStored.slot
            _rewardRate := rewardRate.slot
            _rewards := rewards.slot
            _rewardsToken := rewardsToken.slot
        }
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / _totalSupply);
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant notPaused {
        _updateReward(msg.sender);
        _require(amount > 0, AmountStakedIsZeroSelector);

        uint256 returnSize;
        uint256 returnValue;
        address token;

        assembly {
            let offset := mload(0x40)
            mstore(offset, caller())
            mstore(add(offset, 0x20), SLOT_BALANCES)
            let slotBalances := keccak256(offset, 0x40)
            let senderBal := sload(slotBalances)
            let newBal := add(senderBal, amount)

            if iszero(iszero(lt(newBal, senderBal))) { revert(0, 0) }
            sstore(slotBalances, newBal)

            let supply := sload(SLOT_TOTAL_SUPPLY)
            let newSupply := add(supply, amount)

            if iszero(iszero(lt(newSupply, supply))) { revert(0, 0) }
            sstore(SLOT_TOTAL_SUPPLY, newSupply)

            let tokenSlot := sload(SLOT_PACKED)
            token := and(tokenSlot, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)

            mstore(offset, 0x23b872dd)
            mstore(add(offset, 0x20), caller())
            mstore(add(offset, 0x40), address())
            mstore(add(offset, 0x60), amount)
            let success := call(gas(), token, 0, add(offset, 0x1c), 0x80, 0, 0)

            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        _require(returnSize == 0 ? address(token).code.length == 0 : returnValue != 1, SafeERC20FailedOperationSelector);
        _log2(StakedSig, amount);
    }

    function withdraw(uint256 amount) public nonReentrant {
        _updateReward(msg.sender);
        _require(amount > 0, AmountWithdrawnIsZeroSelector);
        address token;

        assembly {
            let offset := mload(0x40)
            mstore(offset, caller())
            mstore(add(offset, 0x20), SLOT_BALANCES)
            let slot := keccak256(offset, 0x40)
            let senderBal := sload(slot)
            let newBal := sub(senderBal, amount)

            if iszero(iszero(gt(newBal, senderBal))) { revert(0, 0) }
            sstore(slot, newBal)

            let supply := sload(SLOT_TOTAL_SUPPLY)
            let newSupply := sub(supply, amount)

            if iszero(iszero(gt(newSupply, supply))) { revert(0, 0) }
            sstore(SLOT_TOTAL_SUPPLY, newSupply)
            let data := sload(SLOT_PACKED)
            token := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }

        _safeTransfer(token, amount, WithdrawnSig);
    }

    function getReward() public nonReentrant {
        _updateReward(msg.sender);
        uint256 amount;
        address token;

        assembly {
            let offset := mload(0x40)
            mstore(offset, caller())
            mstore(add(offset, 0x20), SLOT_REWARDS)

            let slot := keccak256(offset, 0x40)
            amount := sload(slot)

            if iszero(amount) { return(0, 0) }
            sstore(slot, 0)
            token := sload(SLOT_REWARDS_TOKEN)
        }

        _safeTransfer(token, amount, RewardPaidSig);
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external override onlyRewardsDistribution {
        _updateReward(address(0));
        uint256 _rewardsDuration = rewardsDuration;
        uint256 _rewardRate = rewardRate;
        uint256 _periodFinish = periodFinish;

        if (block.timestamp >= _periodFinish) {
            _rewardRate = _rewardRate / _rewardsDuration;
        } else {
            uint256 leftover = (_periodFinish - block.timestamp) * _rewardRate;
            _rewardRate = (reward + leftover) / _rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardsToken.balanceOf(address(this));
        _require(rewardRate <= balance / _rewardsDuration, RewardTooHighSelector);

        lastUpdateTime = uint32(block.timestamp);
        periodFinish = uint32(block.timestamp + _rewardsDuration);
        rewardRate = _rewardRate;
        _log1(RewardAddedSig, reward);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        _require(tokenAddress != address(stakingToken), TokenStakedIsInvalidSelector);
        _safeTransfer(tokenAddress, tokenAmount, RecoveredSig);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        _require(block.timestamp > periodFinish, RewardPeriodNotFinishedSelector);
        uint32 newRewardsDuration = uint32(_rewardsDuration);
        rewardsDuration = newRewardsDuration;
        _log1(RewardsDurationUpdatedSig, newRewardsDuration);
    }

    function _safeTransfer(address token, uint256 amount, uint256 selector) private {
        uint256 returnSize;
        uint256 returnValue;

        assembly {
            let offset := mload(0x40)

            mstore(offset, 0xa9059cbb)
            mstore(add(offset, 0x20), caller())
            mstore(add(offset, 0x40), amount)
            let success := call(gas(), token, 0, add(offset, 0x1c), 0x60, 0x00, 0x00)

            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        _require(returnSize == 0 ? address(token).code.length == 0 : returnValue != 1, SafeERC20FailedOperationSelector);
        _log2(selector, amount);
    }

    function _updateReward(address account) private {
        uint256 _rewardPerToken = rewardPerToken();
        lastUpdateTime = uint32(lastTimeRewardApplicable());

        assembly {
            let offset := mload(0x40)
            sstore(SLOT_REWARD_PER_TOKEN_STORED, _rewardPerToken)

            if iszero(account) { return(0, 0) }

            mstore(offset, account)
            mstore(add(offset, 0x20), SLOT_BALANCES)
            let slotBalances := keccak256(offset, 0x40)
            let senderBalance := sload(slotBalances)

            mstore(offset, account)
            mstore(add(offset, 0x20), SLOT_USER_REWARD_PER_TOKEN_PAID)
            let slotUserReward := keccak256(offset, 0x40)
            let _userRewardPerTokenPaid := sload(slotUserReward)

            mstore(offset, caller())
            mstore(add(offset, 0x20), SLOT_REWARDS)
            let slotRewards := keccak256(offset, 0x40)
            let userRewards := sload(slotRewards)

            let earned :=
                add(div(mul(sub(_rewardPerToken, _userRewardPerTokenPaid), senderBalance), 0xF4240), userRewards)
            sstore(slotRewards, earned)
            sstore(slotUserReward, _rewardPerToken)
        }
    }

    function _log1(uint256 sig, uint256 value) internal {
        assembly {
            let offset := mload(0x40)
            mstore(offset, value)
            log1(offset, 0x20, sig)
        }
    }

    function _log2(uint256 sig, uint256 value) internal {
        assembly {
            let offset := mload(0x40)
            mstore(offset, value)
            log2(offset, 0x20, sig, caller())
        }
    }

    function _require(bool condition, uint256 selector) internal pure {
        assembly {
            if iszero(condition) {
                let offset := mload(0x40)
                mstore(offset, selector)

                revert(offset, 0x04)
            }
        }
    }
}
