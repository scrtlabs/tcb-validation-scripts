# HOWTO — Running and Reading the TCB Reports

This guide walks through running each script in
[tcb-validation-scripts](README.md) on an Intel Xeon host and explains how to
interpret the output. The compliance bar is driven by
[tcb-policy.json](tcb-policy.json), which encodes the current Intel TDX TCB
Recovery requirements per CPU family.

If you just want a one-screen overview, read [README.md](README.md) first.

## Contents

1. [Prerequisites](#1-prerequisites)
2. [Workflow](#2-workflow)
3. [`preflight.sh` — install tooling](#3-preflightsh--install-tooling)
4. [`verification.sh` — quick microcode check](#4-verificationsh--quick-microcode-check)
5. [`verify-tcb.sh` — full compliance report](#5-verify-tcbsh--full-compliance-report)
6. [`diagnose-tdx.sh` — plumbing diagnostic](#6-diagnose-tdxsh--plumbing-diagnostic)
7. [Reading remediation steps](#7-reading-remediation-steps)
8. [Troubleshooting](#8-troubleshooting)
9. [Appendix — exit codes & files](#9-appendix--exit-codes--files)

---

## 1. Prerequisites

- A Linux host running on a supported Intel Xeon (see the table in
  [README.md](README.md)).
- `sudo` access (required for BIOS, dmesg, dmidecode, and journalctl reads).
- Network access (only for `preflight.sh` package install and to follow the
  remediation URLs the report prints).

Clone the repo and make the scripts executable:

```bash
git clone git@github.com:scrtlabs/tcb-validation-scripts.git
cd tcb-validation-scripts
chmod +x *.sh
```

## 2. Workflow

```
  preflight.sh        → installs jq, cpuid, dmidecode, msr-tools, ...
       │
       ▼
  verification.sh     → quick microcode-only check (no sudo)
       │
       ▼
  verify-tcb.sh       → full TCB compliance report (microcode + TDX module +
       │                 SEAMLDR + BIOS/IPU + DCAP + AESMD + kernel plumbing)
       ▼
  diagnose-tdx.sh     → only when TDX won't initialize: dumps verbose
                        plumbing/dmesg/IOMMU report for triage.
```

Run them in that order on a fresh host. On subsequent runs you can skip
`preflight.sh`.

## 3. `preflight.sh` — install tooling

```bash
sudo ./preflight.sh
```

Installs: `cpuid`, `msr-tools`, `dmidecode`, `pciutils`, `wget`, `curl`,
`jq`, `pv`. Verifies sudo, internet connectivity, and free space on `/boot`.

You only need to run this once per host. Re-run it if you move to a fresh
machine, or if `verify-tcb.sh` complains that `jq` is missing.

## 4. `verification.sh` — quick microcode check

```bash
./verification.sh
```

No sudo required. The script reads CPU signature and microcode from
`/proc/cpuinfo` and looks up the minimum microcode in `tcb-policy.json`.

### How to read it

```
CPU:          INTEL(R) XEON(R) GOLD 5515+
Signature:    06-cf-02
Microcode:    0x210002c0

Detected:     Emerald Rapids (EMR-SP)
Required MCU: >= 0x210002d3  (microcode-20260210)

Status: ❌ Microcode is OUT OF DATE for current Intel TDX TCB policy.

Recommendation:
  Upgrade microcode to 0x210002d3 or newer.
  Apply OEM BIOS update containing this revision, or load late from:
    https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files/releases/tag/microcode-20260210
  Release tag: microcode-20260210
```

| Field             | Meaning                                                            |
|-------------------|--------------------------------------------------------------------|
| `Signature`       | `family-model-stepping` in Intel's microcode-file format.          |
| `Microcode`       | Currently-loaded revision from `/proc/cpuinfo`.                    |
| `Detected`        | The `tcb-policy.json` entry that matched the signature.            |
| `Required MCU`    | Minimum revision per current TCB policy + Intel release tag.       |
| `Status`          | ✅ if `Microcode >= Required MCU`, ❌ otherwise.                    |

**Exit codes:** `0` compliant, `1` not compliant or unsupported CPU,
`2` `jq` missing.

This is intentionally a fast/coarse check. Even if it says ✅, you still need
`verify-tcb.sh` for the full picture (TDX module build, SEAMLDR, DCAP, kernel
plumbing).

## 5. `verify-tcb.sh` — full compliance report

```bash
sudo ./verify-tcb.sh
```

Sudo is required because the script reads `dmesg`, `journalctl`, and
`dmidecode` to identify the loaded TDX module, SEAMLDR version, and BIOS
metadata.

The output is divided into eight numbered sections, followed by a summary
that lists numbered remediation steps for every non-compliant component.

### Section 1 — CPU

```
1. CPU
   Model:     INTEL(R) XEON(R) GOLD 5515+
   Signature: 06-cf-02 (family-model-stepping)
   Codename:  Emerald Rapids
   Family:    5th Gen Intel Xeon Scalable
   Matched:   Emerald Rapids (EMR-SP)
```

If `Matched` is missing and you see `No TCB policy entry for this CPU`, your
host is not in the bundled policy. Either it's an unsupported Xeon, or
`tcb-policy.json` needs a new entry — see
[README.md → Updating the policy](README.md#updating-the-policy).

### Section 2 — Microcode

```
2. Microcode
   Current:  0x210002c0
   Required: 0x210002d3 (microcode-20260210)
   ❌ OUT OF DATE
```

| Status            | What it means                                                   |
|-------------------|-----------------------------------------------------------------|
| ✅ COMPLIANT      | `/proc/cpuinfo` microcode ≥ policy minimum.                     |
| ❌ OUT OF DATE    | Apply an OEM BIOS update containing the required revision, or load it late via `intel-microcode` / `iucode-tool`. URL is in the summary. |

### Section 3 — TDX Module

```
3. TDX Module
   Required: 1.5.24 (series 1.5.x, build 943) or newer
   Source:   https://github.com/.../TDX_MODULE_1.5.24
   Current:  major=1 minor=5 build=943 build_date=20250729
   ✅ COMPLIANT
```

The script extracts `major_version`, `minor_version`, `build_num`, and
`build_date` from `dmesg` lines like `virt/tdx: ... build_num 943 ...`.

| Status                                 | What it means |
|----------------------------------------|----------------|
| ✅ COMPLIANT                           | Series matches and `build ≥ min_build`. |
| ❌ Wrong module series                 | Loaded module is 2.0.x but policy demands 1.5.x (or vice-versa). Install the right module image at `/lib/firmware/intel-seam/`. |
| ❌ Build older than required           | Upgrade the TDX module image; URL is in the summary. |
| ❌ TDX module not detected             | TDX never loaded. Check BIOS enablement, kernel cmdline (`kvm_intel.tdx=1`), and that the module image is present. |

### Section 4 — SEAMLDR

```
4. SEAMLDR
   Required: >= 2.0.00
   Current:  not directly reported; TDX module loaded successfully (implicit OK)
   ✅ IMPLICIT (verify in BIOS release notes)
```

The kernel doesn't always print SEAMLDR's version. The script falls back to:

- **Implicit OK** — if the TDX module loaded successfully, SEAMLDR is at
  least new enough for that module to verify. Confirm against OEM BIOS
  release notes.
- **UNKNOWN** — TDX module didn't load, so SEAMLDR isn't visible. Resolve
  the TDX module issue first.

SEAMLDR is part of the BIOS/PFR image; you upgrade it by upgrading BIOS to
the IPU level required for your CPU.

### Section 5 — BIOS / IPU

```
5. BIOS / IPU
   Required: IPU 2026.1 (February 2026) or later
   Vendor:   American Megatrends International, LLC.
   Version:  00.20.00
   Release:  07/25/2025
   ⚠️  BIOS version strings are OEM-specific — confirm against your
         OEM's release notes that microcode + SEAMLDR meet the policy above.
```

This section is **always a warning**, never a hard pass/fail. OEM BIOS
version strings (e.g. `00.20.00`, `2.B.7`) don't map cleanly to Intel IPU
levels. The authoritative signal is whether the microcode revision and TDX
module build the BIOS ships meet the policy in sections 2 and 3.

To verify: open your OEM's release notes for the BIOS version shown and
check that they list IPU 2025.3 / 2026.1 (or whatever the policy requires).

### Section 6 — SGX DCAP

```
6. SGX DCAP (Quote Verification Library)
   Required: >= 1.24
   Current:  1.23.100.0-noble1
   ❌ OUT OF DATE
```

Reads the version of the `libsgx-dcap-ql` package via `dpkg`. Only matters
on hosts that produce or verify TDX/SGX attestation quotes:

| Outcome           | Meaning |
|-------------------|---------|
| ✅ COMPLIANT      | `libsgx-dcap-ql` version meets policy. |
| ❌ OUT OF DATE    | Upgrade DCAP from the URL in the summary. |
| ⚠️ Not installed  | DCAP isn't present. Reported as a warning — install only if you need attestation. |

### Section 7 — AESMD service

```
7. AESMD service
   ✅ Running
```

| Outcome                | Meaning |
|------------------------|---------|
| ✅ Running              | `systemctl is-active aesmd` reports active. |
| ❌ QE3 failed to load   | The Quoting Enclave can't load — usually a missing or broken PCK cert chain. Check your PCCS configuration. |
| ⚠️ Not running          | AESMD isn't running. Reported as a warning — install only if you need attestation. |

### Section 8 — Kernel / IOMMU plumbing

```
8. Kernel / IOMMU plumbing
   ❌ Missing kernel parameters: kvm_intel.tdx=1
   ✅ CONFIG_INTEL_TDX_HOST=y
```

Two checks:

1. **Kernel cmdline** must contain every parameter listed in
   `tcb-policy.json` → `common.kernel_params_required` (currently
   `kvm_intel.tdx=1` and `intel_iommu=on`). Add missing entries to
   `GRUB_CMDLINE_LINUX` in `/etc/default/grub`, then run `update-grub` and
   reboot.
2. **Kernel build options** must include each line in
   `common.kernel_config_required` (currently `CONFIG_INTEL_TDX_HOST=y`)
   in `/boot/config-$(uname -r)`. If missing, you need a TDX-aware kernel
   (mainline ≥ 6.8 or distro equivalent).

### Summary block

```
==============================================
  Summary
==============================================

❌ Host is NOT fully compliant. Required actions:

  1. Microcode: upgrade 0x210002c0 → 0x210002d3 or newer.
     Apply BIOS update from your OEM that includes Intel microcode revision
     0x210002d3 for Emerald Rapids (EMR-SP), or load the late-loadable
     microcode from:
       https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files/releases/tag/microcode-20260210
     Release tag: microcode-20260210

  2. TDX module: not loaded. ...

  3. SGX DCAP: upgrade 1.23.100.0-noble1 → 1.24+ from:
       https://github.com/intel/SGXDataCenterAttestationPrimitives/releases

  4. Kernel cmdline: add the following to GRUB_CMDLINE_LINUX and run update-grub:
       kvm_intel.tdx=1

After applying patches, reboot and re-run: sudo ./verify-tcb.sh
```

Each numbered step is a self-contained remediation: the current value, the
required value, the Intel release tag, and the download URL. Apply them in
order, reboot, and re-run.

**Exit codes:** `0` if every required component is compliant, `1` if any
remediation step was added, `2` if `jq` is missing.

## 6. `diagnose-tdx.sh` — plumbing diagnostic

```bash
sudo ./diagnose-tdx.sh > tdx-diagnostic-$(date +%Y%m%d).txt
```

Use this when TDX won't initialize and `verify-tcb.sh` reports "TDX module
not detected." It prints a long, verbose report covering:

- System identity (hostname, serial, manufacturer, model)
- CPU signature with TCB policy match
- Microcode comparison against policy
- BIOS version/date
- Kernel version, `CONFIG_INTEL_TDX_HOST` build option
- Full `/proc/cmdline` and TDX-related parameters
- TDX BIOS-enabled message from dmesg/journalctl
- All `virt/tdx` lines from kernel log
- TDX initialization status (`module initialized` vs missing)
- TDX errors and failures
- KVM TDX module parameter (`/sys/module/kvm_intel/parameters/tdx`)
- IOMMU status from DMAR messages
- TME (Total Memory Encryption) detection
- CPU TDX/SGX/TME feature flags from `cpuid`
- SEAMLDR messages
- A summary of critical issues

It always exits 0 — it's informational only. Save the output and compare it
against a working host, or share it for triage.

## 7. Reading remediation steps

Each step in the summary follows the same shape:

```
N. <Component>: <action>
   <details / context>
   <Intel download URL>
   <release tag, if applicable>
```

Map them to actions:

| Component               | Action                                                                 |
|-------------------------|------------------------------------------------------------------------|
| Microcode               | Apply OEM BIOS update OR install `intel-microcode` package OR load via `iucode-tool` from the Intel release tag. |
| TDX module              | Drop the module image at `/lib/firmware/intel-seam/`, reboot, confirm `dmesg \| grep virt/tdx`. |
| SEAMLDR                 | Upgrade BIOS to the required IPU; SEAMLDR ships inside the BIOS image. |
| BIOS / IPU              | Cross-check OEM release notes; upgrade BIOS if microcode/TDX module are behind. |
| SGX DCAP                | `apt`/`dnf` upgrade DCAP packages, or build from the Intel release tag. |
| AESMD                   | `systemctl enable --now aesmd`; for QE3 errors fix PCCS / PCK chain. |
| Kernel cmdline          | Edit `/etc/default/grub`, run `update-grub`, reboot.                   |
| Kernel build option     | Boot a TDX-aware kernel (mainline ≥ 6.8 or distro equivalent).         |

After every patch, **reboot** and re-run `sudo ./verify-tcb.sh` until the
summary reports compliant.

## 8. Troubleshooting

**`jq is required but not installed`**
Run `sudo ./preflight.sh` once.

**`No TCB policy entry for this CPU`**
The host's `family-model-stepping` isn't in `tcb-policy.json`. Either the
host isn't a supported Xeon, or the policy file needs a new entry — see
[README.md → Updating the policy](README.md#updating-the-policy).

**`TDX module not detected in kernel log`**
Probable causes, in order:

1. TDX disabled in BIOS — enter setup, enable Intel TDX (and SGX, TME-MT).
2. Missing kernel parameter — check section 8 of the report.
3. Missing module image — `/lib/firmware/intel-seam/libtdx.so` (or
   equivalent) isn't present. Install the OEM-provided TDX firmware
   package, or download from the Intel TDX module release page.
4. Kernel without `CONFIG_INTEL_TDX_HOST=y` — boot a TDX-aware kernel.

Run `sudo ./diagnose-tdx.sh` and share the output for triage.

**`SEAMLDR ⚠️ UNKNOWN`**
SEAMLDR isn't reported because the TDX module isn't loaded — fix the TDX
module first.

**OEM BIOS version doesn't match Intel's IPU label**
Expected. OEMs use their own version strings. Look up your BIOS version in
the OEM's release notes; if it includes "IPU 2026.1" or the required IPU
level for your CPU, you're fine. The microcode and TDX module versions in
sections 2 and 3 are the ground-truth signals.

**Microcode is from a *newer* release than `min_microcode_release`**
That's fine. The compliance check is `current ≥ minimum`, never equality.
Newer is always compliant.

## 9. Appendix — exit codes & files

| Script             | Exit 0     | Exit 1                           | Exit 2     |
|--------------------|------------|----------------------------------|------------|
| `verification.sh`  | compliant  | not compliant / unsupported CPU  | jq missing |
| `verify-tcb.sh`    | compliant  | not compliant / unsupported CPU  | jq missing |
| `diagnose-tdx.sh`  | always 0 (informational only)    | —          | —          |

| File              | Purpose                                                          |
|-------------------|------------------------------------------------------------------|
| `tcb-policy.json` | Per-CPU TCB minimums; bump `policy_version` after each TCB-R.    |
| `lib-tcb.sh`      | Bash helpers: CPU detection, policy lookup, version comparison.  |
| `preflight.sh`    | Installs `jq`, `cpuid`, `dmidecode`, `msr-tools`, `pciutils`, …  |
| `verification.sh` | Quick microcode-only check, no sudo.                             |
| `verify-tcb.sh`   | Full compliance report with remediation.                         |
| `diagnose-tdx.sh` | Verbose plumbing/dmesg/IOMMU report for TDX init triage.         |

For the project overview and supported-CPU table, see [README.md](README.md).
