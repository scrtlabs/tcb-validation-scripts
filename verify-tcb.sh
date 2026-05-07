#!/bin/bash
#
# verify-tcb.sh - Validate Intel TDX TCB compliance against current Intel guidance.
#
# Detects the host CPU, looks up the per-family policy from tcb-policy.json,
# and reports compliance for microcode, TDX module, SEAMLDR, BIOS/IPU,
# SGX DCAP, and SGX/AESMD plumbing. Lists exact patches required to become
# compliant when components are out of date.
#
# Usage: sudo ./verify-tcb.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib-tcb.sh"

require_jq || exit 2

OVERALL_OK=1
RECOMMENDATIONS=()

note_recommendation() {
    RECOMMENDATIONS+=("$1")
    OVERALL_OK=0
}

print_header() {
    echo "=============================================="
    echo "  Intel TDX TCB Compliance Check"
    echo "  Policy: $(policy_version)"
    echo "  Date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "=============================================="
    echo ""
}

# --- 1. CPU detection ---------------------------------------------------------
print_cpu() {
    SIG=$(get_cpu_signature) || { echo "$TCB_FAIL Could not read CPU signature from /proc/cpuinfo"; exit 1; }
    MODEL_NAME=$(get_cpu_model_name)

    echo "1. CPU"
    echo "   Model:     $MODEL_NAME"
    echo "   Signature: $SIG (family-model-stepping)"

    POLICY=$(policy_for_cpu "$SIG")
    if [ -z "$POLICY" ]; then
        echo "   $TCB_FAIL No TCB policy entry for this CPU."
        echo "   Supported signatures:"
        jq -r '.cpus | keys[] | "     - " + .' "$TCB_POLICY_FILE"
        echo ""
        echo "   This CPU is not in scope for the bundled Intel TDX TCB policy."
        echo "   Update tcb-policy.json or run on a supported Xeon platform."
        exit 1
    fi

    CPU_NAME=$(policy_field "$SIG" name)
    CODENAME=$(policy_field "$SIG" codename)
    GEN=$(policy_field "$SIG" generation)
    echo "   Codename:  $CODENAME"
    echo "   Family:    $GEN"
    echo "   Matched:   $CPU_NAME"
    echo ""
}

# --- 2. Microcode -------------------------------------------------------------
check_microcode() {
    echo "2. Microcode"
    local current min release url
    current=$(get_current_microcode)
    min=$(policy_field "$SIG" min_microcode)
    release=$(policy_field "$SIG" min_microcode_release)
    url=$(policy_field "$SIG" min_microcode_url)

    echo "   Current:  $current"
    echo "   Required: $min ($release)"

    if [ -z "$current" ]; then
        echo "   $TCB_FAIL Could not read microcode version from /proc/cpuinfo"
        note_recommendation "Microcode: unable to read current revision; check /proc/cpuinfo."
    else
        local cmp
        cmp=$(hex_cmp "$current" "$min")
        if [ "$cmp" -ge 0 ]; then
            echo "   $TCB_OK COMPLIANT"
        else
            echo "   $TCB_FAIL OUT OF DATE"
            note_recommendation \
"Microcode: upgrade $current → $min or newer.
     Apply BIOS update from your OEM that includes Intel microcode revision
     $min for $CPU_NAME, or load the late-loadable microcode from:
       $url
     Release tag: $release"
        fi
    fi
    echo ""
}

# --- 3. TDX Module ------------------------------------------------------------
check_tdx_module() {
    echo "3. TDX Module"
    local series min_ver min_build url tdx_info
    series=$(policy_field "$SIG" tdx_module_series)
    min_ver=$(policy_field "$SIG" min_tdx_module_version)
    min_build=$(policy_field "$SIG" min_tdx_module_build)
    url=$(policy_field "$SIG" tdx_module_url)

    echo "   Required: $min_ver (series $series.x, build $min_build) or newer"
    echo "   Source:   $url"

    tdx_info=$(get_tdx_module_info) || tdx_info=""
    if [ -z "$tdx_info" ]; then
        echo "   Current:  $TCB_FAIL TDX module not detected in kernel log"
        note_recommendation \
"TDX module: not loaded. Verify TDX is enabled in BIOS, that the kernel was
     booted with kvm_intel.tdx=1 intel_iommu=on, and that the SEAM module
     image is installed at /lib/firmware/intel-seam/. Latest module:
       $url"
        echo ""
        return
    fi

    read -r MAJ MIN BLD BDATE <<<"$tdx_info"
    local cur_ver="$MAJ.$MIN.$BLD"
    echo "   Current:  major=$MAJ minor=$MIN build=$BLD build_date=$BDATE"

    # Major.minor must match the policy series, build must be >= min build.
    local series_major series_minor
    series_major=${series%.*}
    series_minor=${series#*.}

    if [ "$MAJ" -ne "$series_major" ] || [ "$MIN" -ne "$series_minor" ]; then
        echo "   $TCB_FAIL Wrong module series for this CPU ($MAJ.$MIN, expected $series.x)"
        note_recommendation \
"TDX module: wrong series ($MAJ.$MIN loaded, $series.x required for $CPU_NAME).
     Install module $min_ver from:
       $url"
    elif [ "$BLD" -lt "$min_build" ]; then
        echo "   $TCB_FAIL Build $BLD older than required $min_build"
        note_recommendation \
"TDX module: upgrade build $BLD → $min_build (version $min_ver) from:
       $url"
    else
        echo "   $TCB_OK COMPLIANT"
    fi
    echo ""
}

# --- 4. SEAMLDR ---------------------------------------------------------------
check_seamldr() {
    echo "4. SEAMLDR"
    local min_seamldr current
    min_seamldr=$(policy_field "$SIG" min_seamldr_version)
    current=$(get_seamldr_version)

    echo "   Required: >= $min_seamldr"
    if [ -n "$current" ]; then
        echo "   Current:  $current"
        local cmp
        cmp=$(ver_cmp "$current" "$min_seamldr")
        if [ "$cmp" -ge 0 ]; then
            echo "   $TCB_OK COMPLIANT"
        else
            echo "   $TCB_FAIL OUT OF DATE"
            note_recommendation \
"SEAMLDR: $current < $min_seamldr. SEAMLDR is part of the BIOS/PFR image;
     upgrade BIOS to the IPU level required for this CPU."
        fi
    else
        # Implicit: TDX module loaded successfully implies SEAMLDR works.
        if get_tdx_module_info >/dev/null 2>&1; then
            echo "   Current:  not directly reported; TDX module loaded successfully (implicit OK)"
            echo "   $TCB_OK IMPLICIT (verify in BIOS release notes)"
        else
            echo "   Current:  not detected"
            echo "   $TCB_WARN UNKNOWN — SEAMLDR not visible without TDX module load"
        fi
    fi
    echo ""
}

# --- 5. BIOS / IPU level ------------------------------------------------------
check_bios() {
    echo "5. BIOS / IPU"
    local min_ipu bios vendor version reldate
    min_ipu=$(policy_field "$SIG" min_bios_ipu)
    bios=$(get_bios_info)
    vendor=${bios%%|*}
    version=$(echo "$bios" | cut -d'|' -f2)
    reldate=$(echo "$bios" | cut -d'|' -f3)

    echo "   Required: $min_ipu"
    echo "   Vendor:   ${vendor:-unknown}"
    echo "   Version:  ${version:-unknown}"
    echo "   Release:  ${reldate:-unknown}"
    echo "   $TCB_WARN BIOS version strings are OEM-specific — confirm against your"
    echo "         OEM's release notes that microcode + SEAMLDR meet the policy above."
    echo ""
}

# --- 6. SGX DCAP --------------------------------------------------------------
check_dcap() {
    echo "6. SGX DCAP (Quote Verification Library)"
    local min_dcap dcap_url current_pkg
    min_dcap=$(policy_common_field min_dcap)
    dcap_url=$(policy_common_field dcap_release_url)

    current_pkg=$(dpkg -l 2>/dev/null | awk '/libsgx-dcap-ql/ {print $3; exit}')
    echo "   Required: >= $min_dcap"

    if [ -z "$current_pkg" ]; then
        echo "   Current:  not installed"
        echo "   $TCB_WARN Not installed (only required if this host produces or verifies attestation quotes)"
        note_recommendation \
"SGX DCAP: not installed. If this host produces/verifies TDX attestation
     quotes, install DCAP $min_dcap+ from:
       $dcap_url"
    else
        echo "   Current:  $current_pkg"
        local maj min
        maj=$(echo "$current_pkg" | cut -d. -f1 | sed 's/[^0-9]//g')
        min=$(echo "$current_pkg" | cut -d. -f2 | cut -d- -f1 | sed 's/[^0-9]//g')
        local req_maj=${min_dcap%.*} req_min=${min_dcap#*.}
        if [ "${maj:-0}" -gt "$req_maj" ] || { [ "${maj:-0}" -eq "$req_maj" ] && [ "${min:-0}" -ge "$req_min" ]; }; then
            echo "   $TCB_OK COMPLIANT"
        else
            echo "   $TCB_FAIL OUT OF DATE"
            note_recommendation \
"SGX DCAP: upgrade $current_pkg → $min_dcap+ from:
       $dcap_url"
        fi
    fi
    echo ""
}

# --- 7. AESMD service ---------------------------------------------------------
check_aesmd() {
    echo "7. AESMD service"
    if systemctl is-active --quiet aesmd 2>/dev/null; then
        echo "   $TCB_OK Running"
        if sudo journalctl -u aesmd -n 50 --no-pager 2>/dev/null | grep -qi "failed to load qe3"; then
            echo "   $TCB_FAIL QE3 (Quoting Enclave) failed to load — check Intel SGX PCK Cert chain"
            note_recommendation "AESMD: QE3 failed to load; ensure PCCS / PCK certs are reachable."
        fi
    else
        echo "   $TCB_WARN Not running (only required if this host produces attestation quotes)"
    fi
    echo ""
}

# --- 8. Kernel / IOMMU plumbing ----------------------------------------------
check_kernel_plumbing() {
    echo "8. Kernel / IOMMU plumbing"
    local cmdline kernel_cfg missing_params=()
    cmdline=$(cat /proc/cmdline)
    kernel_cfg="/boot/config-$(uname -r)"

    while IFS= read -r p; do
        [ -z "$p" ] && continue
        local key=${p%=*}
        if ! echo "$cmdline" | grep -qE "(^| )$key="; then
            missing_params+=("$p")
        fi
    done < <(jq -r '.common.kernel_params_required[]?' "$TCB_POLICY_FILE")

    if [ ${#missing_params[@]} -eq 0 ]; then
        echo "   $TCB_OK Kernel cmdline has required TDX/IOMMU parameters"
    else
        echo "   $TCB_FAIL Missing kernel parameters: ${missing_params[*]}"
        note_recommendation \
"Kernel cmdline: add the following to GRUB_CMDLINE_LINUX and run update-grub:
       ${missing_params[*]}"
    fi

    while IFS= read -r req; do
        [ -z "$req" ] && continue
        if [ -f "$kernel_cfg" ] && grep -q "^$req\$" "$kernel_cfg"; then
            echo "   $TCB_OK $req"
        else
            echo "   $TCB_FAIL $req not set in $kernel_cfg"
            note_recommendation \
"Kernel: $req is not enabled. Boot a kernel built with TDX host support
     (mainline >= 6.8 or distro equivalent)."
        fi
    done < <(jq -r '.common.kernel_config_required[]?' "$TCB_POLICY_FILE")
    echo ""
}

# --- Summary ------------------------------------------------------------------
print_summary() {
    echo "=============================================="
    echo "  Summary"
    echo "=============================================="
    if [ "$OVERALL_OK" -eq 1 ]; then
        echo ""
        echo "$TCB_OK This host is compliant with the bundled Intel TDX TCB policy"
        echo "   ($CPU_NAME, policy $(policy_version))."
        echo ""
    else
        echo ""
        echo "$TCB_FAIL Host is NOT fully compliant. Required actions:"
        echo ""
        local i=1
        for r in "${RECOMMENDATIONS[@]}"; do
            echo "  ${i}. ${r}"
            echo ""
            ((i++))
        done
        echo "After applying patches, reboot and re-run: sudo $0"
        echo ""
    fi

    echo "Authoritative source:"
    echo "  $(jq -r '.sources.tcb_recovery_attestation' "$TCB_POLICY_FILE")"
    echo ""
}

print_header
print_cpu
check_microcode
check_tdx_module
check_seamldr
check_bios
check_dcap
check_aesmd
check_kernel_plumbing
print_summary

[ "$OVERALL_OK" -eq 1 ] && exit 0 || exit 1
