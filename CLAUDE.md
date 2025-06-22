## Code Best Practices

- Avoid writing javascript, html, or CSS that's more than one line long in Swift. Create a new file and use the existing template mechanism to load it.
- After creating a new file, `git add` it immediately
- In Swift, use it_fatalError and it_assert instead of fatalError and assert, which do not create useful crash logs.

