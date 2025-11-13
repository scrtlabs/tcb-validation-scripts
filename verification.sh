#!/bin/bash
#
# Check what you currently have
CURRENT_MCU=$(grep microcode /proc/cpuinfo | head -1 | awk '{print $3}')

echo "Current Microcode: $CURRENT_MCU"
echo ""

# Determine your update path
if [[ "$CURRENT_MCU" < "0x21000201" ]]; then
    echo "Status: Very outdated - Need TCB-R 18 or later"
    echo "Recommendation: Update to TCB-R 20 directly (0x210002B3+)"
elif [[ "$CURRENT_MCU" < "0x21000290" ]]; then
    echo "Status: Pre-UPLR2 - On early TCB-R 18"
    echo "Recommendation: Update to TCB-R 20 (0x210002B3+)"
elif [[ "$CURRENT_MCU" < "0x210002b3" ]]; then
    echo "Status: On TCB-R 18 (UPLR2) or TCB-R 19"
    echo "Recommendation: Update to TCB-R 20 (0x210002B3+)"
else
    echo "Status: On TCB-R 20 or later"
    echo "Recommendation: Already compliant, no action needed"
fi