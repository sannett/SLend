# SLend Smart Contract

A decentralized lending and deposit protocol on Stacks blockchain with multi-signature governance and oracle integration. Features dynamic interest rates, time-locks, referrals, and secure withdrawal controls.

## Core Features

### Multi-Signature Governance
- 3-10 contract owners (configurable)
- Proposal-based governance system
- Multiple confirmations required for actions
- Owner management functions

### Oracle Integration
- Dynamic STX/USD price feed
- Market-responsive interest rates
- Price staleness checks
- Automatic rate adjustments based on STX price

### Deposit System
- Standard STX deposits
- Time-locked deposits (up to 1 year)
- Referral-based deposits
- Interest based on deposit size and market conditions

### Withdrawal System
- Standard withdrawals (within daily limits)
- Emergency withdrawals (5% penalty)
- Daily withdrawal limits per user

## Usage

### Governance Functions
```clarity
add-owner(new-owner)
remove-owner(owner)
create-proposal(action, target, amount)
confirm-proposal(proposal-id)
set-required-confirmations(count)
```

### Oracle Functions
```clarity
set-oracle(oracle)
update-stx-price(new-price)
toggle-dynamic-rates()
```

### Deposit Functions
```clarity
deposit(amount)
deposit-with-lock(amount, lock-blocks)
deposit-with-referral(amount, referrer)
```

### Withdrawal Functions
```clarity
withdraw(amount)
emergency-withdraw(amount)
```

### Read-Only Functions
```clarity
get-balance(user)
get-balance-with-interest(user)
get-deposit-info(user)
get-unlock-height(user)
get-daily-withdrawal(user)
get-referrer(user)
get-daily-limit()

// New Governance Queries
get-owners()
get-required-confirmations()
get-proposal(proposal-id)

// New Oracle Queries
get-stx-price()
get-oracle-address()
is-dynamic-rates-enabled()
get-usd-value(stx-amount)
```

## Interest System

### Dynamic Rates
- Base rates:
  - 10% for deposits < 1M microSTX
  - 15% for deposits ≥ 1M microSTX
- Market adjustments:
  - STX price > $1.50: -2% (min 5%)
  - STX price ≤ $1.50: +2% (max 20%)
- Price staleness checks (10-day threshold)

## Security Features

### Governance Security
- Multi-signature requirements
- Proposal system with timeouts
- Configurable confirmation thresholds

### Oracle Security
- Price staleness checks
- Authorized oracle updates only
- Dynamic rate limits

### Transaction Security
- Daily withdrawal limits
- Time-lock enforcement
- Emergency withdrawal penalties
- Balance validations

## Error Codes

### Governance Errors
- `ERR-NOT-OWNER`: Unauthorized owner action
- `ERR-ALREADY-OWNER`: Owner already exists
- `ERR-INVALID-OWNER-COUNT`: Invalid number of owners
- `ERR-PROPOSAL-NOT-FOUND`: Proposal doesn't exist
- `ERR-PROPOSAL-EXPIRED`: Proposal timeout reached
- `ERR-ALREADY-VOTED`: Owner already voted

### Oracle Errors
- `ERR-ORACLE-ERROR`: Oracle operation failed
- `ERR-STALE-PRICE`: Price data too old

### Standard Errors
[Previous error codes remain unchanged...]

## License

This contract is provided for educational and demonstration purposes. Use at your own risk.

---
**Note**: The protocol uses block height for time calculations. 1 year ≈ 52,560 blocks based on 10-minute block times.
