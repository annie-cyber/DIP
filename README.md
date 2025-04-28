# Decentralized Insurance Protocol (DIP)

A secure, smart contract-based insurance system on the Stacks blockchain that provides coverage against financial losses, enabling users to purchase insurance coverage, file claims, and receive compensation in a transparent, decentralized manner.

## Overview

The Decentralized Insurance Protocol (DIP) allows entities on the Stacks blockchain to:

- Purchase insurance coverage with customizable amounts and durations
- File claims with optional cryptographic evidence when incidents occur
- Receive insurance payouts through a transparent approval process
- Manage and extend existing coverage as needed

The protocol uses STX as the insurance premium and payout currency, with all transactions recorded on-chain for full transparency.

## Features

- **Customizable Coverage**: Users can specify coverage amounts and periods
- **Evidence-Based Claims**: Submit claims with cryptographic proof of incidents
- **Premium Calculation**: Dynamic premium calculation based on coverage amount, duration, and risk factors
- **Partial Refunds**: Cancel coverage anytime with proportional premium refunds
- **Coverage Extensions**: Extend coverage period or increase coverage amount as needed
- **Transparent Administration**: All claim approvals and rejections are recorded on-chain
- **Emergency Pause**: Contract operations can be paused in case of emergencies
- **Enhanced Security**: Comprehensive input validation and data checks throughout the contract

## Security Features

- **Principal Validation**: All principal addresses are validated against the zero address
- **Evidence Hash Validation**: Cryptographic evidence is validated for correct format
- **Claim Validation**: Multiple validation checks before approving or rejecting claims
- **Coverage Verification**: Ensures coverage is active before processing any claims
- **Error Handling**: Specific error codes for better debugging and user experience

## Contract Functions

### User Functions

- `purchase-coverage`: Purchase new insurance coverage
- `increase-coverage`: Increase the coverage amount on existing policy
- `extend-coverage-period`: Extend the duration of existing coverage
- `cancel-coverage`: Cancel coverage and receive partial refund
- `file-claim`: Submit an insurance claim with optional evidence

### Admin Functions

- `approve-claim`: Process and approve an insurance claim
- `reject-claim`: Reject an insurance claim with reason
- `check-and-expire-claim`: Mark expired claims
- `change-contract-owner`: Transfer contract ownership
- `set-contract-pause`: Pause/unpause contract operations
- `set-minimum-coverage`: Set minimum required coverage amount

### Read-Only Functions

- `calculate-premium`: Calculate premium for given coverage and duration
- `get-pool-balance`: Get current insurance pool balance
- `is-insured`: Check if an entity has active coverage
- `get-coverage-details`: Get details of entity's coverage
- `get-claim-status`: Check status of a specific claim
- `get-pending-claims`: Get all pending claims for an entity
- `get-contract-stats`: Get general contract statistics

## How It Works

1. Users purchase insurance by paying premiums in STX
2. If an incident occurs, users file claims with optional evidence
3. Contract administrators review and approve/reject claims
4. Approved claims receive payouts directly from the insurance pool
5. All transactions and decisions are recorded on the blockchain

## Use Cases

- Protection against smart contract vulnerabilities
- Insurance for digital assets
- Coverage for decentralized finance positions
- Business continuity protection for blockchain projects
