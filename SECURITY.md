# Security Policy

## Supported Versions

We provide security updates for the current major release branch:

| Version | Supported          |
| :---    | :---               |
| 2.x     | :white_check_mark: |
| < 2.0   | :x:                |

---

## Threat Model & Security Scope

AirDrop Wheel 2 interacts with Apple's peer-to-peer wireless protocol (AWDL) and HTTP-over-TLS microservices on local network endpoints.

### Key Security Guardrails in AirDrop Wheel 2:
1. **Target Mode**:
   AirDrop Wheel 2 communicates only with endpoints currently advertising in "Everyone for 10 minutes" mode. It does not attempt to brute-force or spoof Apple ID cryptographic identities.
2. **Recipient Consent**:
   All transfers strictly await recipient user interaction. No data bytes are streamed until the receiving device explicitly accepts the transfer prompt on screen.
3. **TLS Leaf Certificate Pinning**:
   During the initial handshake via `POST /Discover`, the peer's leaf certificate is pinned for the remainder of that transfer session. This prevents in-flight man-in-the-middle key replacement.
4. **Local Isolation & Privacy**:
   No user files, metadata, or telemetry are ever transmitted to external cloud servers. All network operations are strictly constrained to peer-to-peer links (`fe80::...%awdl0`).

---

## Reporting a Vulnerability

If you discover a security vulnerability or sensitive bug in AirDrop Wheel 2, please **do not open a public issue**.

Instead, please report it via one of the following methods:

- **Private Vulnerability Report**: Open a report via [GitHub Security Advisories](https://github.com/Manfredsun/airdrop-wheel/security/advisories/new).
- **Direct Email**: Send encrypted or plain details directly to:
  **manfredymcacc@gmail.com**

Please include:
- A description of the vulnerability and its potential impact.
- Step-by-step instructions or proof-of-concept to reproduce the issue.
- Your macOS version, device model, and target device details.

We will acknowledge receipt within 48 hours and work with you to test and release a prompt fix before public disclosure.
