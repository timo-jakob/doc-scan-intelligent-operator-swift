#!/bin/bash

# Invoice Testing Script
# Tests all PDFs in the specified directory for invoice recognition
#
# IMPORTANT: This script requires the Xcode-built binary because MLX Swift
# needs Metal shaders which can only be compiled by Xcode (not swift build).
# To rebuild: xcodebuild -scheme docscan -destination 'platform=macOS' build

DOCSCAN="/Users/timo/Library/Developer/Xcode/DerivedData/doc-scan-intelligent-operator-swift-cimftdfhaznijchfykkomrbhysow/Build/Products/Debug/docscan"
INVOICE_DIR="/Users/timo/Documents/Dokumente/Timo/Finanzen/Rechnungen"
RESULTS_FILE="/tmp/invoice_test_results.txt"
SUMMARY_FILE="/tmp/invoice_test_summary.txt"

# Counters
total=0
recognized=0
extracted=0
failed=0
not_invoice=0

# Clear results file
> "$RESULTS_FILE"

echo "Starting invoice testing..."
echo "Results will be saved to: $RESULTS_FILE"
echo ""

# Find all PDFs excluding _eigene
while IFS= read -r pdf; do
    ((total++))

    # Get just the filename for display
    filename=$(basename "$pdf")
    dirname=$(dirname "$pdf" | sed "s|$INVOICE_DIR/||")

    echo -n "[$total] Testing: $dirname/$filename ... "

    # Run docscan with timeout and capture output
    output=$("$DOCSCAN" "$pdf" --dry-run --auto-resolve ocr 2>&1)
    exit_code=$?

    # Analyze output
    if echo "$output" | grep -q "VLM and OCR agree: This IS an invoice"; then
        ((recognized++))
        if echo "$output" | grep -q "New filename:"; then
            ((extracted++))
            new_name=$(echo "$output" | grep "New filename:" | sed 's/New filename: //')
            echo "OK -> $new_name"
            echo "OK|$dirname/$filename|$new_name" >> "$RESULTS_FILE"
        else
            echo "RECOGNIZED but extraction failed"
            echo "PARTIAL|$dirname/$filename|Recognition OK, extraction failed" >> "$RESULTS_FILE"
        fi
    elif echo "$output" | grep -q "VLM and OCR agree: This is NOT an invoice"; then
        ((not_invoice++))
        echo "NOT AN INVOICE"
        echo "NOT_INVOICE|$dirname/$filename|Both agree not invoice" >> "$RESULTS_FILE"
    elif echo "$output" | grep -q "Auto-resolve: Using OCR"; then
        # Conflict resolved by OCR
        if echo "$output" | grep -q "New filename:"; then
            ((recognized++))
            ((extracted++))
            new_name=$(echo "$output" | grep "New filename:" | sed 's/New filename: //')
            echo "OK (conflict) -> $new_name"
            echo "OK_CONFLICT|$dirname/$filename|$new_name" >> "$RESULTS_FILE"
        else
            ((recognized++))
            echo "RECOGNIZED (conflict) but extraction failed"
            echo "PARTIAL_CONFLICT|$dirname/$filename|Conflict resolved, extraction failed" >> "$RESULTS_FILE"
        fi
    else
        ((failed++))
        error=$(echo "$output" | tail -3 | tr '\n' ' ')
        echo "FAILED: $error"
        echo "FAILED|$dirname/$filename|$error" >> "$RESULTS_FILE"
    fi

done < <(find "$INVOICE_DIR" -name "*.pdf" -type f ! -path "*/_eigene/*" 2>/dev/null)

# Write summary
cat > "$SUMMARY_FILE" << EOF
========================================
INVOICE TESTING SUMMARY
========================================
Total PDFs tested:     $total
Recognized as invoice: $recognized
Successfully extracted: $extracted
Not an invoice:        $not_invoice
Failed:                $failed

Recognition rate: $(echo "scale=1; $recognized * 100 / $total" | bc)%
Extraction rate:  $(echo "scale=1; $extracted * 100 / $total" | bc)%
========================================
EOF

echo ""
cat "$SUMMARY_FILE"
