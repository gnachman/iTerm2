#!/usr/bin/env python3.10
import csv
import fcntl
import json
import signal
import sys
import os
import select
import termios
import time
import tty
import re

# Create a pipe for signal handling
rfd, wfd = os.pipe()
flags = fcntl.fcntl(rfd, fcntl.F_GETFL)
fcntl.fcntl(rfd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

def make_nonblocking(file_obj):
    fd = file_obj.fileno()
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

def make_blocking(file_obj):
    fd = file_obj.fileno()
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)

def replace_control_chars(s):
    def replace_char(c):
        if c == '\x1b':
            return r'\e'
        elif c == '\n':
            return r'\n'
        elif c == '\r':
            return r'\r'
        elif '\x00' <= c <= '\x1F' or c == '\x7F':
            return r'\u{{{:02x}}}'.format(ord(c))
        else:
            return c

    return ''.join(replace_char(c) for c in s)

def set_noncanonical_mode(fd):
    old_settings = termios.tcgetattr(fd)
    new_settings = termios.tcgetattr(fd)
    new_settings[3] &= ~termios.ICANON
    termios.tcsetattr(fd, termios.TCSADRAIN, new_settings)
    return old_settings


def restore_mode(fd, old_settings):
    termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

# Signal handler for SIGINT
def signal_handler(signal, frame):
    os.write(wfd, b'\n')

# Function to convert escaped characters to their actual representation
def unescape_string(s):
    s = s.replace("\\e", "\x1b")
    s = s.replace("\\n", "\n")
    s = s.replace("\\t", "\t")
    s = re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m.group(1), 16)), s)
    return s

# Function to read CSV and execute test steps
def run_test_harness(csv_file, output_file, manual_only=False, no_retry=False, start_index=None):
    results = []
    manual_skipped = 0

    with open(csv_file, mode='r', encoding='utf-8') as file:
        reader = csv.DictReader(file)
        lastkb = ""
        lastalt = ""
        rows = list(reader)

        for index, row in enumerate(rows):
            if start_index is not None and index < start_index:
                continue
            step_number = index
            key = row['Key']
            if len(key) == 0:
                continue

            # Some steps can't be automated: they need a keyboard-layout switch or
            # a modifier-remapping (Super/Hyper/Meta) that the harness can't make on
            # its own, and their keystrokes can't be reliably replayed. Those are
            # flagged TRUE in the Manual column. Skip them in a normal run and count
            # them; a --manual run does the opposite and runs only those.
            is_manual = ((row.get('Manual') or '').strip().upper() == 'TRUE')
            if manual_only:
                if not is_manual:
                    continue
            elif is_manual:
                manual_skipped += 1
                continue

            retrying = True
            while retrying:
                type_ = row['Type']
                modifiers = row['Modifiers']
                option_as_alt = row['Option as alt?']
                keyboard = row['Keyboard']
                mode = row['Mode']
                expected_output = unescape_string(row['Expected output'])

                print(f'\033[2J\033[H', end='', flush=True)
                if keyboard != lastkb:
                    print(f'Switch to {keyboard}')
                    lastkb = keyboard
                if option_as_alt != lastalt and option_as_alt != "NA":
                    print(f'Change config option-as-alt to {option_as_alt}')
                    lastalt = option_as_alt
                if option_as_alt == "TRUE":
                    print(f'\033[?1036h', end='', flush=True)
                else:
                    print(f'\033[?1036l', end='', flush=True)
                if modifiers == "None":
                    mods = ""
                else:
                    mods = f'{modifiers}-'
                if key == "None":
                    description = type_
                else:
                    description = f"{type_} {mods}{key}"

                print(f'\033[={mode}u', end='', flush=True)  # Output control sequence
                print(f'Mode={mode} keyboard={keyboard} opt-as-alt={option_as_alt}')
                print(f'Step {step_number}: {description}')
                print(f'Expecting: {row["Expected output"]}')
                # Drain SIGINT notifs
                try:
                    while True:
                        os.read(rfd, 1)
                except:
                    pass
                try:
                    signal.signal(signal.SIGINT, signal_handler)

                    input_received = []
                    while True:
                        rlist, _, _ = select.select([sys.stdin, rfd], [], [])
                        if sys.stdin in rlist:
                            make_nonblocking(sys.stdin)
                            c = sys.stdin.read(1024)
                            make_blocking(sys.stdin)
                            safe = replace_control_chars(c)
                            input_received.append(c)
                            print(f'Read {safe}')
                            continue
                        if rfd in rlist:
                            os.read(rfd, 1)
                            print("SIGINT")
                            break

                    input_received = ''.join(input_received)
                except KeyboardInterrupt:
                    pass
                if input_received == expected_output:
                    print("Good")
                    retrying = False
                else:
                    print(f'\033[=0u', end='', flush=True)
                    print("Fail. Expected:")
                    print(replace_control_chars(expected_output))
                    print("")
                    print("Actual:")
                    print(replace_control_chars(input_received))
                    print("")
                    if no_retry:
                        yn = "n"
                    else:
                        print("Retry? [yn]")
                        yn = sys.stdin.read(1)
                        time.sleep(0.1)
                    retrying = yn != "n"

            result = {
                'step_number': step_number,
                'input_received': input_received,
                'matched_expected': input_received == expected_output
            }
            results.append(result)

    with open(output_file, mode='w') as file:
        json.dump(results, file, indent=4)

    return manual_skipped

if __name__ == "__main__":
    csv_file = 'steps.csv'  # Input CSV file with test steps

    # Flags may appear in any order:
    #   --manual     run ONLY the tests flagged Manual in steps.csv
    #   --no-retry   don't prompt to retry a failed step
    #   <number>     start at that step index (skips earlier steps)
    manual_only = "--manual" in sys.argv
    no_retry = "--no-retry" in sys.argv
    start_index = None
    for arg in sys.argv[1:]:
        if not arg.startswith("--") and arg.isdigit():
            start_index = int(arg)
            break

    if manual_only:
        suffix = "-manual"
    elif start_index is not None:
        suffix = str(start_index)
    else:
        suffix = ""
    output_file = f'harness{suffix}.json'  # Output JSON file with results

    manual_skipped = 0
    try:
        print(f'\033[?1049h')
        # Save the current terminal settings
        old_settings = set_noncanonical_mode(sys.stdin.fileno())

        # Run the test harness
        manual_skipped = run_test_harness(csv_file, output_file,
                                          manual_only=manual_only,
                                          no_retry=no_retry,
                                          start_index=start_index)
    finally:
        # Restore the terminal settings
        print(f'\033[?1049l')
        restore_mode(sys.stdin.fileno(), old_settings)

    if not manual_only:
        script = os.path.basename(sys.argv[0])
        print(f'Skipped {manual_skipped} manual test(s) that must be run by hand.')
        print(f'To run only the manual tests: python3.10 {script} --manual')
