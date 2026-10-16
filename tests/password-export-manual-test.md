# Password export/import manual test

Run a debug build with `make run`. Use throwaway entries: everything below writes to the real
login keychain (service “iTerm2”, or “iTerm2-Browser” for the browser password manager).

## Password manager window
1. Window > Password Manager with the Keychain selected. Add “test-a” (user “alice”) and “test-b”
   (no user name).
2. Settings menu > Export Passwords…. Expect a Touch ID or password prompt every time, even if the
   password manager was just unlocked.
3. Save the file. Enter mismatched passphrases: expect a re-prompt saying they don’t match. Enter
   an empty one: expect a re-prompt. Then enter a matching one.
4. Delete test-a. Import Passwords… and choose the file. A wrong passphrase re-prompts. With the
   right one, test-a comes back without a conflict prompt for test-b, and the summary shows
   Added 1, Already saved 1.
5. Change the saved passwords of the test entries (add a few more before step 2 so there are
   several), import the same file again, and try each conflict button: Replace, Don’t Replace,
   Always Replace (stops asking), Never Replace (stops asking), Cancel (stops the import and
   reports what was done). An entry whose password you didn’t change is not asked about.
6. Switch to another password manager (e.g. 1Password). Export and Import are disabled.
7. Repeat 1 to 4 from the built-in browser’s password manager. Its file holds only browser entries.

## Finder
8. Double-click the exported file in Finder. Expect authentication, then the passphrase prompt,
   then the summary. An open password manager window reloads.
8a. Set both the terminal and browser password managers to something other than macOS Keychain
   and double-click the file. Expect a message saying to choose macOS Keychain, with no
   authentication or passphrase prompt.
8b. Rename some other file (e.g. a text file) to end in .iterm2passwords and double-click it.
   Expect “This is not an iTerm2 passwords file.” with no authentication or passphrase prompt.

## Export/Import All Settings and Data
9. Settings > General > Export All Settings and Data…. The save panel has an unchecked “Include
   saved passwords” box. Export once without it and once with it (expect authentication and a
   passphrase).
10. With every password manager set to something other than Keychain, the checkbox is absent.
11. Import All with the file that has passwords: before the relaunch, a Touch ID or password
    prompt appears, then a passphrase prompt. Cancelling either skips the passwords and the rest
    of the import continues. Enter a wrong passphrase: the re-prompt still explains that Cancel
    imports everything else. Repeat and enter it.
11a. Export with passwords while the terminal uses macOS Keychain. Switch the terminal to another
    password manager, then Import All from that export. The passwords are imported (not counted
    as “Not imported”), and after the relaunch the terminal uses macOS Keychain and shows them.
12. Erase All Settings and Data > Export First: the save panel has no passwords checkbox.

## No login password
12a. On a Mac (or VM) whose user has no login password, export and import from the password
    manager window and from Finder. There is no system authentication prompt; the passphrase
    prompt appears and both work.

## Phone
13. With a paired iTerm2 Buddy, the passphrase prompts are not offered on the phone. The conflict
    prompt is.

Clean up: delete the test entries and the exported files.
