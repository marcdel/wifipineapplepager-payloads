#!/bin/bash
# Tests for flock_signatures.sh
# Run with: bash flock_signatures_test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/flock_signatures.sh"

# ============================================================================
# TEST FRAMEWORK
# ============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    ((TESTS_RUN++))
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    Expected: '$expected', Actual: '$actual'"
    fi
}

assert_return_code() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    ((TESTS_RUN++))
    if [[ "$expected" -eq "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "  ${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++))
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    Expected: $expected, Actual: $actual"
    fi
}

print_header() {
    echo ""
    echo -e "${YELLOW}$1${NC}"
}

# ============================================================================
# flock_check_mac_prefix
# ============================================================================

print_header "flock_check_mac_prefix()"

flock_check_mac_prefix "58:8e:81:aa:bb:cc"
assert_return_code 0 $? "Matches FS Ext Battery prefix"
assert_equals "FS Ext Battery" "$FLOCK_MATCH_TYPE" "Sets correct type"

flock_check_mac_prefix "70:c9:4e:11:22:33"
assert_return_code 0 $? "Matches Flock WiFi prefix"
assert_equals "Flock WiFi" "$FLOCK_MATCH_TYPE" "Sets correct type"

flock_check_mac_prefix "70:C9:4E:11:22:33"
assert_return_code 0 $? "Case insensitive matching"

flock_check_mac_prefix "aa:bb:cc:dd:ee:ff"
assert_return_code 1 $? "Rejects non-matching MAC"
assert_equals "" "$FLOCK_MATCH_TYPE" "Clears type on non-match"

flock_check_mac_prefix ""
assert_return_code 1 $? "Rejects empty MAC"

# ============================================================================
# flock_check_ssid_pattern
# ============================================================================

print_header "flock_check_ssid_pattern()"

flock_check_ssid_pattern "flock"
assert_return_code 0 $? "Matches 'flock' pattern"

flock_check_ssid_pattern "FLOCK"
assert_return_code 0 $? "Case insensitive matching"

flock_check_ssid_pattern "MyFlockNetwork"
assert_return_code 0 $? "Matches substring"

flock_check_ssid_pattern "FS Ext Battery"
assert_return_code 0 $? "Matches 'FS Ext Battery' pattern"

flock_check_ssid_pattern "HomeNetwork"
assert_return_code 1 $? "Rejects non-matching SSID"

flock_check_ssid_pattern ""
assert_return_code 1 $? "Rejects empty SSID (hidden network)"

flock_check_ssid_pattern "[Hidden]"
assert_return_code 1 $? "Rejects '[Hidden]' placeholder"

# ============================================================================
# flock_check_ble_name
# ============================================================================

print_header "flock_check_ble_name()"

flock_check_ble_name "Flock"
assert_return_code 0 $? "Matches 'Flock' name"

flock_check_ble_name "FS Ext Battery"
assert_return_code 0 $? "Matches 'FS Ext Battery' name"

flock_check_ble_name "flock"
assert_return_code 0 $? "Case insensitive matching"

flock_check_ble_name "MyPhone"
assert_return_code 1 $? "Rejects non-matching name"

flock_check_ble_name ""
assert_return_code 1 $? "Rejects empty name"

# ============================================================================
# flock_check_device
# ============================================================================

print_header "flock_check_device()"

# MAC prefix detection
flock_check_device "58:8e:81:aa:bb:cc" "RandomNetwork" "wifi"
assert_return_code 0 $? "Detects by MAC prefix (ignores SSID)"
assert_equals "MAC Prefix" "$FLOCK_DETECTION_METHOD" "Reports MAC Prefix method"

# SSID detection (when MAC doesn't match)
flock_check_device "aa:bb:cc:dd:ee:ff" "FlockNetwork" "wifi"
assert_return_code 0 $? "Detects by SSID when MAC doesn't match"
assert_equals "SSID Pattern" "$FLOCK_DETECTION_METHOD" "Reports SSID Pattern method"

# BLE detection
flock_check_device "aa:bb:cc:dd:ee:ff" "FS Ext Battery" "ble"
assert_return_code 0 $? "Detects by BLE name"
assert_equals "BLE Name" "$FLOCK_DETECTION_METHOD" "Reports BLE Name method"

# MAC takes precedence
flock_check_device "70:c9:4e:11:22:33" "FlockNetwork" "wifi"
assert_equals "MAC Prefix" "$FLOCK_DETECTION_METHOD" "MAC prefix takes precedence over SSID"

# No match cases
flock_check_device "aa:bb:cc:dd:ee:ff" "HomeNetwork" "wifi"
assert_return_code 1 $? "Rejects non-matching wifi device"

flock_check_device "aa:bb:cc:dd:ee:ff" "" "wifi"
assert_return_code 1 $? "Rejects hidden SSID with non-matching MAC"

# Type handling
flock_check_device "aa:bb:cc:dd:ee:ff" "FlockNetwork" "WIFI"
assert_return_code 1 $? "Type is case-sensitive ('WIFI' fails)"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "========================================"
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All $TESTS_RUN tests passed${NC}"
    exit 0
else
    echo -e "${RED}$TESTS_FAILED of $TESTS_RUN tests failed${NC}"
    exit 1
fi
