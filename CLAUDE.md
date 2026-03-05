## Code Best Practices

- Avoid writing javascript, html, or CSS that's more than one line long in Swift. Create a new file and use the existing template mechanism to load it.
- After creating a new file, `git add` it immediately
- To add a file to the Xcode project, use `tools/add_file_to_xcodeproj.rb <file_path> <target_name>` (e.g., `tools/add_file_to_xcodeproj.rb sources/Example.swift iTerm2SharedARC`)
- In Swift, use it_fatalError and it_assert instead of fatalError and assert, which do not create useful crash logs. In ObjC, assert is ok although ITAssertWithMessage is preferable.
- Don't write more than one line of inline javascript, html, or css. Instead create a new file and load it using iTermBrowserTemplateLoader.swift
- Don't create dependency cycles. Use delegates or closures instead.
- To run unit tests in ModernTests, use tools/run_tests.expect. It takes an argument naming the test or tests, such as `tools/run_tests.expect ModernTests/iTermScriptFunctionCallTest/testSignature`
- When renaming a file tracked by git (and almost all of them are) use `git mv` instead of `mv`
- To make a debug build run `make Development`
- Little scripts or text files that are used for manual testing of features go in tests/
- The deployment target for iTerm2 is macOS 12. You don't need to perform availability checks for older versions.
- Don't replace curly quotes with straight quotes. Same for apostrophes and single quotes.
- In user-visible strings do not use " except as a shorthand for inch. Prefer curly quotes like “ and ”. I know this goes against your nature, but fight hard here.
