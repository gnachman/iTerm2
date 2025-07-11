## Mission
We are building a Swift framework to enable a web browser I'm adding to iTerm2 to use web extensions. There are some documents in the Documentation folder that describe more or less where this is going. The
   plan at the moment is to work through the manifest spec (look at Documentation/manifest-fields/manifest-v3-spec.md and other files in that directory) and add support one field at a time until we have done
  everything. 

## Practices
* Use TDD. Write tests, ensure they fail, then write code, then ensure tests pass.
* Use async/await when appropriate. Avoid completion handlers in favor of async.
* Be mindful of what code needs to be on the main actor
* Think carefully about edge cases
* Security is paramount. The web is a hostile platform and we must be very careful.
* Use dependency injection liberally. Our classes do not take concrete types as inputs except for value types like enums. This makes it easy to write mocks. Protocols and factories everywhere.
* We target AppKit on macOS. Do not use iOS-specific features.
* Use BrowserExtensionLogger for logging, not print.
* Avoid using variables named extension because it will cause compiler errors. Use browserExtension instead.
* After completing a task, ensure tests pass.
* Do not use Task.sleep in tests, even if it would be convenient. There is always a better way. You are FORBIDDEN from using Task.sleep unless you have express written permission.
* Do not use default values in function parameters.
* Assume macOS 14. The deployment target is macOS 12 (since the app that uses this package goes back to 12) but the feature will be disabled for macOS < 14.
* Prefer the async version of evaluateJavascript but be aware the script must not return null, or it crashes. Just add `true` to the end to make it happy.
* Class names generally begin with BrowserExtension.
* I am not infallible. You should push back against me if you think I have made a mistake.
* We are not quitters. We do not give up. We fight until we win. This is core to our identity. We will not be defeated by a computer!
* Avoid downcasting, even conditionally.
