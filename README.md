# SLend Smart Contract

SLend is a decentralized lending and deposit smart contract written in Clarity for the Stacks blockchain. It allows users to deposit STX, earn interest, set time-locks, refer others, and withdraw funds with daily limits and penalties for emergency withdrawals.

---

## Features

- **Deposit STX**: Users can deposit STX, optionally with a time-lock or a referral.
- **Interest Tiers**: Interest rates are based on deposit size, with configurable tiers.
- **Withdrawals**: Withdraw funds if not locked and within daily limits.
- **Emergency Withdrawals**: Withdraw before unlock with a penalty.
- **Time-Locks**: Lock deposits for a specified number of blocks (max 1 year).
- **Referrals**: Refer other users for deposits.
- **Admin Controls**: Owner can set interest tiers and daily withdrawal limits.
- **Read-Only Queries**: Check balances, interest, lock status, referrer, and withdrawal limits.

---

## Usage

### Deposit

- `deposit(amount)`  
  Deposit STX into the contract.

- `deposit-with-lock(amount, lock-blocks)`  
  Deposit STX with a time-lock (max 1 year).

- `deposit-with-referral(amount, referrer)`  
  Deposit STX and specify a referrer.

### Withdraw

- `withdraw(amount)`  
  Withdraw funds if not locked and within daily limit.

- `emergency-withdraw(amount)`  
  Withdraw funds before unlock with a 5% penalty.

### Admin Functions

- `set-interest-tier(threshold, rate)`  
  Set interest rate for a deposit threshold (owner only).

- `set-withdrawal-limit(new-limit)`  
  Set daily withdrawal limit (owner only).

### Read-Only Functions

- `get-balance(user)`  
  Get user's deposit balance.

- `get-deposit-info(user)`  
  Get user's deposit details.

- `get-unlock-height(user)`  
  Get user's unlock block height.

- `get-daily-withdrawal(user)`  
  Get user's daily withdrawal amount.

- `calculate-interest(amount)`  
  Calculate interest for a given amount.

- `get-interest-rate-for-amount(amount)`  
  Get interest rate for a given amount.

- `get-balance-with-interest(user)`  
  Get user's balance including accrued interest.

- `can-withdraw(user)`  
  Check if user can withdraw.

- `get-referrer(user)`  
  Get user's referrer.

- `get-daily-limit()`  
  Get current daily withdrawal limit.

---

## Interest Calculation

- Interest is calculated in basis points (1% = 100 basis points).
- Default tiers:
  - `< 1,000,000 microSTX`: 10%
  - `≥ 1,000,000 microSTX`: 15%
- Simple interest based on deposit amount and time elapsed.

---

## Security & Limits

- Daily withdrawal limit per user.
- Time-lock prevents withdrawal until unlock block.
- Emergency withdrawal incurs a 5% penalty.
- Only contract owner can change interest tiers and limits.

---

## Error Codes

- `ERR-INVALID-AMOUNT`: Invalid deposit/withdrawal amount.
- `ERR-LOCK-TOO-LONG`: Lock period exceeds maximum.
- `ERR-UNAUTHORIZED`: Unauthorized action.
- `ERR-INVALID-RATE`: Invalid interest rate.
- `ERR-INVALID-THRESHOLD`: Invalid interest tier threshold.
- `ERR-SELF-REFERRAL`: Cannot refer yourself.
- `ERR-INVALID-REFERRER`: Referrer must have a deposit.
- `ERR-INVALID-LIMIT`: Invalid withdrawal limit.
- `ERR-LIMIT-TOO-HIGH`: Withdrawal limit too high.
- `ERR-INSUFFICIENT-BALANCE`: Not enough balance.
- `ERR-FUNDS-LOCKED`: Funds are locked.
- `ERR-DAILY-LIMIT-EXCEEDED`: Daily withdrawal limit exceeded.

---

## License

This contract is provided for educational and demonstration purposes. 
