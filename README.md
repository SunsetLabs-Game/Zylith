# Zylith Protocol

**Version**: 1.0 (MVP)
**Network**: Starknet
**Status**: Active Development

---

## Overview

Zylith is a privacy-preserving Concentrated Liquidity Market Maker (CLMM) built on Starknet. It combines the capital efficiency of concentrated liquidity with zero-knowledge privacy features, enabling users to trade and provide liquidity with complete privacy while maintaining the precision of traditional CLMMs.

### Key Features

| Feature | Description | Status |
|---------|-------------|--------|
| **Concentrated Liquidity** | Ekubo-compatible CLMM with efficient capital utilization | Complete |
| **Privacy Layer** | ZK-proof-based private swaps and positions | Complete |
| **Commitment-based Ownership** | Cryptographic ownership instead of addresses | Complete |
| **Merkle Tree** | Poseidon BN254 tree for membership proofs | Complete |
| **Private Swaps** | Zero-knowledge verified swap execution | Complete |
| **Private LP Operations** | Privacy-preserving liquidity management | Complete |

---

## Project Structure

```
Zylith/
├── README.md                    # This file - project overview
├── docs/                        # All documentation
│   ├── README.md               # Documentation index
│   ├── architecture/           # Architecture documentation
│   │   └── system-architecture.md
│   ├── api/                    # API documentation
│   │   └── api-reference.md
│   ├── reference/              # Reference documentation
│   │   ├── requirements.md
│   │   └── technology-stack.md
│   └── product/                # Product documentation
│       └── product-requirements.md
├── circuits-noir/              # Noir circuit implementation
└── zylith/                     # Main protocol implementation
    ├── src/                    # Cairo smart contracts
    │   ├── clmm/              # CLMM layer (math, ticks, swaps)
    │   ├── privacy/           # Privacy layer (Merkle tree, commitments)
    │   └── integration/       # Integration layer (private operations)
    ├── tests/                  # Comprehensive test suite
    ├── circuits/               # Circom ZK circuits
    ├── scripts/                # Setup and deployment scripts
    └── docs/                   # Implementation documentation
        ├── DEPLOYMENT.md
        └── USAGE.md
```

---

## Quick Start

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| **Scarb** | Latest | Cairo package manager |
| **Starknet Foundry** | 0.50.0+ | Testing framework |
| **Node.js** | 16+ | Circuit compilation |
| **Python** | 3.10+ | Garaga setup |

### Installation

```bash
# Clone the repository
git clone https://github.com/your-org/Zylith.git
cd Zylith/zylith

# Build contracts
scarb build

# Run tests
scarb test
```

### Running Tests

```bash
# Run all tests
scarb test

# Run specific test suite
snforge test test_clmm        # CLMM core tests
snforge test test_privacy     # Privacy layer tests
snforge test test_integration # Integration tests
```

---

## Implementation Status

### Core Components

| Component | Status | Test Coverage | Notes |
|-----------|--------|---------------|-------|
| **CLMM Engine** | Complete | 63% | Swap engine, tick management, liquidity |
| **Privacy Layer** | Complete | 100% | Merkle tree, commitments, nullifiers |
| **Integration Layer** | Complete | 75% | Private swaps, deposits, withdrawals |
| **ZK Circuits** | Framework Ready | N/A | Circom circuits implemented |
| **ASP Server** | Framework Ready | N/A | Rust implementation pending |

### Test Results

| Test Suite | Tests Passing | Total Tests | Status |
|------------|--------------|-------------|--------|
| **Privacy Tests** | 12/12 | 12 | Passing |
| **CLMM Tests** | 8/15 | 15 | In Progress |
| **Integration Tests** | 2/8 | 8 | In Progress |
| **Overall** | 22/35 | 35 | 63% |

---

## Documentation

### Core Documentation

| Document | Description | Target Audience |
|----------|-------------|-----------------|
| **[System Architecture](docs/architecture/system-architecture.md)** | System architecture and design | Developers, Architects |
| **[API Reference](docs/api/api-reference.md)** | Complete API documentation | Integrators, Developers |
| **[Product Requirements](docs/product/product-requirements.md)** | Product requirements document | Stakeholders, Product Team |
| **[Requirements](docs/reference/requirements.md)** | System requirements | Developers, Product Team |
| **[Technology Stack](docs/reference/technology-stack.md)** | Technology stack reference | Developers |
| **[Implementation Guide](zylith/README.md)** | Implementation guide | Developers |

### Quick Links

- **Documentation Index**: See [docs/README.md](docs/README.md)
- **Architecture**: See [docs/architecture/system-architecture.md](docs/architecture/system-architecture.md)
- **API Reference**: See [docs/api/api-reference.md](docs/api/api-reference.md)
- **Setup Guide**: See [docs/reference/technology-stack.md](docs/reference/technology-stack.md)
- **Testing**: See [zylith/README.md](zylith/README.md#testing)
- **Deployment**: See [zylith/docs/DEPLOYMENT.md](zylith/docs/DEPLOYMENT.md)

---

## Roadmap

### Phase 1: MVP (Complete)

- Core CLMM implementation
- Privacy layer with ZK proofs
- Basic integration layer
- Test framework and initial tests

### Phase 2: Production Readiness (In Progress)

| Task | Status | Target Date |
|------|--------|-------------|
| Garaga verifier integration | Pending | Q1 2026 |
| ASP server implementation | Pending | Q1 2026 |
| Security hardening | Pending | Q1 2026 |
| Documentation completion | In Progress | Q1 2026 |

### Phase 3: Testnet Deployment (Planned)

- Deploy to Starknet testnet
- Public testing period
- Bug bounty program
- Community feedback integration

### Phase 4: Mainnet Launch (Planned)

- Security audits (2x independent)
- Mainnet deployment
- Monitoring and support infrastructure
- Production ASP deployment

---

## Contributing

We welcome contributions from the community. Before contributing, please:

1. Review the [System Architecture](docs/architecture/system-architecture.md) to understand the system design
2. Check the [API Reference](docs/api/api-reference.md) for API specifications
3. Follow Cairo coding standards and style guides
4. Ensure all tests pass before submitting
5. Update documentation for any API changes

### Development Workflow

```bash
# Create feature branch
git checkout -b feature/your-feature

# Make changes and test
scarb build
scarb test

# Commit and push
git add .
git commit -m "feat: your feature description"
git push origin feature/your-feature

# Open pull request
```

---

## Community and Support

### Resources

| Resource | Link | Purpose |
|----------|------|---------|
| **Documentation** | [docs/README.md](docs/README.md) | Complete docs index |
| **GitHub Issues** | GitHub Issues | Bug reports, feature requests |
| **Architecture** | [docs/architecture/system-architecture.md](docs/architecture/system-architecture.md) | System design |
| **API Reference** | [docs/api/api-reference.md](docs/api/api-reference.md) | API documentation |

### Contact

- **Technical Questions**: Open a GitHub issue
- **Security Issues**: Contact security team (see [Product Requirements](docs/product/product-requirements.md))
- **General Inquiries**: See [Documentation Index](docs/README.md)

---

## License

[License information to be added]

---

**Version**: 1.0 (MVP)
**Last Updated**: December 2025
**Maintained By**: Zylith Protocol Team

