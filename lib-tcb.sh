#!/bin/bash
# Shared helpers for TCB validation scripts.
# Source this file from other scripts: . "$(dirname "$0")/lib-tcb.sh"

TCB_POLICY_FILE="${TCB_POLICY_FILE:-$(dirname "${BASH_SOURCE[0]}")/tcb-policy.json}"

# Colors / status markers
TCB_OK="✅"
TCB_WARN="⚠️ "
TCB_FAIL="❌"
TCB_INFO="ℹ️ "

require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "$TCB_FAIL jq is required but not installed. Run ./preflight.sh first." >&2
        return 1
    fi
}

# Read the host CPU signature in Intel "ff-mm-ss" format (e.g. 06-cf-02).
# Reads from /proc/cpuinfo so no sudo / cpuid binary is required.
get_cpu_signature() {
    local family model stepping
    family=$(awk -F: '/^cpu family[[:space:]]*:/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' /proc/cpuinfo)
    model=$(awk -F: '/^model[[:space:]]*:/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' /proc/cpuinfo)
    stepping=$(awk -F: '/^stepping[[:space:]]*:/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' /proc/cpuinfo)

    if [ -z "$family" ] || [ -z "$model" ] || [ -z "$stepping" ]; then
        return 1
    fi

    printf "%02x-%02x-%02x" "$family" "$model" "$stepping"
}

get_cpu_model_name() {
    awk -F: '/^model name/ {sub(/^[[:space:]]+/,"",$2); print $2; exit}' /proc/cpuinfo
}

get_current_microcode() {
    awk -F: '/^microcode/ {gsub(/[[:space:]]/,"",$2); print tolower($2); exit}' /proc/cpuinfo
}

# Compare two hex microcode revisions ("0x...") numerically.
# Echoes -1 if a<b, 0 if a==b, 1 if a>b.
hex_cmp() {
    local a=$(( ${1} ))
    local b=$(( ${2} ))
    if [ "$a" -lt "$b" ]; then echo -1
    elif [ "$a" -gt "$b" ]; then echo 1
    else echo 0
    fi
}

# Look up a CPU's policy entry by signature. Echoes the JSON object or empty
# string if not found.
policy_for_cpu() {
    local sig="$1"
    jq -e --arg k "$sig" '.cpus[$k] // empty' "$TCB_POLICY_FILE" 2>/dev/null
}

policy_field() {
    local sig="$1" field="$2"
    jq -r --arg k "$sig" --arg f "$field" '.cpus[$k][$f] // ""' "$TCB_POLICY_FILE" 2>/dev/null
}

policy_common_field() {
    local field="$1"
    jq -r --arg f "$field" '.common[$f] // ""' "$TCB_POLICY_FILE" 2>/dev/null
}

policy_version() {
    jq -r '.policy_version // "unknown"' "$TCB_POLICY_FILE" 2>/dev/null
}

# Parse the TDX module version triple (major.minor.patch) and build_num from
# kernel log. Echoes "MAJOR MINOR BUILD BUILD_DATE" or empty on failure.
get_tdx_module_info() {
    local line major minor build build_date
    line=$(sudo dmesg 2>/dev/null | grep -E "virt/tdx.*(major|minor|build_num|build_date)" | tail -5)
    if [ -z "$line" ]; then
        line=$(sudo journalctl -k --no-pager 2>/dev/null | grep -E "virt/tdx.*(major|minor|build_num|build_date)" | tail -5)
    fi
    [ -z "$line" ] && return 1

    major=$(echo "$line" | grep -oP 'major_version \K\d+' | tail -1)
    minor=$(echo "$line" | grep -oP 'minor_version \K\d+' | tail -1)
    build=$(echo "$line" | grep -oP 'build_num \K\d+' | tail -1)
    build_date=$(echo "$line" | grep -oP 'build_date \K\d+' | tail -1)

    [ -z "$major" ] && return 1
    echo "$major $minor $build $build_date"
}

get_seamldr_version() {
    sudo dmesg 2>/dev/null | grep -i "seamldr.*version" | grep -oP 'version \K[0-9.]+' | tail -1
}

get_bios_info() {
    sudo dmidecode -t bios 2>/dev/null | awk -F: '
        /Vendor:/      {gsub(/^[[:space:]]+/,"",$2); v=$2}
        /Version:/     {gsub(/^[[:space:]]+/,"",$2); ver=$2}
        /Release Date/ {gsub(/^[[:space:]]+/,"",$2); rd=$2}
        END {print v "|" ver "|" rd}'
}

# Compare semver-style "MAJOR.MINOR.PATCH" strings. Echoes -1/0/1.
ver_cmp() {
    local a="$1" b="$2"
    local IFS='.'
    local -a aa=($a) bb=($b)
    local i
    for ((i=0; i<3; i++)); do
        local av=${aa[i]:-0} bv=${bb[i]:-0}
        if [ "$av" -lt "$bv" ]; then echo -1; return; fi
        if [ "$av" -gt "$bv" ]; then echo 1; return; fi
    done
    echo 0
}
