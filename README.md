# Atomic Swap - Smart Contract Documentation

## Overview
Atomic Swap enables trustless peer-to-peer token exchanges using Hash Time-Locked Contracts (HTLC), ensuring both parties receive assets or both get refunded.

## Problem Solved
- **Counterparty Risk**: Trustless exchange without intermediaries
- **Settlement Risk**: Atomic execution or automatic refund
- **Cross-Chain Trading**: Hash-locked secret mechanism
- **Escrow Costs**: Direct P2P without third parties

## Key Features

### Core Functionality
- Hash Time-Locked Contracts (HTLC)
- Automatic timeout refunds
- Secret reveal mechanism
- Multi-step atomic execution
- Route statistics tracking

### Security Features
- Time-bounded execution
- Secret hash verification
- Automatic refunds on timeout
- Single-use secrets
- Emergency pause capability

## Contract Functions

### Swap Operations

#### `initiate-swap`
- **Parameters**: participant, initiator-amount, participant-amount, secret-hash, timelock
- **Returns**: swap-id
- **Effect**: Locks initiator funds

#### `participate`
- **Parameters**: swap-id
- **Effect**: Locks participant funds, activates swap

#### `claim-with-secret`
- **Parameters**: swap-id, secret
- **Effect**: Participant claims with secret reveal

#### `claim-initiator`
- **Parameters**: swap-id
- **Effect**: Initiator claims using revealed secret

#### `refund-timeout`
- **Parameters**: swap-id
- **Effect**: Refunds on timeout expiry

#### `cancel-swap`
- **Parameters**: swap-id
- **Effect**: Early cancellation if not participated

### Admin Functions
- `set-timelock-bounds`: Adjust min/max timelock
- `set-protocol-fee`: Update fee percentage
- `toggle-emergency-pause`: Emergency controls
- `withdraw-fees`: Collect protocol fees

### Read Functions
- `get-swap`: Swap details
- `get-user-swaps`: User's swap history
- `verify-secret-hash`: Verify secret/hash pair
- `is-swap-expired`: Check timeout status
- `get-route-stats`: Trading pair statistics

## Usage Flow

```clarity
;; 1. Initiator creates swap with secret hash
(contract-call? .atomic-swap initiate-swap
    'SP2J6Y09...     ;; participant
    u1000000         ;; 1 STX from initiator
    u2000000         ;; 2 STX from participant
    0x1234...        ;; secret hash
    u1440)           ;; 24-hour timelock

;; 2. Participant accepts and locks funds
(contract-call? .atomic-swap participate u1)

;; 3. Participant claims with secret
(contract-call? .atomic-swap claim-with-secret u1 0xABCD...)

;; 4. Initiator claims using revealed secret
(contract-call? .atomic-swap claim-initiator u1)

;; Alternative: Refund on timeout
(contract-call? .atomic-swap refund-timeout u1)
```

## HTLC Mechanism

### Secret Generation
1. Initiator generates random secret
2. Creates hash(secret)
3. Shares hash with participant

### Execution Path
- **Success**: Both parties claim within timelock
- **Timeout**: Automatic refund after expiry
- **Cancel**: Early cancellation if not participated

## Security Parameters
- **Min Timelock**: 144 blocks (~24 minutes)
- **Max Timelock**: 10080 blocks (~7 days)
- **Protocol Fee**: 0.1% on initiator amount
- **Secret Size**: 32 bytes

## Deployment
1. Deploy contract
2. Set timelock parameters
3. Configure protocol fee
4. Monitor swap activity
5. Collect fees periodically

## Testing Checklist
- Complete swap flow
- Secret verification
- Timeout refunds
- Cancellation logic
- Fee calculations
- Route statistics
- Emergency pause

## Cross-Chain Compatibility
- Same secret works across chains
- Coordinated timelocks
- Chain-specific implementations
- Unified secret format

## Use Cases
- **P2P Trading**: Direct token swaps
- **Cross-Chain**: Bridge different blockchains
- **OTC Deals**: Large trustless trades
- **Arbitrage**: Atomic cross-DEX trades
