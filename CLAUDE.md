## Code Best Practices

- Avoid writing javascript, html, or CSS that's more than one line long in Swift. Create a new file and use the existing template mechanism to load it.
- After creating a new file, `git add` it immediately
- In Swift, use it_fatalError and it_assert instead of fatalError and assert, which do not create useful crash logs.
- Don't write more than one line of inline javascript, html, or css. Instead create a new file and load it using iTermBrowserTemplateLoader.swift
- Don't create dependency cycles. Use delegates or closures instead.
- To run unit tests in ModernTests, use tools/run_tests.expect. It takes an argument naming the test or tests, such as `tools/run_tests.expect ModernTests/iTermScriptFunctionCallTest/testSignature`
- When renaming a file tracked by git (and almost all of them are) use `git mv` instead of `mv`
