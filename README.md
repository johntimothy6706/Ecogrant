# Ecogrant - Eco Grant Distribution DAO

A decentralized autonomous organization (DAO) smart contract for distributing grants to green startups and environmental projects on the Stacks blockchain.

## Overview

Ecogrant enables community-driven funding for environmental initiatives through a transparent voting mechanism. Members contribute STX tokens to join the DAO, create funding proposals, and vote on grant distributions to support eco-friendly startups.

## Features

- **Membership System**: Join DAO by staking STX tokens with minimum voting power requirements
- **Proposal Creation**: Submit grant proposals with detailed descriptions and funding amounts
- **Voting Mechanism**: Democratic voting system with quorum requirements
- **Grant Distribution**: Automatic fund distribution to approved proposals
- **Treasury Management**: Transparent treasury tracking and emergency controls
- **Governance Controls**: Adjustable voting duration, quorum thresholds, and minimum voting power

## Contract Functions

### Public Functions

#### Membership Management
- `join-dao(voting-power)` - Join DAO by staking STX tokens
- `leave-dao()` - Leave DAO and withdraw staked tokens

#### Proposal Management  
- `create-proposal(title, description, recipient, amount, category)` - Submit new grant proposal
- `vote-on-proposal(proposal-id, vote)` - Vote on active proposals (true = for, false = against)
- `execute-proposal(proposal-id)` - Execute approved proposals after voting ends

#### Governance (Owner Only)
- `update-voting-duration(new-duration)` - Modify voting period length
- `update-quorum-threshold(new-threshold)` - Adjust quorum percentage requirement
- `update-min-voting-power(new-min)` - Change minimum voting power to join
- `emergency-withdraw(amount)` - Emergency treasury withdrawal

### Read-Only Functions

- `get-proposal(proposal-id)` - Get proposal details
- `get-vote(proposal-id, voter)` - Get specific vote information
- `get-treasury-balance()` - Check current treasury balance
- `get-total-proposals()` - Get total number of proposals
- `get-member-info(member)` - Get member stake information
- `get-voting-power-info(member)` - Get member voting power
- `get-dao-settings()` - Get current DAO configuration
- `is-proposal-active(proposal-id)` - Check if proposal voting is active
- `get-proposal-status(proposal-id)` - Get current proposal status

## Usage Instructions

### 1. Join the DAO

```clarity
;; Join with 1 STX (1,000,000 micro-STX) minimum
(contract-call? .Ecogrant join-dao u1000000)
```

### 2. Create a Proposal

```clarity
(contract-call? .Ecogrant create-proposal 
    "Solar Panel Initiative"
    "Funding for community solar panels in rural areas"
    'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7
    u500000  ;; 0.5 STX
    "renewable-energy"
)
```

### 3. Vote on Proposals

```clarity
;; Vote in favor (true) or against (false)
(contract-call? .Ecogrant vote-on-proposal u1 true)
```

### 4. Execute Approved Proposals

```clarity
;; Execute after voting period ends
(contract-call? .Ecogrant execute-proposal u1)
```

### 5. Check Proposal Status

```clarity
;; Get proposal details
(contract-call? .Ecogrant get-proposal u1)

;; Check current status
(contract-call? .Ecogrant get-proposal-status u1)
```

## Default Settings

- **Minimum Voting Power**: 1 STX (1,000,000 micro-STX)
- **Voting Duration**: 144 blocks (~24 hours)
- **Quorum Threshold**: 51% of total voting power
- **Categories**: Open-ended string field for proposal categorization

## Proposal Lifecycle

1. **Creation**: DAO member submits proposal with funding request
2. **Voting**: Active voting period (144 blocks by default)
3. **Execution**: Automatic fund distribution if proposal passes quorum and majority vote
4. **Completion**: Proposal marked as executed with pass/fail status

## Error Codes

- `u100` - Unauthorized access
- `u101` - Invalid proposal parameters
- `u102` - Proposal not found
- `u103` - Voting period has ended
- `u104` - Voting period not yet ended
- `u105` - Already voted on proposal
- `u106` - Insufficient treasury funds
- `u107` - Proposal already executed
- `u108` - Invalid amount specified
- `u109` - Invalid duration specified
- `u110` - Not a DAO member

## Security Features

- Member-only proposal creation and voting
- Duplicate vote prevention
- Treasury balance validation
- Owner-controlled governance parameters
- Emergency withdrawal mechanism

## Development

This contract is built for the Stacks blockchain using Clarity smart contract language. Deploy using Clarinet development environment.

### Requirements
- Clarinet CLI
- Stacks wallet for testing
- STX tokens for DAO participation

### Testing
Run tests using Clarinet:
```bash
clarinet test
```

## License

MIT License - See LICENSE file for details
