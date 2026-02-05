#!/bin/bash

# Test script for color reset fix
# This script walks through the manual test plan for verifying that
# reset control sequences restore Edit Session colors, not original profile colors.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

print_header() {
    echo ""
    echo "=============================================="
    echo -e "${YELLOW}$1${NC}"
    echo "=============================================="
    echo ""
}

print_step() {
    echo -e "${BLUE}>>> $1${NC}"
}

print_instruction() {
    echo -e "${YELLOW}MANUAL STEP: $1${NC}"
}

ask_confirmation() {
    local prompt="$1"
    local response
    echo ""
    read -p "$prompt (y/n/s to skip): " response
    case "$response" in
        y|Y) return 0 ;;
        s|S)
            echo -e "${YELLOW}Skipped${NC}"
            ((SKIP_COUNT++))
            return 2
            ;;
        *) return 1 ;;
    esac
}

record_result() {
    local result=$1
    local test_name="$2"
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}PASS: $test_name${NC}"
        ((PASS_COUNT++))
    elif [ $result -eq 2 ]; then
        : # Already counted as skip
    else
        echo -e "${RED}FAIL: $test_name${NC}"
        ((FAIL_COUNT++))
    fi
}

wait_for_user() {
    echo ""
    read -p "Press Enter when ready to continue..."
}

# Test 1: Basic Foreground Color Reset
test_1() {
    print_header "Test 1: Basic Foreground Color Reset"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Foreground' to RED"
    wait_for_user

    print_step "Setting foreground to BLUE via escape sequence..."
    printf '\e]10;#0000ff\a'
    sleep 0.5

    if ask_confirmation "Is the foreground text now BLUE?"; then
        print_step "Resetting foreground via escape sequence..."
        printf '\e]110\a'
        sleep 0.5

        if ask_confirmation "Did the foreground return to RED (not white/original)?"; then
            record_result 0 "Test 1: Basic Foreground Color Reset"
        else
            record_result 1 "Test 1: Basic Foreground Color Reset"
        fi
    else
        echo "Escape sequence to set color didn't work"
        record_result 1 "Test 1: Basic Foreground Color Reset"
    fi
}

# Test 2: Basic Background Color Reset
test_2() {
    print_header "Test 2: Basic Background Color Reset"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Background' to GREEN"
    wait_for_user

    print_step "Setting background to BLUE via escape sequence..."
    printf '\e]11;#0000ff\a'
    sleep 0.5

    if ask_confirmation "Is the background now BLUE?"; then
        print_step "Resetting background via escape sequence..."
        printf '\e]111\a'
        sleep 0.5

        if ask_confirmation "Did the background return to GREEN (not original)?"; then
            record_result 0 "Test 2: Basic Background Color Reset"
        else
            record_result 1 "Test 2: Basic Background Color Reset"
        fi
    else
        echo "Escape sequence to set color didn't work"
        record_result 1 "Test 2: Basic Background Color Reset"
    fi
}

# Test 3: ANSI Color Reset (OSC 4)
test_3() {
    print_header "Test 3: ANSI Color Reset (OSC 4)"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'ANSI Red' (Ansi 1 Color) to ORANGE"
    wait_for_user

    print_step "Displaying text in ANSI color 1 (should be ORANGE)..."
    printf '\e[31mThis text should be ORANGE\e[0m\n'

    if ask_confirmation "Is the text above ORANGE?"; then
        print_step "Setting ANSI color 1 to GREEN via escape sequence..."
        printf '\e]4;1;#00ff00\a'
        sleep 0.5
        printf '\e[31mThis text should now be GREEN\e[0m\n'

        if ask_confirmation "Is the text above GREEN?"; then
            print_step "Resetting ANSI color 1 via escape sequence..."
            printf '\e]104;1\a'
            sleep 0.5
            printf '\e[31mThis text should be ORANGE again\e[0m\n'

            if ask_confirmation "Did ANSI red return to ORANGE (not original red)?"; then
                record_result 0 "Test 3: ANSI Color Reset"
            else
                record_result 1 "Test 3: ANSI Color Reset"
            fi
        else
            record_result 1 "Test 3: ANSI Color Reset"
        fi
    else
        record_result 1 "Test 3: ANSI Color Reset"
    fi
}

# Test 4: Cursor Color Reset (OSC 12)
test_4() {
    print_header "Test 4: Cursor Color Reset (OSC 12)"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Cursor' color to PURPLE"
    wait_for_user

    if ask_confirmation "Is the cursor PURPLE?"; then
        print_step "Setting cursor to YELLOW via escape sequence..."
        printf '\e]12;#ffff00\a'
        sleep 0.5

        if ask_confirmation "Is the cursor now YELLOW?"; then
            print_step "Resetting cursor color via escape sequence..."
            printf '\e]112\a'
            sleep 0.5

            if ask_confirmation "Did the cursor return to PURPLE (not original)?"; then
                record_result 0 "Test 4: Cursor Color Reset"
            else
                record_result 1 "Test 4: Cursor Color Reset"
            fi
        else
            record_result 1 "Test 4: Cursor Color Reset"
        fi
    else
        record_result 1 "Test 4: Cursor Color Reset"
    fi
}

# Test 5: Selection Color Reset (OSC 17)
test_5() {
    print_header "Test 5: Selection Color Reset (OSC 17)"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Selection' color to CYAN"
    wait_for_user

    echo "Select some of this text to verify the selection color"

    if ask_confirmation "Is the selection background CYAN when you select text?"; then
        print_step "Setting selection background to RED via escape sequence..."
        printf '\e]17;#ff0000\a'
        sleep 0.5

        echo "Select some text again to see the new color"

        if ask_confirmation "Is the selection background now RED?"; then
            print_step "Resetting selection background via escape sequence..."
            printf '\e]117\a'
            sleep 0.5

            echo "Select text once more"

            if ask_confirmation "Did the selection background return to CYAN (not original)?"; then
                record_result 0 "Test 5: Selection Color Reset"
            else
                record_result 1 "Test 5: Selection Color Reset"
            fi
        else
            record_result 1 "Test 5: Selection Color Reset"
        fi
    else
        record_result 1 "Test 5: Selection Color Reset"
    fi
}

# Test 6: Edit Session After Escape Sequence
test_6() {
    print_header "Test 6: Edit Session After Escape Sequence"
    echo "This tests that Edit Session changes clear the baseline"

    print_step "Setting foreground to BLUE via escape sequence..."
    printf '\e]10;#0000ff\a'
    sleep 0.5

    if ask_confirmation "Is the foreground BLUE?"; then
        print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Foreground' to GREEN"
        wait_for_user

        if ask_confirmation "Is the foreground now GREEN?"; then
            print_step "Setting foreground to RED via escape sequence..."
            printf '\e]10;#ff0000\a'
            sleep 0.5

            if ask_confirmation "Is the foreground now RED?"; then
                print_step "Resetting foreground via escape sequence..."
                printf '\e]110\a'
                sleep 0.5

                if ask_confirmation "Did the foreground return to GREEN (the Edit Session value)?"; then
                    record_result 0 "Test 6: Edit Session After Escape Sequence"
                else
                    record_result 1 "Test 6: Edit Session After Escape Sequence"
                fi
            else
                record_result 1 "Test 6: Edit Session After Escape Sequence"
            fi
        else
            record_result 1 "Test 6: Edit Session After Escape Sequence"
        fi
    else
        record_result 1 "Test 6: Edit Session After Escape Sequence"
    fi
}

# Test 7: Multiple Escape Sequences Before Reset
test_7() {
    print_header "Test 7: Multiple Escape Sequences Before Reset"
    echo "This tests that the baseline is saved on first change, not overwritten"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Foreground' to RED"
    wait_for_user

    print_step "Setting foreground to BLUE..."
    printf '\e]10;#0000ff\a'
    sleep 0.3

    print_step "Setting foreground to GREEN..."
    printf '\e]10;#00ff00\a'
    sleep 0.3

    print_step "Setting foreground to YELLOW..."
    printf '\e]10;#ffff00\a'
    sleep 0.3

    if ask_confirmation "Is the foreground now YELLOW?"; then
        print_step "Resetting foreground..."
        printf '\e]110\a'
        sleep 0.5

        if ask_confirmation "Did the foreground return to RED (not blue/green/yellow)?"; then
            record_result 0 "Test 7: Multiple Escape Sequences Before Reset"
        else
            record_result 1 "Test 7: Multiple Escape Sequences Before Reset"
        fi
    else
        record_result 1 "Test 7: Multiple Escape Sequences Before Reset"
    fi
}

# Test 8: Tab Color Set and Reset
test_8() {
    print_header "Test 8: Tab Color Set and Reset"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Enable 'Tab Color' and set it to RED"
    wait_for_user

    if ask_confirmation "Is the tab color RED?"; then
        print_step "Setting tab color to BLUE via escape sequence..."
        printf '\e]1337;SetColors=tab=0000ff\a'
        sleep 0.5

        if ask_confirmation "Is the tab color now BLUE?"; then
            print_step "Resetting tab color via escape sequence..."
            printf '\e]1337;SetColors=tab=default\a'
            sleep 0.5

            if ask_confirmation "Did the tab color return to RED (not disabled)?"; then
                record_result 0 "Test 8: Tab Color Set and Reset"
            else
                record_result 1 "Test 8: Tab Color Set and Reset"
            fi
        else
            record_result 1 "Test 8: Tab Color Set and Reset"
        fi
    else
        record_result 1 "Test 8: Tab Color Set and Reset"
    fi
}

# Test 9: Tab Color Component Changes
test_9() {
    print_header "Test 9: Tab Color Component Changes"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Enable 'Tab Color' and set it to RED"
    wait_for_user

    if ask_confirmation "Is the tab color RED?"; then
        print_step "Setting tab blue component to max via escape sequence..."
        printf '\e]6;1;bg;blue;brightness;255\a'
        sleep 0.5

        if ask_confirmation "Did the tab color change (should have blue added)?"; then
            print_step "Resetting tab color via escape sequence..."
            printf '\e]1337;SetColors=tab=default\a'
            sleep 0.5

            if ask_confirmation "Did the tab color return to RED?"; then
                record_result 0 "Test 9: Tab Color Component Changes"
            else
                record_result 1 "Test 9: Tab Color Component Changes"
            fi
        else
            record_result 1 "Test 9: Tab Color Component Changes"
        fi
    else
        record_result 1 "Test 9: Tab Color Component Changes"
    fi
}

# Test 10: Light/Dark Mode
test_10() {
    print_header "Test 10: Light/Dark Mode - Separate Colors Enabled"

    print_instruction "1. Open Edit Session (Cmd+I) > Colors"
    print_instruction "2. Enable 'Use different colors for light mode and dark mode'"
    print_instruction "3. Make sure you're in DARK mode (check system appearance)"
    print_instruction "4. Change 'Foreground' to RED"
    wait_for_user

    if ask_confirmation "Is the foreground RED?"; then
        print_step "Setting foreground to BLUE via escape sequence..."
        printf '\e]10;#0000ff\a'
        sleep 0.5

        print_step "Resetting foreground..."
        printf '\e]110\a'
        sleep 0.5

        if ask_confirmation "Did the foreground return to RED?"; then
            print_instruction "Now switch to LIGHT mode (System Preferences > Appearance)"
            wait_for_user

            if ask_confirmation "Is the light mode foreground UNAFFECTED (original profile color, not red)?"; then
                record_result 0 "Test 10: Light/Dark Mode"
            else
                record_result 1 "Test 10: Light/Dark Mode"
            fi
        else
            record_result 1 "Test 10: Light/Dark Mode"
        fi
    else
        record_result 1 "Test 10: Light/Dark Mode"
    fi
}

# Test 11: Color Preset via Escape Sequence
test_11() {
    print_header "Test 11: Color Preset via Escape Sequence"
    echo "A preset loaded via escape sequence is still an escape sequence change."
    echo "Reset should restore to the Edit Session baseline, not the preset."

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Foreground' to RED"
    wait_for_user

    print_step "Loading 'Tango Dark' preset via escape sequence..."
    printf '\e]1337;SetColors=preset=Tango Dark\a'
    sleep 0.5

    if ask_confirmation "Did the colors change to Tango Dark preset?"; then
        print_step "Setting foreground to GREEN..."
        printf '\e]10;#00ff00\a'
        sleep 0.5

        print_step "Resetting foreground..."
        printf '\e]110\a'
        sleep 0.5

        if ask_confirmation "Did the foreground return to RED (the Edit Session value, not Tango Dark)?"; then
            record_result 0 "Test 11: Color Preset via Escape Sequence"
        else
            record_result 1 "Test 11: Color Preset via Escape Sequence"
        fi
    else
        record_result 1 "Test 11: Color Preset via Escape Sequence"
    fi
}

# Test 12: Push/Pop Colors (simple case)
test_12() {
    print_header "Test 12: Push/Pop Colors (simple case)"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Foreground' to RED"
    wait_for_user

    print_step "Pushing colors..."
    printf '\e[#P'
    sleep 0.3

    print_step "Setting foreground to BLUE..."
    printf '\e]10;#0000ff\a'
    sleep 0.3

    print_step "Popping colors..."
    printf '\e[#Q'
    sleep 0.3

    if ask_confirmation "Is the foreground back to RED (from pop)?"; then
        print_step "Setting foreground to GREEN..."
        printf '\e]10;#00ff00\a'
        sleep 0.3

        print_step "Resetting foreground..."
        printf '\e]110\a'
        sleep 0.5

        if ask_confirmation "Did the foreground return to RED (Edit Session value preserved through push/pop)?"; then
            record_result 0 "Test 12: Push/Pop Colors (simple)"
        else
            record_result 1 "Test 12: Push/Pop Colors (simple)"
        fi
    else
        record_result 1 "Test 12: Push/Pop Colors (simple)"
    fi
}

# Test 13: Push/Pop Colors (Edit Session between)
test_13() {
    print_header "Test 13: Push/Pop Colors (Edit Session between push/pop)"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Foreground' to RED"
    wait_for_user

    print_step "Pushing colors (saves RED)..."
    printf '\e[#P'
    sleep 0.3

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Foreground' to GREEN"
    wait_for_user

    print_step "Setting foreground to BLUE..."
    printf '\e]10;#0000ff\a'
    sleep 0.3

    print_step "Popping colors (restores RED from push)..."
    printf '\e[#Q'
    sleep 0.3

    if ask_confirmation "Is the foreground RED (from the push, not GREEN)?"; then
        print_step "Setting foreground to YELLOW..."
        printf '\e]10;#ffff00\a'
        sleep 0.3

        print_step "Resetting foreground..."
        printf '\e]110\a'
        sleep 0.5

        if ask_confirmation "Did the foreground return to GREEN (Edit Session value, NOT the popped RED)?"; then
            record_result 0 "Test 13: Push/Pop Colors (Edit Session between)"
        else
            record_result 1 "Test 13: Push/Pop Colors (Edit Session between)"
        fi
    else
        record_result 1 "Test 13: Push/Pop Colors (Edit Session between)"
    fi
}

# Test 14: No Edit Session Changes (Original Behavior)
test_14() {
    print_header "Test 14: No Edit Session Changes (Original Behavior)"
    echo "This test requires a FRESH session with NO Edit Session changes"

    print_instruction "Please open a NEW terminal session/tab (don't make any Edit Session changes)"
    wait_for_user

    echo "Note the current foreground color"

    print_step "Setting foreground to BLUE..."
    printf '\e]10;#0000ff\a'
    sleep 0.5

    print_step "Resetting foreground..."
    printf '\e]110\a'
    sleep 0.5

    if ask_confirmation "Did the foreground return to the ORIGINAL profile color (the default)?"; then
        record_result 0 "Test 14: No Edit Session Changes"
    else
        record_result 1 "Test 14: No Edit Session Changes"
    fi
}

# Test 15: SetColors with Named Colors
test_15() {
    print_header "Test 15: SetColors with Named Colors"

    print_instruction "Open Edit Session (Cmd+I) > Colors > Change 'Foreground' to RED"
    wait_for_user

    print_step "Setting foreground to BLUE via SetColors..."
    printf '\e]1337;SetColors=fg=0000ff\a'
    sleep 0.5

    if ask_confirmation "Is the foreground BLUE?"; then
        print_step "Resetting foreground via OSC 110..."
        printf '\e]110\a'
        sleep 0.5

        if ask_confirmation "Did the foreground return to RED?"; then
            record_result 0 "Test 15: SetColors with Named Colors"
        else
            record_result 1 "Test 15: SetColors with Named Colors"
        fi
    else
        record_result 1 "Test 15: SetColors with Named Colors"
    fi
}

# Test 16: Multiple Colors in Same Sequence
test_16() {
    print_header "Test 16: Multiple Colors in Same Sequence"

    print_instruction "Open Edit Session (Cmd+I) > Colors:"
    print_instruction "  - Change 'Foreground' to RED"
    print_instruction "  - Change 'Background' to GREEN"
    wait_for_user

    print_step "Setting both colors via SetColors..."
    printf '\e]1337;SetColors=fg=0000ff,bg=ffff00\a'
    sleep 0.5

    if ask_confirmation "Is foreground BLUE and background YELLOW?"; then
        print_step "Resetting foreground only..."
        printf '\e]110\a'
        sleep 0.5

        if ask_confirmation "Is foreground RED and background still YELLOW?"; then
            print_step "Resetting background..."
            printf '\e]111\a'
            sleep 0.5

            if ask_confirmation "Did both return to Edit Session values (RED fg, GREEN bg)?"; then
                record_result 0 "Test 16: Multiple Colors in Same Sequence"
            else
                record_result 1 "Test 16: Multiple Colors in Same Sequence"
            fi
        else
            record_result 1 "Test 16: Multiple Colors in Same Sequence"
        fi
    else
        record_result 1 "Test 16: Multiple Colors in Same Sequence"
    fi
}

# Print summary
print_summary() {
    print_header "TEST SUMMARY"
    echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
    echo -e "${RED}Failed: $FAIL_COUNT${NC}"
    echo -e "${YELLOW}Skipped: $SKIP_COUNT${NC}"
    echo ""

    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo -e "${RED}Some tests failed. Please review the results above.${NC}"
    fi
}

# Main menu
main_menu() {
    echo ""
    echo "Color Reset Test Suite"
    echo "======================"
    echo ""
    echo "Tests available:"
    echo "  1) Test 1: Basic Foreground Color Reset"
    echo "  2) Test 2: Basic Background Color Reset"
    echo "  3) Test 3: ANSI Color Reset (OSC 4)"
    echo "  4) Test 4: Cursor Color Reset (OSC 12)"
    echo "  5) Test 5: Selection Color Reset (OSC 17)"
    echo "  6) Test 6: Edit Session After Escape Sequence"
    echo "  7) Test 7: Multiple Escape Sequences Before Reset"
    echo "  8) Test 8: Tab Color Set and Reset"
    echo "  9) Test 9: Tab Color Component Changes"
    echo " 10) Test 10: Light/Dark Mode"
    echo " 11) Test 11: Color Preset via Escape Sequence"
    echo " 12) Test 12: Push/Pop Colors (simple)"
    echo " 13) Test 13: Push/Pop Colors (Edit Session between)"
    echo " 14) Test 14: No Edit Session Changes"
    echo " 15) Test 15: SetColors with Named Colors"
    echo " 16) Test 16: Multiple Colors in Same Sequence"
    echo ""
    echo "  a) Run ALL tests"
    echo "  q) Quit"
    echo ""
    read -p "Select test(s) to run: " choice

    case "$choice" in
        1) test_1 ;;
        2) test_2 ;;
        3) test_3 ;;
        4) test_4 ;;
        5) test_5 ;;
        6) test_6 ;;
        7) test_7 ;;
        8) test_8 ;;
        9) test_9 ;;
        10) test_10 ;;
        11) test_11 ;;
        12) test_12 ;;
        13) test_13 ;;
        14) test_14 ;;
        15) test_15 ;;
        16) test_16 ;;
        a|A)
            test_1
            test_2
            test_3
            test_4
            test_5
            test_6
            test_7
            test_8
            test_9
            test_10
            test_11
            test_12
            test_13
            test_14
            test_15
            test_16
            print_summary
            ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice" ;;
    esac

    if [ "$choice" != "a" ] && [ "$choice" != "A" ] && [ "$choice" != "q" ] && [ "$choice" != "Q" ]; then
        main_menu
    fi
}

# Start
echo "=========================================="
echo "  iTerm2 Color Reset Test Suite"
echo "=========================================="
echo ""
echo "This script will guide you through testing"
echo "the color reset fix."
echo ""
echo "IMPORTANT: Run this in the iTerm2 build you"
echo "want to test (the Development build)."
echo ""

main_menu
