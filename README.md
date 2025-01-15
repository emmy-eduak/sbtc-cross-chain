# sBTC Cross-Chain Bridge Smart Contract

A secure and decentralized cross-chain bridge implementation for sBTC (Stacks Bitcoin) that enables trustless token transfers between blockchains. This smart contract follows the SIP-010 fungible token standard and implements robust security measures including multi-signature authorization.

## Features

- **Multi-signature Security**: Requires multiple authorized signers to validate cross-chain transfers
- **SIP-010 Compliance**: Fully implements the Stacks SIP-010 fungible token standard
- **Configurable Parameters**: Adjustable fees, minimum amounts, and security thresholds
- **Pausable Operations**: Emergency pause functionality for enhanced security
- **Timeout Mechanism**: Automatic expiration of pending transfers for safety
- **Fee Management**: Configurable bridge fees with basis points precision

## Architecture

### Core Components

1. **Authorization System**

   - Multi-signature requirement for transfers
   - Configurable authorized signers
   - Owner-controlled administrative functions

2. **Bridge Operations**

   - Initiate cross-chain transfers
   - Sign pending transfers
   - Complete validated transfers
   - Cancel expired transfers

3. **Token Management**
   - Support for SIP-010 compliant tokens
   - Dynamic token addition/removal
   - Balance tracking

### Security Features

- Minimum 3 signatures required for transfer completion
- 24-hour timeout period for pending transfers
- Pausable contract operations
- Maximum bridge amount limits
- Comprehensive error handling

## Contract Functions

### Administrative Functions

```clarity
(set-contract-owner (new-owner principal))
(set-bridge-fee (new-fee uint))
(set-minimum-amount (amount uint))
(toggle-pause)
(add-authorized-signer (signer principal))
(remove-authorized-signer (signer principal))
(add-supported-token (token-contract <sip-010-trait>))
(remove-supported-token (token principal))
```

### Core Bridge Functions

```clarity
(initiate-bridge-transfer
    (token-contract <sip-010-trait>)
    (amount uint)
    (destination-chain (string-ascii 32))
    (destination-address (buff 42)))

(sign-bridge-transfer (swap-id uint))
(complete-bridge-transfer (swap-id uint) (token-contract <sip-010-trait>))
(cancel-expired-transfer (swap-id uint) (token-contract <sip-010-trait>))
```

### Read-Only Functions

```clarity
(get-pending-swap (swap-id uint))
(is-signer (account principal))
(get-bridge-fee)
(get-minimum-amount)
(is-token-supported (token principal))
(is-paused)
```

## Error Codes

| Code | Description            |
| ---- | ---------------------- |
| 1000 | Not authorized         |
| 1001 | Invalid amount         |
| 1002 | Insufficient balance   |
| 1003 | Bridge paused          |
| 1004 | Invalid token          |
| 1005 | Invalid destination    |
| 1006 | Swap not found         |
| 1007 | Swap already completed |
| 1008 | Swap expired           |
| 1009 | Invalid signature      |
| 1010 | Already authorized     |

## Bridge Transfer Flow

1. **Initiation**

   - User calls `initiate-bridge-transfer`
   - Contract validates parameters
   - Creates pending swap entry
   - Locks tokens in contract

2. **Validation**

   - Authorized signers verify the transfer
   - Call `sign-bridge-transfer`
   - Minimum 3 signatures required

3. **Completion**

   - After sufficient signatures
   - Call `complete-bridge-transfer`
   - Tokens released to destination

4. **Expiration**
   - Transfers expire after 24 hours
   - Can be cancelled via `cancel-expired-transfer`
   - Tokens returned to initiator

## Configuration

### Constants

- `BASIS-POINTS`: 10000 (for fee calculations)
- `MAX-BRIDGE-AMOUNT`: 100000000 satoshis
- Default bridge fee: 1% (100 basis points)
- Minimum transfer amount: 1000000 satoshis
- Transfer timeout: 144 blocks (approximately 24 hours)

## Security Considerations

1. **Multi-signature Requirements**

   - Minimum 3 signatures for transfer completion
   - Distributed trust model
   - Signer management controls

2. **Amount Limitations**

   - Maximum bridge amount enforced
   - Minimum amount requirements
   - Configurable thresholds

3. **Timeouts**

   - 24-hour expiration on pending transfers
   - Automatic cancellation mechanism
   - Protection against stuck transfers

4. **Access Controls**
   - Owner-controlled administration
   - Authorized signer management
   - Pausable operations

## Best Practices

1. **For Users**

   - Verify destination addresses carefully
   - Ensure transfer amount meets minimums
   - Monitor transfer status
   - Cancel expired transfers if needed

2. **For Administrators**

   - Regularly review authorized signers
   - Monitor bridge usage patterns
   - Adjust fees based on network conditions
   - Maintain active signer quorum

3. **For Signers**
   - Verify transfer details thoroughly
   - Maintain secure key management
   - Coordinate with other signers
   - Monitor for suspicious activities

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our repository.
