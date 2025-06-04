# ✈️ FlightSure - Travel Delay Insurance Smart Contract

## 🌟 Overview

FlightSure is a decentralized travel delay insurance platform built on the Stacks blockchain. Get automatically compensated when your flight is delayed based on real-time flight data from trusted oracles! 🚀

## 🎯 Features

- 📋 **Purchase Insurance Policies** - Buy coverage for your flights
- 🔍 **Oracle Integration** - Real-time flight delay verification
- 💰 **Automatic Claims** - Get paid when flights are delayed
- ⚙️ **Configurable Parameters** - Adjustable premiums and thresholds
- 📊 **Policy Management** - Track and manage your policies

## 🛠️ How It Works

1. **Purchase Policy** 🛒 - Buy insurance for your flight with STX
2. **Oracle Reports Delay** 📡 - Trusted oracle reports flight delays
3. **Claim Insurance** 💸 - Automatically claim compensation for delays
4. **Get Paid** 🎉 - Receive STX directly to your wallet

## 📋 Contract Functions

### Public Functions

#### `purchase-policy`
Purchase insurance for a specific flight
- **Parameters**: flight-number, departure-date, coverage-amount
- **Returns**: policy-id

#### `claim-insurance`
Claim compensation for a delayed flight
- **Parameters**: policy-id
- **Returns**: payout amount

#### `report-flight-delay`
Oracle function to report flight delays (oracle only)
- **Parameters**: flight-number, date, delay-minutes

#### `cancel-policy`
Cancel an active policy for 50% refund
- **Parameters**: policy-id
- **Returns**: refund amount

### Read-Only Functions

#### `get-policy`
Get policy details by ID

#### `get-flight-delay`
Check flight delay information

#### `is-policy-claimable`
Check if a policy can be claimed

#### `calculate-premium`
Calculate premium for coverage amount (5% of coverage)

## 🚀 Usage Examples

### Purchase Insurance Policy

```bash
clarinet console
```

```clarity
(contract-call? .FlightSure purchase-policy "AA1234" u1000 u10000000)
```

### Check Policy Status

```clarity
(contract-call? .FlightSure get-policy u1)
```

### Claim Insurance

```clarity
(contract-call? .FlightSure claim-insurance u1)
```

## ⚙️ Configuration

- **Minimum Premium**: 1 STX (1,000,000 microSTX)
- **Maximum Coverage**: 100 STX (100,000,000 microSTX)
- **Delay Threshold**: 120 minutes
- **Premium Rate**: 5% of coverage amount
- **Cancellation Refund**: 50% of premium

## 🔧 Admin Functions

Contract owners can:
- Set oracle address
- Adjust minimum/maximum coverage
- Modify delay threshold
- Withdraw contract funds

## 📊 Policy Lifecycle

1. **Active** ✅ - Policy purchased and valid
2. **Claimable** 🎯 - Flight delayed, ready to claim
3. **Claimed** 💰 - Insurance payout completed
4. **Cancelled** ❌ - Policy cancelled by user

## 🛡️ Security Features

- Owner-only admin functions
- Policy holder verification
- Oracle authorization
- Duplicate claim prevention
- Balance validation

## 🎮 Testing

Deploy and test with Clarinet:

```bash
clarinet check
```

```bash
clarinet test
```

## 📝 License

MIT License - Feel free to use and modify! 🎉

---

*Safe travels with FlightSure! Never worry about flight delays again.* ✈️💙

