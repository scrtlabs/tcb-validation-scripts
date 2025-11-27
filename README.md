# TCB Verification Scripts - How-To Guide

This guide explains how to use the verification scripts to check if your system meets TCB (Trusted Computing Base) requirements for Intel TDX.

## Overview

These scripts help you determine if your system is ready for TCB-R 18 or TCB-R 20 compliance. They check critical components including microcode, BIOS, TDX module, SEAMLDR, and SGX DCAP.

## Prerequisites

Before running the verification scripts, ensure you have sudo/root access to the system.

---

## Clone the repo

```bash
git clone git@github.com:scrtlabs/tcb-validation-scripts.git
cd tcb-validation-scripts
```

## Script Execution Order

### Step 1: Install Required Tools

**Script:** `preflight.sh`
**Privileges:** Requires `sudo`
**Purpose:** Installs necessary diagnostic tools and performs basic system checks

```bash
sudo ./preflight.sh
```

**What it does:**
- Installs: cpuid, msr-tools, dmidecode, pciutils, wget, curl, jq, pv
- Verifies sudo access
- Checks internet connectivity
- Verifies available disk space (needs at least 2GB)

**When to run:** Always run this first on a new system or if tools are missing.

---

### Step 2: Quick TCB Level Check

**Script:** `verification.sh`
**Privileges:** No sudo required
**Purpose:** Quickly determines your current TCB level and provides upgrade recommendations

```bash
./verification.sh
```

**What it does:**
- Reads current microcode version from `/proc/cpuinfo`
- Compares against TCB-R 18, 19, and 20 thresholds
- Provides clear status and recommendations:
  - Very outdated: `< 0x21000201`
  - Pre-UPLR2: `< 0x21000290`
  - TCB-R 18: `< 0x210002B3`
  - TCB-R 20: `>= 0x210002B3`

**When to run:** After preflight to get a quick assessment of your system's TCB level.

---

### Step 3A: Comprehensive TCB-R 18 Verification

**Script:** `verify-system.sh`
**Privileges:** Requires `sudo`
**Purpose:** Comprehensive check for TCB-R 18 compliance

```bash
sudo ./verify-system.sh
```

**What it does:**
- Checks CPU family, model, and stepping (Emerald Rapids: 0xC06F2)
- Verifies microcode version (TCB-R 18 minimum: >= 0x21000201)
- Checks BIOS vendor, version, and release date
- Verifies TDX module version (>= 1.5.06 required)
- Checks SEAMLDR version (>= 2.0.00 for 5th Gen)
- Validates SGX device presence (`/dev/sgx_enclave`)
- Checks AESMD service status
- Verifies SGX DCAP version (>= 1.14 required)

**Output:** Clear status indicators (✅ COMPLIANT, ⚠️ PARTIAL, ❌ NEEDS UPDATE)

---

### Step 3B: TDX Diagnostic Report (Alternative/Fallback)

**Script:** `diagnose-tdx.sh`
**Privileges:** Requires `sudo`
**Purpose:** Detailed diagnostic report for troubleshooting TDX issues

```bash
sudo ./diagnose-tdx.sh
```

**What it does:**
- System identity (hostname, serial, manufacturer, model)
- CPU information with detailed CPUID breakdown
- Microcode version with TCB-R 20 comparison
- BIOS details
- Kernel configuration checks (CONFIG_INTEL_TDX_HOST)
- Kernel parameters (kvm_intel.tdx, intel_iommu)
- TDX BIOS enablement status
- TDX module initialization status
- TDX error messages from dmesg and journalctl
- KVM TDX module status
- IOMMU status
- TME (Total Memory Encryption) detection
- CPU feature support (TDX, SGX, TME)
- SEAMLDR messages
- Summary of critical issues preventing TDX

**When to run:** Use this script when `verify-system.sh` shows failures or doesn't provide the expected results. This script provides much more detailed diagnostic information to help identify the root cause of TDX issues.

**Note:** This script is particularly useful for:
- Debugging why TDX is not working
- Comparing configurations between working and non-working servers
- Identifying missing kernel configurations or boot parameters
- Finding specific error messages in system logs

---

### Step 4: TCB-R 20 Compliance Check

**Script:** `verify-tcb-v20.sh`
**Privileges:** Requires `sudo`
**Purpose:** Final verification for TCB-R 20 compliance

```bash
sudo ./verify-tcb-v20.sh
```

**What it does:**
- Checks microcode >= 0x210002B3 (TCB-R 20 requirement)
- Verifies BIOS version (IPU 2025.3, August 2025+)
- Validates TDX Module 1.5.16+ (build ~900, Feb 2025+)
- Confirms SEAMLDR 2.0+ compatibility
- Checks SGX DCAP >= 1.14
- Verifies AESMD service is running
- Checks QE3 (Quoting Enclave) load status
- Provides overall component summary

**When to run:** After confirming TCB-R 18 compliance or when targeting TCB-R 20 specifically.

---

## Recommended Workflow

### For Initial System Assessment:

```bash
# 1. Install tools (first time only)
sudo ./preflight.sh

# 2. Quick check
./verification.sh

# 3. Comprehensive verification
sudo ./verify-system.sh

# 4. If targeting TCB-R 20
sudo ./verify-tcb-v20.sh
```

### For Troubleshooting TDX Issues:

```bash
# If verify-system.sh shows unexpected results
sudo ./diagnose-tdx.sh > tdx-diagnostic-report.txt

# Save the output and compare with a working server
# or share with support for analysis
```

---

## Understanding the Output

### Status Indicators

- ✅ **COMPLIANT** - Component meets requirements
- ⚠️ **WARNING/PARTIAL** - Component works but recommend upgrade
- ❌ **NEEDS UPDATE** - Component must be updated for compliance

### Common Issues

1. **Microcode too old**: Update system firmware/BIOS
2. **TDX not enabled in BIOS**: Enable Intel TDX in BIOS settings
3. **Missing kernel parameters**: Add `kvm_intel.tdx=1` and `intel_iommu=on` to kernel boot parameters
4. **AESMD not running**: Install and start SGX AESMD service
5. **SGX DCAP too old**: Update SGX DCAP packages

---

## TCB Version Requirements Summary

### TCB-R 18 Requirements
- **Microcode**: >= 0x21000201 (minimum), >= 0x21000290 (recommended UPLR2)
- **TDX Module**: >= 1.5.06
- **SEAMLDR**: >= 2.0.00 (5th Gen)
- **SGX DCAP**: >= 1.14

### TCB-R 20 Requirements
- **Microcode**: >= 0x210002B3
- **BIOS**: IPU 2025.3 (August 2025+)
- **TDX Module**: >= 1.5.16 (build ~900, Feb 2025+)
- **SEAMLDR**: 2.0+
- **SGX DCAP**: >= 1.14

---

## Tips

- Always run `preflight.sh` first on new systems
- Use `verification.sh` for quick status checks without sudo
- Run `verify-system.sh` for detailed TCB-R 18 checks
- Use `diagnose-tdx.sh` when you need to troubleshoot or when `verify-system.sh` doesn't give expected results
- Run `verify-tcb-v20.sh` to confirm TCB-R 20 compliance
- Save diagnostic output for comparison or support: `sudo ./diagnose-tdx.sh > diagnostic-$(date +%Y%m%d).txt`

---

## Additional Notes

- Most verification scripts require sudo to read hardware information via dmidecode and dmesg
- The `verification.sh` script is the only one that doesn't require sudo (quick microcode check)
- All scripts are safe to run multiple times
- Scripts do not modify system configuration - they only read and report
