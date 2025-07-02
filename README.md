# Rent-to-Own Contract
A decentralized Rent-to-Own property management system built on Stacks blockchain.

## 🚀 Features

- Automated monthly payment processing
- Property ownership transfer upon completion
- Payment history tracking
- Contract status monitoring
- Late payment handling
- Security validations

## 🛠️ Technical Details

### Security Features
- Owner-only initialization
- Payment validation
- Status checks
- Access control
- Safe STX transfers

### Optimizations
- Efficient state management
- Minimal storage usage
- Optimized payment tracking

## 📋 Usage Instructions

1. Deploy contract using Clarinet:
```bash
clarinet contract deploy
```

2. Initialize contract with property details:
```bash
clarinet contract call initialize-contract
```

3. Make monthly payments:
```bash
clarinet contract call make-payment
```

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 💻 UI Components

### Dashboard Features
- Payment Schedule Timeline
- Property Details Card
- Payment History Table
- Contract Status Indicator
- Progress Bar for Total Payments
- Action Buttons (Make Payment, Check Status)
