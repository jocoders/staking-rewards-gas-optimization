// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Owned} from "./Owned.sol";
import {Test, console} from "forge-std/Test.sol";

contract StakingRewardsOptimized is Owned, ReentrancyGuard {
    // *✦✧✶✧✦.* SLOT 3 *.✦✧✶✧✦ //
    address public rewardsDistribution;
    uint32 public lastPauseTime;
    bool public paused;

    // *✦✧✶✧✦.* SLOT 4 *.✦✧✶✧✦ //
    IERC20 public stakingToken;
    uint32 public periodFinish;
    uint32 public lastUpdateTime;
    uint32 public rewardsDuration = 7 days;

    // *✦✧✶✧✦.* SLOT 5 *.✦✧✶✧✦ //
    IERC20 public rewardsToken;

    // *✦✧✶✧✦.* SLOT 6 *.✦✧✶✧✦ //
    uint256 public rewardRate = 0;

    // *✦✧✶✧✦.* SLOT 7 *.✦✧✶✧✦ //
    uint256 public rewardPerTokenStored;

    // *✦✧✶✧✦.* SLOT 8 *.✦✧✶✧✦ //
    mapping(address => uint256) public userRewardPerTokenPaid;

    // *✦✧✶✧✦.* SLOT 9 *.✦✧✶✧✦ //
    mapping(address => uint256) public rewards;

    // *✦✧✶✧✦.* SLOT 10 *.✦✧✶✧✦ //
    uint256 public totalSupply;

    // *✦✧✶✧✦.* SLOT 11 *.✦✧✶✧✦ //
    mapping(address => uint256) private _balances;

    uint256 private constant SLOT_PAUSED = 3;
    uint256 private constant SLOT_STAKE = 4;
    uint256 private constant SLOT_REWARDS_TOKEN = 5;
    uint256 private constant SLOT_REWARD_RATE = 6;
    uint256 private constant SLOT_REWARD_PER_TOKEN_STORED = 7;
    uint256 private constant SLOT_USER_REWARD_PER_TOKEN_PAID = 8;
    uint256 private constant SLOT_REWARDS = 9;
    uint256 private constant SLOT_TOTAL_SUPPLY = 10;
    uint256 private constant SLOT_BALANCES = 11;

    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /*                       CUSTOM ERRORS                    */
    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    error AmountStakedIsZero();
    error AmountWithdrawnIsZero();
    error RewardPeriodNotFinished();
    error RewardTooHigh();
    error TokenStakedIsInvalid();
    error SafeERC20FailedOperation();
    error NotRewardsDistribution();
    error PauseChanged();

    uint256 private constant AmountStakedIsZeroSelector = 0x6e0ff7cf;
    uint256 private constant AmountWithdrawnIsZeroSelector = 0xc5c5eb74;
    uint256 private constant RewardPeriodNotFinishedSelector = 0x9634abc1;
    uint256 private constant RewardTooHighSelector = 0x474c2471;
    uint256 private constant TokenStakedIsInvalidSelector = 0x7444d4aa;
    uint256 private constant SafeERC20FailedOperationSelector = 0x70c9c181;
    uint256 private constant NotRewardsDistributionSelector = 0xf08a6a31;
    uint256 private constant PauseChangedSelector = 0xe9b8c78d;

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
    uint256 private constant PauseChangedSig = 0xde88a922e0d3b88b24e9623efeb464919c6bf9f66857a65e2bfcf2ce87a9433d;

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
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint32 _lastTime) {
        assembly {
            _lastTime := and(timestamp(), 0xFFFFFFFF)
            let _slotStake := sload(SLOT_STAKE)
            let _periodFinish := and(shr(160, _slotStake), 0xFFFFFFFF)

            if iszero(lt(_lastTime, _periodFinish)) { _lastTime := _periodFinish }
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply);
    }

    function getRewardForDuration() external view returns (uint256 _duration) {
        assembly {
            let _rewardRate := sload(SLOT_REWARD_RATE)
            let _slotStake := sload(SLOT_STAKE)
            _duration := mul(_rewardRate, shr(224, _slotStake))
        }
    }

    function getReward() public nonReentrant {
        _updateReward(msg.sender);
        uint256 _amount;
        address _token;

        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, caller())
            mstore(add(_mptr, 0x20), SLOT_REWARDS)

            let _slotNum := keccak256(_mptr, 0x40)
            _amount := sload(_slotNum)

            if iszero(_amount) { return(0, 0) }
            sstore(_slotNum, 0)
            _token := sload(SLOT_REWARDS_TOKEN)
        }

        _safeTransfer(_token, _amount, RewardPaidSig);
    }

    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /*               MUTATIVE FUNCTIONS                       */
    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    function setPaused(bool _paused) external onlyOwner {
        bool _pausedSaved;

        assembly {
            let _slotPause := sload(SLOT_PAUSED)
            _pausedSaved := and(shr(192, _slotPause), 0xFF)

            if iszero(iszero(eq(_pausedSaved, _paused))) { return(0, 0) }

            let _mptr := mload(0x40)
            mstore(_mptr, _pausedSaved)
            log1(_mptr, 0x20, PauseChangedSig)
        }

        paused = _paused;

        if (_paused) {
            lastPauseTime = uint32(block.timestamp);
        }
    }

    function stake(uint256 amount) external nonReentrant {
        _require(!paused, PauseChangedSelector);
        _updateReward(msg.sender);
        _require(amount > 0, AmountStakedIsZeroSelector);

        uint256 _returnSize;
        uint256 _returnValue;
        address _token;

        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, caller())
            mstore(add(_mptr, 0x20), SLOT_BALANCES)
            let _slotBalances := keccak256(_mptr, 0x40)
            let _senderBal := sload(_slotBalances)
            let _newBal := add(_senderBal, amount)

            if iszero(iszero(lt(_newBal, _senderBal))) { revert(0, 0) }
            sstore(_slotBalances, _newBal)

            let _supply := sload(SLOT_TOTAL_SUPPLY)
            let _newSupply := add(_supply, amount)

            if iszero(iszero(lt(_newSupply, _supply))) { revert(0, 0) }
            sstore(SLOT_TOTAL_SUPPLY, _newSupply)

            let _tokenSlot := sload(SLOT_STAKE)
            _token := and(_tokenSlot, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)

            mstore(_mptr, 0x23b872dd)
            mstore(add(_mptr, 0x20), caller())
            mstore(add(_mptr, 0x40), address())
            mstore(add(_mptr, 0x60), amount)
            let _success := call(gas(), _token, 0, add(_mptr, 0x1c), 0x80, 0, 0)

            if iszero(_success) {
                let _ptr := mload(0x40)
                returndatacopy(_ptr, 0, returndatasize())
                revert(_ptr, returndatasize())
            }
            _returnSize := returndatasize()
            _returnValue := mload(0)
        }

        _require(
            _returnSize == 0 ? address(_token).code.length == 0 : _returnValue != 1, SafeERC20FailedOperationSelector
        );
        _log2(StakedSig, amount);
    }

    function withdraw(uint256 amount) public nonReentrant {
        _updateReward(msg.sender);
        _require(amount > 0, AmountWithdrawnIsZeroSelector);
        address _token;

        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, caller())
            mstore(add(_mptr, 0x20), SLOT_BALANCES)
            let _slotNum := keccak256(_mptr, 0x40)
            let _senderBal := sload(_slotNum)
            let _newBal := sub(_senderBal, amount)

            if iszero(iszero(gt(_newBal, _senderBal))) { revert(0, 0) }
            sstore(_slotNum, _newBal)

            let _supply := sload(SLOT_TOTAL_SUPPLY)
            let _newSupply := sub(_supply, amount)

            if iszero(iszero(gt(_newSupply, _supply))) { revert(0, 0) }
            sstore(SLOT_TOTAL_SUPPLY, _newSupply)
            let _data := sload(SLOT_STAKE)
            _token := and(_data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }

        _safeTransfer(_token, amount, WithdrawnSig);
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    function notifyRewardAmount(uint256 reward) external {
        _require(msg.sender == rewardsDistribution, NotRewardsDistributionSelector);
        _updateReward(address(0));
        uint256 _rewardsDuration;
        uint256 _rewardBal = rewardsToken.balanceOf(address(this));

        assembly {
            let _slotStake := sload(SLOT_STAKE)
            _rewardsDuration := shr(224, _slotStake)
            let _periodFinish := and(shr(160, _slotStake), 0xFFFFFFFF)
            let _rewardRate := sload(SLOT_REWARD_RATE)
            let _currentTime := timestamp()
            let _condition := or(gt(_currentTime, _periodFinish), eq(_currentTime, _periodFinish))

            switch _condition
            case 1 { _rewardRate := div(_rewardRate, _rewardsDuration) }
            default {
                let _leftover := mul(sub(_periodFinish, _currentTime), _rewardRate)
                _rewardRate := div(add(reward, _leftover), _rewardsDuration)
            }

            sstore(SLOT_REWARD_RATE, _rewardRate)

            let _rate := div(_rewardBal, _rewardsDuration)
            let _cond := or(gt(_rewardRate, _rate), eq(_rewardRate, _rate))

            if iszero(_cond) {
                let _mptr := mload(0x40)
                mstore(_mptr, RewardTooHighSelector)
                revert(_mptr, 0x04)
            }
        }

        lastUpdateTime = uint32(block.timestamp);
        periodFinish = uint32(block.timestamp + _rewardsDuration);
        _log1(RewardAddedSig, reward);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        _require(tokenAddress != address(stakingToken), TokenStakedIsInvalidSelector);
        _safeTransfer(tokenAddress, tokenAmount, RecoveredSig);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = uint32(_rewardsDuration);
        _log1(RewardsDurationUpdatedSig, _rewardsDuration);
    }

    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /*               INTERNAL FUNCTIONS                       */
    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    function _safeTransfer(address token, uint256 amount, uint256 selector) private {
        uint256 _returnSize;
        uint256 _returnValue;

        assembly {
            let _mptr := mload(0x40)

            mstore(_mptr, 0xa9059cbb)
            mstore(add(_mptr, 0x20), caller())
            mstore(add(_mptr, 0x40), amount)
            let _success := call(gas(), token, 0, add(_mptr, 0x1c), 0x60, 0x00, 0x00)

            if iszero(_success) {
                returndatacopy(_mptr, 0, returndatasize())
                revert(_mptr, returndatasize())
            }
            _returnSize := returndatasize()
            _returnValue := mload(0)
        }

        _require(
            _returnSize == 0 ? address(token).code.length == 0 : _returnValue != 1, SafeERC20FailedOperationSelector
        );
        _log2(selector, amount);
    }

    function _updateReward(address account) private {
        uint256 _rewardPerToken = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        assembly {
            let _mptr := mload(0x40)
            sstore(SLOT_REWARD_PER_TOKEN_STORED, _rewardPerToken)

            if iszero(iszero(account)) {
                mstore(_mptr, account)
                mstore(add(_mptr, 0x20), SLOT_BALANCES)
                let _slotBalances := keccak256(_mptr, 0x40)
                let _senderBalance := sload(_slotBalances)

                mstore(_mptr, account)
                mstore(add(_mptr, 0x20), SLOT_USER_REWARD_PER_TOKEN_PAID)
                let _slotUserReward := keccak256(_mptr, 0x40)
                let _userRewardPerTokenPaid := sload(_slotUserReward)

                mstore(_mptr, caller())
                mstore(add(_mptr, 0x20), SLOT_REWARDS)
                let _slotRewards := keccak256(_mptr, 0x40)
                let _userRewards := sload(_slotRewards)

                let _earned :=
                    add(div(mul(sub(_rewardPerToken, _userRewardPerTokenPaid), _senderBalance), 0xF4240), _userRewards)
                sstore(_slotRewards, _earned)
                sstore(_slotUserReward, _rewardPerToken)
            }
        }
    }

    function _log1(uint256 sig, uint256 value) internal {
        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, value)
            log1(_mptr, 0x20, sig)
        }
    }

    function _log2(uint256 sig, uint256 value) internal {
        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, value)
            log2(_mptr, 0x20, sig, caller())
        }
    }

    function _require(bool condition, uint256 selector) internal pure {
        assembly {
            if iszero(condition) {
                let _mptr := mload(0x40)
                mstore(_mptr, selector)
                revert(_mptr, 0x04)
            }
        }
    }
}
