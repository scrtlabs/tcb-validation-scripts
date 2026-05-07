# Intel TDX TCB Validation Scripts

Validates whether a host meets the **current** Intel TDX Trusted Computing Base
(TCB) policy and lists the exact patches required when it doesn't.

The compliance bar tracks Intel's
[TCB Recovery Attestation](https://www.intel.com/content/www/us/en/developer/topic-technology/software-security-guidance/trusted-computing-base-recovery-attestation.html)
guidance and is encoded in [tcb-policy.json](tcb-policy.json) — keyed by CPU
signature (`family-model-stepping`), so the same scripts validate every
supported Xeon family without code changes.

→ **For a step-by-step walkthrough and how to interpret the output, see
[HOWTO.md](HOWTO.md).**

## Supported CPUs

| Signature  | Codename             | Generation                    | TDX module series |
|------------|----------------------|-------------------------------|-------------------|
| `06-8f-07` | Sapphire Rapids      | 4th Gen Intel Xeon Scalable   | 1.5.x             |
| `06-8f-08` | Sapphire Rapids      | 4th Gen Intel Xeon Scalable   | 1.5.x             |
| `06-cf-02` | Emerald Rapids       | 5th Gen Intel Xeon Scalable   | 1.5.x             |
| `06-ad-01` | Granite Rapids AP/SP | Intel Xeon 6 (P-cores)        | 2.0.x             |
| `06-ae-01` | Granite Rapids-D     | Intel Xeon 6 (P-cores, edge)  | 2.0.x             |
| `06-af-03` | Sierra Forest        | Intel Xeon 6 (E-cores)        | 1.5.x             |

The exact minimum microcode revision, TDX module build, SEAMLDR version, and
required IPU level for each CPU live in [tcb-policy.json](tcb-policy.json).
Update that file (and bump `policy_version`) when Intel publishes a new TCB-R.

## Files

| File                  | Purpose                                                                 |
|-----------------------|-------------------------------------------------------------------------|
| `tcb-policy.json`     | Machine-readable per-CPU TCB policy (microcode, TDX module, SEAMLDR…). |
| `lib-tcb.sh`          | Shared bash helpers: CPU detection, policy lookup, version comparison. |
| `preflight.sh`        | One-time install of `cpuid`, `msr-tools`, `dmidecode`, `jq`, etc.     |
| `verification.sh`     | Quick microcode-only check, no sudo required.                           |
| `verify-tcb.sh`       | Full compliance check: microcode + TDX module + SEAMLDR + DCAP + …      |
| `diagnose-tdx.sh`     | Verbose plumbing diagnostic (BIOS, kernel cmdline, dmesg, IOMMU, …).   |

## Quick start

```bash
git clone git@github.com:scrtlabs/tcb-validation-scripts.git
cd tcb-validation-scripts
chmod +x *.sh

sudo ./preflight.sh        # one-time prereq install
./verification.sh          # quick microcode check (no sudo)
sudo ./verify-tcb.sh       # full compliance check
```

For full instructions and how to read each report, see [HOWTO.md](HOWTO.md).

## How the policy works

`verify-tcb.sh` reads `cpu family`, `model`, and `stepping` from
`/proc/cpuinfo`, formats them as `ff-mm-ss` (e.g. `06-cf-02`), and looks up
the entry in [tcb-policy.json](tcb-policy.json). For each component it
compares the host's current value against the policy minimum and prints a
remediation step (with Intel release tag and download URL) when the host is
behind.

### Updating the policy

When Intel publishes a new TCB recovery (TCB-R *N*):

1. Edit [tcb-policy.json](tcb-policy.json):
   - Bump `policy_version` (use the IPU date, e.g. `2026-08-12`).
   - For each affected CPU, update `min_microcode`,
     `min_microcode_release`, `min_microcode_url`, `min_tdx_module_*`, and
     `min_bios_ipu`.
2. Cross-check sources:
   - [Intel TCB Recovery Attestation](https://www.intel.com/content/www/us/en/developer/topic-technology/software-security-guidance/trusted-computing-base-recovery-attestation.html)
   - [Intel TDX Enabling Guide — TCB Recoveries](https://cc-enabling.trustedservices.intel.com/intel-tdx-enabling-guide/02/tcb_recoveries/)
   - [Intel-Linux-Processor-Microcode-Data-Files releases](https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files/releases)
   - [Intel TDX module releases](https://github.com/intel/confidential-computing.tdx.tdx-module/releases)
3. Run `sudo ./verify-tcb.sh` on a known-good host to confirm the new
   thresholds parse correctly.

No script changes are needed — the JSON drives every check.

## Exit codes

| Script             | 0          | 1                                | 2          |
|--------------------|------------|----------------------------------|------------|
| `verification.sh`  | compliant  | not compliant / unsupported CPU  | jq missing |
| `verify-tcb.sh`    | compliant  | not compliant / unsupported CPU  | jq missing |
| `diagnose-tdx.sh`  | always 0 (informational only)    | —          | —          |

## Notes

- All scripts only **read** system state; they don't modify anything.
- BIOS/IPU strings are OEM-specific; `verify-tcb.sh` prints them but cannot
  authoritatively validate the IPU level. Cross-check against your OEM's
  release notes — the microcode revision and TDX module build it ships are
  the ground truth.
- The DCAP and AESMD checks only matter on hosts that produce or verify
  TDX/SGX attestation quotes; they are reported as warnings (not failures)
  when the components aren't installed.
