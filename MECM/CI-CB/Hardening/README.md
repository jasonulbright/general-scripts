# Hardening

Baselines for credential and network hardening. Each folder is one control. Open its README for the details.

## Contents

| Folder | What it enforces | Builder |
|--------|------------------|---------|
| [`Anonymous-Enumeration-Restrict/`](Anonymous-Enumeration-Restrict/) | Restrictions on anonymous (null-session) enumeration (`RestrictAnonymous`, `RestrictAnonymousSAM`, `EveryoneIncludesAnonymous`). | `New-AnonymousEnumerationBaseline.ps1` |
| [`LLMNR-Disable/`](LLMNR-Disable/) | LLMNR off (`DNSClient\EnableMulticast = 0`). Blocks Responder-style name-resolution poisoning. | `New-LLMNRDisableBaseline.ps1` |
| [`LSA-Protection/`](LSA-Protection/) | LSA Protection on (`RunAsPPL = 1`), so LSASS runs as a Protected Process Light. A reboot is required. | `New-LSAProtectionBaseline.ps1` |
| [`NTLM-Hardening/`](NTLM-Hardening/) | NTLMv2 only (`LmCompatibilityLevel = 5`). Refuses LM and NTLMv1. | `New-NTLMHardeningBaseline.ps1` |
| [`SMB-Signing-Require/`](SMB-Signing-Require/) | SMB signing required on the client and the server (`RequireSecuritySignature = 1`). | `New-SMBSigningBaseline.ps1` |
| [`WDigest-Disable/`](WDigest-Disable/) | WDigest plaintext credential caching off (`UseLogonCredential = 0`). | `New-WDigestDisableBaseline.ps1` |
