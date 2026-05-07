#!/bin/bash
#
# verification.sh - Quick microcode-only TCB check (no sudo required).
#
# Detects CPU family, looks up minimum required microcode for that CPU in
# tcb-policy.json, and reports whether /proc/cpuinfo's microcode field meets
# it. For a full check (TDX module, SEAMLDR, BIOS, DCAP) run verify-tcb.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-tcb.sh"

require_jq || exit 2

SIG=$(get_cpu_signature) || { echo "Could not read CPU signature"; exit 1; }
NAME=$(get_cpu_model_name)
MCU=$(get_current_microcode)
POLICY=$(policy_for_cpu "$SIG")

echo "CPU:          $NAME"
echo "Signature:    $SIG"
echo "Microcode:    $MCU"
echo ""

if [ -z "$POLICY" ]; then
    echo "Status: ❌ No TCB policy entry for this CPU ($SIG)."
    echo ""
    echo "Supported CPUs in this policy:"
    jq -r '.cpus | to_entries[] | "  - " + .key + "  " + .value.name' "$TCB_POLICY_FILE"
    exit 1
fi

CPU_NAME=$(policy_field "$SIG" name)
MIN=$(policy_field "$SIG" min_microcode)
RELEASE=$(policy_field "$SIG" min_microcode_release)
URL=$(policy_field "$SIG" min_microcode_url)

echo "Detected:     $CPU_NAME"
echo "Required MCU: >= $MIN  ($RELEASE)"
echo ""

CMP=$(hex_cmp "$MCU" "$MIN")
if [ "$CMP" -ge 0 ]; then
    echo "Status: ✅ Microcode meets policy ($(policy_version))."
    echo ""
    echo "Run 'sudo ./verify-tcb.sh' for the full check (TDX module, SEAMLDR, BIOS, DCAP)."
    exit 0
else
    echo "Status: ❌ Microcode is OUT OF DATE for current Intel TDX TCB policy."
    echo ""
    echo "Recommendation:"
    echo "  Upgrade microcode to $MIN or newer."
    echo "  Apply OEM BIOS update containing this revision, or load late from:"
    echo "    $URL"
    echo "  Release tag: $RELEASE"
    exit 1
fi
