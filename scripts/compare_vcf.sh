#!/usr/bin/env bash
# compare_vcf.sh — Compare a sarek VCF against a Kailos production VCF
#
# Usage:
#   ./scripts/compare_vcf.sh <sarek.vcf.gz> <kailos.vcf.gz> [panel.bed]
#
# If a BED file is provided, the Kailos VCF is restricted to those regions
# before comparing (recommended for panel runs).
#
# Output: printed summary + files written to a timestamped directory

set -euo pipefail

SAREK_VCF=${1:-}
KAILOS_VCF=${2:-}
BED=${3:-}

if [[ -z "$SAREK_VCF" || -z "$KAILOS_VCF" ]]; then
    echo "Usage: $0 <sarek.vcf.gz> <kailos.vcf.gz> [panel.bed]"
    exit 1
fi

for f in "$SAREK_VCF" "$KAILOS_VCF"; do
    [[ -f "$f" ]] || { echo "ERROR: File not found: $f"; exit 1; }
done

OUTDIR="comparison_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

# Index inputs if needed
[[ -f "${SAREK_VCF}.tbi" || -f "${SAREK_VCF}.csi" ]] || bcftools index "$SAREK_VCF"
[[ -f "${KAILOS_VCF}.tbi" || -f "${KAILOS_VCF}.csi" ]] || bcftools index "$KAILOS_VCF"

# Optionally restrict Kailos VCF to panel BED
if [[ -n "$BED" ]]; then
    [[ -f "$BED" ]] || { echo "ERROR: BED file not found: $BED"; exit 1; }
    KAILOS_FILTERED="$OUTDIR/kailos_panel.vcf.gz"
    bcftools view -R "$BED" "$KAILOS_VCF" -O z -o "$KAILOS_FILTERED" 2>/dev/null
    bcftools index "$KAILOS_FILTERED"
    COMPARE_VCF="$KAILOS_FILTERED"
    echo "Panel BED: $BED"
else
    COMPARE_VCF="$KAILOS_VCF"
fi

# Run isec
bcftools isec -p "$OUTDIR" "$SAREK_VCF" "$COMPARE_VCF" 2>/dev/null

# Count results
SAREK_TOTAL=$(bcftools view -H "$SAREK_VCF" 2>/dev/null | wc -l | tr -d ' ')
KAILOS_TOTAL=$(bcftools view -H "$COMPARE_VCF" 2>/dev/null | wc -l | tr -d ' ')
SAREK_ONLY=$(grep -vc "^#" "$OUTDIR/0000.vcf" || true)
KAILOS_ONLY=$(grep -vc "^#" "$OUTDIR/0001.vcf" || true)
SHARED=$(grep -vc "^#" "$OUTDIR/0002.vcf" || true)
RECALL=$(awk "BEGIN {printf \"%.1f\", ($SHARED / ($SHARED + $KAILOS_ONLY)) * 100}" 2>/dev/null || echo "N/A")
PRECISION=$(awk "BEGIN {printf \"%.1f\", ($SHARED / ($SHARED + $SAREK_ONLY)) * 100}" 2>/dev/null || echo "N/A")

echo ""
echo "============================================"
echo " VCF Comparison Summary"
echo "============================================"
echo " Sarek VCF:         $SAREK_VCF  ($SAREK_TOTAL variants)"
echo " Kailos VCF:        $KAILOS_VCF  ($KAILOS_TOTAL variants)"
[[ -n "$BED" ]] && echo " Panel BED applied: $BED  ($(grep -c "" "$BED") regions)"
echo "--------------------------------------------"
printf " %-28s %s\n" "Shared by both:"       "$SHARED"
printf " %-28s %s\n" "Only in sarek:"        "$SAREK_ONLY"
printf " %-28s %s\n" "Only in Kailos:"       "$KAILOS_ONLY"
echo "--------------------------------------------"
printf " %-28s %s%%\n" "Recall (vs Kailos):"   "$RECALL"
printf " %-28s %s%%\n" "Precision (vs Kailos):" "$PRECISION"
echo "============================================"
echo ""
echo " Output files in: $OUTDIR/"
echo "   0000.vcf = sarek only"
echo "   0001.vcf = kailos only"
echo "   0002.vcf = shared"
echo ""

# Show shared variants
if (( SHARED > 0 && SHARED <= 100 )); then
    echo "--- Variants called by BOTH pipelines ---"
    grep -v "^#" "$OUTDIR/0002.vcf" | awk '{printf "  %s:%s %s>%s\n", $1,$2,$4,$5}'
    echo ""
fi

# Show the discordant variants if small enough
if (( KAILOS_ONLY <= 50 )); then
    echo "--- Kailos variants NOT called by sarek ---"
    grep -v "^#" "$OUTDIR/0001.vcf" | awk '{printf "  %s:%s %s>%s  FILTER=%s\n", $1,$2,$4,$5,$7}'
    echo ""
fi

if (( SAREK_ONLY <= 50 )); then
    echo "--- Sarek variants NOT in Kailos ---"
    grep -v "^#" "$OUTDIR/0000.vcf" | awk '{printf "  %s:%s %s>%s\n", $1,$2,$4,$5}'
    echo ""
fi
