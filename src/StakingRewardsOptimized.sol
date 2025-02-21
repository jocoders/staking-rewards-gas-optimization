// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Owned} from "./Owned.sol";

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

    /**
     *  @notice Creates a new StakingRewardsOptimized contract
     *  @param _owner The address of the owner
     *  @param _rewardsDistribution The address responsible for distributing rewards
     *  @param _rewardsToken The token used for rewards
     *  @param _stakingToken The token that will be staked
     *
     */
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

    /**
     *  @notice Returns the balance of the given account
     *  @param account The address of the account to check
     *  @return The balance of the account
     *
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Retrieves the total rewards for the current duration.
     * @return _duration The total reward amount for the duration.
     */
    function getRewardForDuration() external view returns (uint256 _duration) {
        assembly {
            let _rewardRate := sload(rewardRate.slot)
            _duration := mul(_rewardRate, shr(224, stakingToken.slot))
        }
    }

    /**
     * @notice Gets the last applicable time for reward calculations.
     * @return _lastTime The last applicable reward time.
     */
    function lastTimeRewardApplicable() public view returns (uint32 _lastTime) {
        assembly {
            _lastTime := and(timestamp(), 0xFFFFFFFF)
            let _periodFinish := and(shr(160, stakingToken.slot), 0xFFFFFFFF)

            if iszero(lt(_lastTime, _periodFinish)) { _lastTime := _periodFinish }
        }
    }

    /**
     * @notice Calculates the reward per staked token.
     * @return The reward per token.
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored + (((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalSupply);
    }

    /**
     * @notice Claims the reward for the sender.
     */
    function getReward() public nonReentrant {
        _updateReward(msg.sender);
        uint256 _amount;
        address _token;

        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, caller())
            mstore(add(_mptr, 0x20), rewards.slot)

            let _slotNum := keccak256(_mptr, 0x40)
            _amount := sload(_slotNum)

            if iszero(_amount) { return(0, 0) }
            sstore(_slotNum, 0)
            _token := sload(rewardsToken.slot)
        }

        _safeTransfer(_token, _amount, RewardPaidSig);
    }

    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /*               MUTATIVE FUNCTIONS                       */
    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/

    /**
     * @notice Allows the owner to pause or unpause the contract.
     * @param _paused The new pause state.
     */
    function setPaused(bool _paused) external onlyOwner {
        bool _pausedSaved;

        assembly {
            _pausedSaved := and(shr(192, rewardsDistribution.slot), 0xFF)

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

    /**
     * @notice Allows the owner to recover mistakenly sent ERC20 tokens.
     * @param tokenAddress The address of the ERC20 token.
     * @param tokenAmount The amount of tokens to recover.
     */
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

    /**
     * @notice Sets the rewards duration.
     * @param reward The new duration in seconds.
     */
    function notifyRewardAmount(uint256 reward) external {
        _require(msg.sender == rewardsDistribution, NotRewardsDistributionSelector);
        _updateReward(address(0));
        uint256 _rewardsDuration;
        uint256 _rewardBal = rewardsToken.balanceOf(address(this));

        assembly {
            let _slotStake := sload(stakingToken.slot)
            _rewardsDuration := shr(224, _slotStake)
            let _periodFinish := and(shr(160, _slotStake), 0xFFFFFFFF)
            let _rewardRate := sload(rewardRate.slot)
            let _currentTime := timestamp()
            let _condition := or(gt(_currentTime, _periodFinish), eq(_currentTime, _periodFinish))

            switch _condition
            case 1 { _rewardRate := div(_rewardRate, _rewardsDuration) }
            default {
                let _leftover := mul(sub(_periodFinish, _currentTime), _rewardRate)
                _rewardRate := div(add(reward, _leftover), _rewardsDuration)
            }

            sstore(rewardRate.slot, _rewardRate)

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

    /**
     * @notice Allows a user to exit by withdrawing their stake and claiming rewards.
     */
    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /**
     * @notice Allows a user to stake tokens.
     * @param amount The amount to stake.
     */
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
            mstore(add(_mptr, 0x20), _balances.slot)
            let _slotBalances := keccak256(_mptr, 0x40)
            let _senderBal := sload(_slotBalances)
            let _newBal := add(_senderBal, amount)

            if iszero(iszero(lt(_newBal, _senderBal))) { revert(0, 0) }
            sstore(_slotBalances, _newBal)

            let _supply := sload(totalSupply.slot)
            let _newSupply := add(_supply, amount)

            if iszero(iszero(lt(_newSupply, _supply))) { revert(0, 0) }
            sstore(totalSupply.slot, _newSupply)

            let _tokenSlot := sload(stakingToken.slot)
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

    /**
     * @notice Allows a user to withdraw staked tokens.
     * @param amount The amount to withdraw.
     */
    function withdraw(uint256 amount) public nonReentrant {
        _updateReward(msg.sender);
        _require(amount > 0, AmountWithdrawnIsZeroSelector);
        address _token;

        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, caller())
            mstore(add(_mptr, 0x20), _balances.slot)
            let _slotNum := keccak256(_mptr, 0x40)
            let _senderBal := sload(_slotNum)
            let _newBal := sub(_senderBal, amount)

            if iszero(iszero(gt(_newBal, _senderBal))) { revert(0, 0) }
            sstore(_slotNum, _newBal)

            let _supply := sload(totalSupply.slot)
            let _newSupply := sub(_supply, amount)

            if iszero(iszero(gt(_newSupply, _supply))) { revert(0, 0) }
            sstore(totalSupply.slot, _newSupply)
            let _data := sload(stakingToken.slot)
            _token := and(_data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }

        _safeTransfer(_token, amount, WithdrawnSig);
    }

    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /*               INTERNAL FUNCTIONS                       */
    /*✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦.•:*¨¨*:•.✦✧✶✧✦*/
    /**
     * @notice Safely transfers tokens to a recipient.
     * @param token The address of the token to transfer.
     * @param amount The amount to transfer.
     * @param selector The event selector for logging.
     */
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

    /**
     * @notice Updates the reward for a given account.
     * @param account The address of the account to update.
     */
    function _updateReward(address account) private {
        uint256 _rewardPerToken = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        assembly {
            let _mptr := mload(0x40)
            sstore(rewardPerTokenStored.slot, _rewardPerToken)

            if iszero(iszero(account)) {
                mstore(_mptr, account)
                mstore(add(_mptr, 0x20), _balances.slot)
                let _slotBalances := keccak256(_mptr, 0x40)
                let _senderBalance := sload(_slotBalances)

                mstore(_mptr, account)
                mstore(add(_mptr, 0x20), userRewardPerTokenPaid.slot)
                let _slotUserReward := keccak256(_mptr, 0x40)
                let _userRewardPerTokenPaid := sload(_slotUserReward)

                mstore(_mptr, caller())
                mstore(add(_mptr, 0x20), rewards.slot)
                let _slotRewards := keccak256(_mptr, 0x40)
                let _userRewards := sload(_slotRewards)

                let _earned :=
                    add(div(mul(sub(_rewardPerToken, _userRewardPerTokenPaid), _senderBalance), 0xF4240), _userRewards)
                sstore(_slotRewards, _earned)
                sstore(_slotUserReward, _rewardPerToken)
            }
        }
    }

    /**
     * @notice Logs a single event with one parameter.
     * @param sig The event signature.
     * @param value The parameter value.
     */
    function _log1(uint256 sig, uint256 value) internal {
        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, value)
            log1(_mptr, 0x20, sig)
        }
    }

    /**
     * @notice Logs a single event with two parameters.
     * @param sig The event signature.
     * @param value The parameter value.
     */
    function _log2(uint256 sig, uint256 value) internal {
        assembly {
            let _mptr := mload(0x40)
            mstore(_mptr, value)
            log2(_mptr, 0x20, sig, caller())
        }
    }

    /**
     * @notice Ensures that a condition is met, otherwise reverts.
     * @param condition The condition to check.
     * @param selector The error selector in case of failure.
     */
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
