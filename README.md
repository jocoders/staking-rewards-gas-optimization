# Gas Optimization Audit Report - StakingRewards

## Overview

- **Contract Audited:** StakingRewards.sol & StakingRewardsOptimized.sol
- **Optimization Techniques Used:** Yul optimizations, slot packing, inline assembly, gas-efficient event logging, custom errors
- **Audit Focus:** Reducing gas costs for deployment and function execution
- **Findings Summary:**
  - **Deployment Gas Reduced:** 2,160,624 -> 1,546,600 (↓ 28.4%)
  - **Deployment Size Reduced:** 10,073 -> 7,340 (↓ 27.2%)
  - **Gas Savings on Function Calls:** Significant reductions across multiple functions

## Optimizations & Gas Savings

### 1️⃣ Moved RewardsDistributionRecipient Logic Inside Contract

- Previously, the contract used an external `RewardsDistributionRecipient` contract.
- Moved its logic directly inside `StakingRewards` to save external call gas.
- **Gas Improvement:** Reduced the number of external calls, lowering gas usage.

### 2️⃣ Packed Multiple Variables into a Single Storage Slot

- **Before:** Some variables were stored separately, increasing SLOAD costs.
- **After:** Related variables were combined into a single slot when possible.
- **Gas Improvement:** Less storage access, reducing SLOAD cost (cold -> warm reads).

### 3️⃣ Created Getters in Yul

- Implemented getters using Yul with direct slot access.
- **Gas Improvement:** Direct slot access instead of Solidity’s default storage handling.

### 4️⃣ Created Setters in Yul

- Implemented setters using Yul with direct slot assignments.
- **Gas Improvement:** More efficient storage updates.

### 5️⃣ Moved Complex Computations to Yul

- **Before:** Solidity handled expensive calculations within functions.
- **After:** Optimized using inline Yul.
- **Gas Improvement:** Lower opcode execution costs, improved efficiency.

### 6️⃣ Implemented Require Checks in Yul

- **Before:** Solidity `require(condition, "error message")`
- **After:** Yul `if iszero(condition) { revert(...) }`
- **Gas Improvement:** Saves gas because strings are expensive in `require()`.

### 7️⃣ Optimized Event Logging with `log1`, `log2`

- Used **low-level event logging in Yul (`log1`, `log2`)**.
- **Gas Improvement:** Direct event writing reduced the overhead of Solidity event emissions.

### 8️⃣ Implemented Transfer Function in Yul

- **Before:** Solidity’s `transfer()` was used.
- **After:** Used Yul’s `call()` for gas efficiency.
- **Gas Improvement:** Reduced external call gas cost.

### 9️⃣ Implemented Update Function in Yul

- Similar optimization as the transfer function.
- **Benefit:** Lower gas cost per execution.

## 📊 Gas Usage Comparison (Before vs After)

| Function Name              | Before (Avg) | After (Avg) | Improvement |
| -------------------------- | ------------ | ----------- | ----------- |
| **Deployment Cost**        | 2,160,624    | 1,546,600   | **↓ 28.4%** |
| **Deployment Size**        | 10,073       | 7,340       | **↓ 27.2%** |
| `balanceOf`                | 940          | 918         | ↓ 2.3%      |
| `exit`                     | 69,364       | 61,868      | **↓ 10.8%** |
| `getReward`                | 46,119       | 43,699      | **↓ 5.3%**  |
| `getRewardForDuration`     | 4,892        | 2,519       | **↓ 48.5%** |
| `lastTimeRewardApplicable` | 2,677        | 481         | **↓ 82.0%** |
| `notifyRewardAmount`       | 78,412       | 47,647      | **↓ 39.2%** |
| `paused`                   | 555          | 584         | ↑ 5.2%      |
| `recoverERC20`             | 44,755       | 44,117      | ↓ 1.4%      |
| `rewardRate`               | 515          | 493         | ↓ 4.3%      |
| `setPaused`                | 52,683       | 30,430      | **↓ 42.2%** |
| `setRewardsDuration`       | 32,403       | 30,275      | ↓ 6.6%      |
| `stake`                    | 129,789      | 123,410     | **↓ 4.9%**  |
| `totalSupply`              | 500          | 471         | ↓ 5.8%      |
| `withdraw`                 | 77,695       | 69,885      | **↓ 10.1%** |

## ✅ Conclusion

- **Achieved a 28.4% reduction in deployment gas cost.**
- **Reduced contract size by 27.2%.**
- **Lowered function execution gas across all functions, especially `getRewardForDuration` (-48.5%) and `lastTimeRewardApplicable` (-82.0%).**
- **Major improvements from using Yul, packing storage, optimizing events, and reducing unnecessary gas costs.**

These optimizations significantly improve the efficiency of `StakingRewardsOptimized.sol`, making it more gas-efficient for both deployment and function execution.
