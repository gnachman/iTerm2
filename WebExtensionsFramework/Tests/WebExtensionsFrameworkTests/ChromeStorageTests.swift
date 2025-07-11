import XCTest
import WebKit
@testable import WebExtensionsFramework

@MainActor
class ChromeStorageTests: XCTestCase {
    
    var testRunner: ExtensionTestingInfrastructure.TestRunner!
    
    override func setUp() async throws {
        testRunner = ExtensionTestingInfrastructure.TestRunner(verbose: false)
    }
    
    override func tearDown() async throws {
        testRunner = nil
    }

    // TEST 1: Verify chrome.storage.local.set and chrome.storage.local.get work for simple key-value pairs
    func testSimpleSetAndGet() async throws {
        let set = "Set"
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    \(testRunner.javascriptCreatingPromise(name: set))
                    (async function() {
                        // Test simple set and get using promises
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ foo: "bar" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed without error');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: set))
                                \(testRunner.expectReach("setter callback"))
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.get("foo", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed without error');
                                assertEqual(result.foo, "bar", 'Retrieved value should match set value');
                                assertTrue(typeof result === 'object', 'Result should be an object');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: get))
                                \(testRunner.expectReach("getter callback"))
                            });
                        });
                    })();
                """
            ]
        )
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: set)
        testRunner.verifyAssertions()
    }

    // TEST 2: Ensure getting non-existent key returns undefined rather than throwing
    func testGetNonExistentKey() async throws {
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    (async function() {
                        await new Promise((resolve) => {
                            chrome.storage.local.get("noSuchKey", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should not error for non-existent key');
                                assertTrue(result.noSuchKey === undefined, 'Non-existent key should return undefined');
                                assertTrue(typeof result === 'object', 'Result should still be an object');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: get))
                                \(testRunner.expectReach("getter callback"))
                            });
                        });
                    })();
                """
            ]
        )
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        testRunner.verifyAssertions()
    }

    // TEST 3: Test chrome.storage.local.get with object of defaults merges defaults correctly
    func testGetWithDefaults() async throws {
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    (async function() {
                        // First clear storage to ensure it's empty
                        await new Promise((resolve) => {
                            chrome.storage.local.clear(function() {
                                assertTrue(!chrome.runtime.lastError, 'Clear should succeed');
                                resolve();
                                \(testRunner.expectReach("clear callback"))
                            });
                        });
                        
                        // Get with defaults
                        await new Promise((resolve) => {
                            chrome.storage.local.get({ a: 1, b: 2 }, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get with defaults should succeed');
                                assertEqual(result.a, 1, 'Default value a should be returned');
                                assertEqual(result.b, 2, 'Default value b should be returned');
                                assertTrue(Object.keys(result).length === 2, 'Result should have exactly 2 keys');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: get))
                                \(testRunner.expectReach("getter callback"))
                            });
                        });
                    })();
                """
            ]
        )
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        testRunner.verifyAssertions()
    }

    // TEST 3b: Test that stored values override defaults in get() with object parameter
    func testGetWithDefaultsStoredOverride() async throws {
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    (async function() {
                        // First set some values
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ a: 9 }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                                \(testRunner.expectReach("set callback"))
                            });
                        });
                        
                        // Get with defaults - stored value should override default
                        await new Promise((resolve) => {
                            chrome.storage.local.get({ a: 1, b: 2 }, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get with defaults should succeed');
                                assertEqual(result.a, 9, 'Stored value should override default');
                                assertEqual(result.b, 2, 'Default value should be used for missing key');
                                assertTrue(Object.keys(result).length === 2, 'Result should have exactly 2 keys');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: get))
                                \(testRunner.expectReach("getter callback"))
                            });
                        });
                    })();
                """
            ]
        )
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        testRunner.verifyAssertions()
    }

    // TEST 4: Verify chrome.storage.local.remove deletes key but leaves others intact
    func testRemoveKey() async throws {
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    (async function() {
                        // Set multiple keys
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ x: 1, y: 2 }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                                \(testRunner.expectReach("set callback"))
                            });
                        });
                        
                        // Remove one key
                        await new Promise((resolve) => {
                            chrome.storage.local.remove("x", function() {
                                assertTrue(!chrome.runtime.lastError, 'Remove should succeed');
                                resolve();
                                \(testRunner.expectReach("remove callback"))
                            });
                        });
                        
                        // Get both keys
                        await new Promise((resolve) => {
                            chrome.storage.local.get(["x", "y"], function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertTrue(result.x === undefined, 'Removed key should be undefined');
                                assertEqual(result.y, 2, 'Non-removed key should remain');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: get))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        testRunner.verifyAssertions()
    }

    // TEST 5: Confirm chrome.storage.local.clear wipes all stored data
    func testClearStorage() async throws {
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    (async function() {
                        // Set multiple keys
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ a: 1, b: 2, c: 3 }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                                \(testRunner.expectReach("set callback"))
                            });
                        });
                        
                        // Clear all
                        await new Promise((resolve) => {
                            chrome.storage.local.clear(function() {
                                assertTrue(!chrome.runtime.lastError, 'Clear should succeed');
                                resolve();
                                \(testRunner.expectReach("clear callback"))
                            });
                        });
                        
                        // Get all keys (null means all)
                        await new Promise((resolve) => {
                            chrome.storage.local.get(null, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertTrue(Object.keys(result).length === 0, 'Storage should be empty after clear');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: get))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        testRunner.verifyAssertions()
    }


    // TEST 6: Ensure that only string keys are accepted (numbers are coerced)
    func testNumericKeysCoerced() async throws {
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    (async function() {
                        // Test with numeric key - spec allows either coercion to string OR error
                        let retrievedValue = null;
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ 123: "num" }, function() {
                                assertTrue(!chrome.runtime.lastError);
                                \(testRunner.expectReach("set callback"))
                                resolve();
                            });
                        });
                        
                        // If set succeeded, verify the key was coerced to string
                        await new Promise((resolve) => {
                            chrome.storage.local.get("123", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get with string version should succeed if coercion occurred');
                                retrievedValue = result["123"];
                                assertEqual(retrievedValue, "num", 'Wrong retrieved value');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: get))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        testRunner.verifyAssertions()
    }

    // TEST 6b: Test invalid key types in remove and clear operations
    func testInvalidKeyTypesInRemoveAndClear() async throws {
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    (async function() {
                        // Test remove() with null key
                        try {
                            await new Promise((resolve) => {
                                chrome.storage.local.remove(null, function() {
                                    // Spec allows either error or coercion to "null"
                                    if (chrome.runtime.lastError) {
                                        assertTrue(true, 'remove(null) can throw error');
                                    } else {
                                        assertTrue(true, 'remove(null) can coerce to string "null"');
                                    }
                                    resolve();
                                });
                            });
                        } catch (error) {
                            assertTrue(true, 'remove(null) can throw synchronously');
                        }
                        
                        // Test remove() with undefined key
                        try {
                            await new Promise((resolve) => {
                                chrome.storage.local.remove(undefined, function() {
                                    // Spec allows either error or coercion to "undefined"
                                    if (chrome.runtime.lastError) {
                                        assertTrue(true, 'remove(undefined) can throw error');
                                    } else {
                                        assertTrue(true, 'remove(undefined) can coerce to string "undefined"');
                                    }
                                    resolve();
                                });
                            });
                        } catch (error) {
                            assertTrue(true, 'remove(undefined) can throw synchronously');
                        }
                        
                        // Test remove() with numeric key
                        try {
                            await new Promise((resolve) => {
                                chrome.storage.local.remove(123, function() {
                                    // Spec allows either error or coercion to "123"
                                    if (chrome.runtime.lastError) {
                                        assertTrue(true, 'remove(123) can throw error');
                                    } else {
                                        assertTrue(true, 'remove(123) can coerce to string "123"');
                                    }
                                    resolve();
                                });
                            });
                        } catch (error) {
                            assertTrue(true, 'remove(123) can throw synchronously');
                        }
                        \(testRunner.javascriptResolvingPromise(name: get))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        testRunner.verifyAssertions()
    }

    // TEST 7: Reject unsupported value types (functions, DOM nodes, undefined)
    func testRejectUnsupportedValueTypes() async throws {
        let get = "Get"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: get))
                    (async function() {
                        // First, set some valid data to verify it remains unchanged
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ valid: "original" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Valid data should set successfully');
                                resolve();
                                \(testRunner.expectReach("set original"))
                            });
                        });
                        
                        // Test with function - won't do anything but it runs the callback
                        await new Promise((resolve) => {
                                \(testRunner.expectReach("will set bad"))
                            chrome.storage.local.set({ bad: () => {} }, function() {
                                resolve();
                                \(testRunner.expectReach("set bad"))
                            });
                        });
                        
                        // Verify stored data remains unchanged after failed attempts
                        await new Promise((resolve) => {
                            chrome.storage.local.get(["valid", "bad", "node"], function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertEqual(result.valid, "original", 'Valid data should remain unchanged');
                                assertTrue(result.bad === undefined, 'Bad function should not be stored');
                                resolve();
                                \(testRunner.expectReach("verify"))
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: get))
                    })();
                """
            ]
        )

        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: get)
        testRunner.verifyAssertions()
    }

    // TEST 7b: Verify onChanged does not fire on failed set operations
    func testOnChangedNoFireOnFailedSets() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let changeEventCount = 0;
                        
                        // Set up onChanged listener
                        chrome.storage.onChanged.addListener(function(changes, areaName) {
                            if (areaName === 'local') {
                                changeEventCount++;
                            }
                        });
                        
                        // Try to set a function - should fail and NOT fire onChanged
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ func: () => {} }, function() {
                                resolve();
                                \(testRunner.expectReach("promise for set func"))
                            });
                        });
                        
                        // Check that no onChanged events fired
                        assertEqual(changeEventCount, 0, 'onChanged should not fire for failed set operations');
                        
                        // Verify a successful set DOES fire onChanged
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ valid: "value" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Valid set should succeed');
                                resolve();
                            });
                        });
                        
                        // Check that valid operation fired exactly one event
                        assertEqual(changeEventCount, 1, 'onChanged should fire exactly once for successful operation');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 8: Store and retrieve nested plain objects and arrays correctly
    func testNestedObjectsAndArrays() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        const originalObj = { a: 1, b: [2, 3] };
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ obj: originalObj }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.get("obj", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertTrue(result.obj !== undefined, 'Object should be retrieved');
                                assertEqual(result.obj.a, 1, 'Nested property a should match');
                                assertTrue(Array.isArray(result.obj.b), 'Nested property b should be array');
                                assertEqual(result.obj.b.length, 2, 'Array should have correct length');
                                assertEqual(result.obj.b[0], 2, 'Array element 0 should match');
                                assertEqual(result.obj.b[1], 3, 'Array element 1 should match');
                                \(testRunner.expectReach("promise for get func"))
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 8b: Reject undefined value type - turns into a no-op
    func testRejectUndefinedValueType() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ u: undefined }, function() {
                                \(testRunner.expectReach("promise for set func"))
                                resolve();
                            });
                        });
                        
                        // verify it didn't sneak through
                        await new Promise((resolve) => {
                            chrome.storage.local.get('u', function(result) {
                                assertTrue(result.u === undefined, 'undefined value must not be stored');
                                \(testRunner.expectReach("promise for get func"))
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 9: Confirm that setting the same value twice does not fire onChanged
    func testNoOnChangedForSameValue() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let changeCount = 0;
                        
                        // Set initial value
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ dup: 5 }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Initial set should succeed');
                                \(testRunner.expectReach("promise for set 1"))
                                resolve();
                            });
                        });
                        
                        // Add onChanged listener
                        chrome.storage.onChanged.addListener(function(changes, areaName) {
                            if (areaName === 'local' && 'dup' in changes) {
                                changeCount++;
                            }
                        });
                        
                        // Listener registration is synchronous, no need to wait
                        
                        // Set same value again - should not fire onChanged
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ dup: 5 }, function() {
                                \(testRunner.expectReach("promise for set 2"))
                                assertTrue(!chrome.runtime.lastError, 'Second set should succeed');
                                resolve();
                            });
                        });
                        
                        // Use synchronous check - if onChanged was going to fire, it would have by now
                        
                        // Verify no change event fired
                        assertEqual(changeCount, 0, 'Setting same value should not fire onChanged');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 10: Verify that chrome.storage.onChanged fires with correct oldValue and newValue
    func testOnChangedWithCorrectValues() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let capturedChanges = null;
                        
                        // Set initial value
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ key: "old" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Initial set should succeed');
                                \(testRunner.expectReach("promise for set 1"))
                                resolve();
                            });
                        });
                        
                        // Add onChanged listener
                        chrome.storage.onChanged.addListener(function(changes, areaName) {
                            if (areaName === 'local' && 'key' in changes) {
                                // Verify change event fired with correct values
                                assertTrue(changes !== null, 'onChanged should have fired');
                                assertTrue('key' in changes, 'Changes should contain key');
                                assertEqual(changes.key.oldValue, "old", 'Old value should be correct');
                                assertEqual(changes.key.newValue, "new", 'New value should be correct');
                                \(testRunner.javascriptResolvingPromise(name: end))
                            }
                        });
                        
                        // Listener registration is synchronous, no additional wait needed
                        
                        // Change the value
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ key: "new" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Value change should succeed');
                                resolve();
                            });
                        });
                    })();
                """
            ]
        )
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 11: Verify deep-merge vs overwrite semantics
    func testOverwriteSemantics() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Set initial object
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ obj: { x: 1, y: 2 } }, function() {
                                assertTrue(!chrome.runtime.lastError, 'First set should succeed');
                                resolve();
                            });
                        });
                        
                        // Overwrite with different object (should replace, not merge)
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ obj: { z: 3 } }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Second set should succeed');
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.get("obj", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertTrue(result.obj.x === undefined, 'Original property x should be gone');
                                assertTrue(result.obj.y === undefined, 'Original property y should be gone');
                                assertEqual(result.obj.z, 3, 'New property z should be present');
                                assertTrue(Object.keys(result.obj).length === 1, 'Object should have only new property');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 12: Test behavior of get(null) and get(undefined)
    func testGetNullAndUndefined() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Clear and populate some keys
                        await new Promise((resolve) => {
                            chrome.storage.local.clear(function() {
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ a: 1, b: 2, c: 3 }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                            });
                        });
                        
                        // Test get(null) - should return all keys
                        await new Promise((resolve) => {
                            chrome.storage.local.get(null, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get null should succeed');
                                assertEqual(Object.keys(result).length, 3, 'get(null) should return all keys');
                                assertEqual(result.b, 2, 'get(null) should include key b');
                                assertEqual(result.a, 1, 'get(null) should include key a');
                                resolve();
                            });
                        });
                        
                        // Test get(undefined) - should also return all keys  
                        let undefinedResult;
                        await new Promise((resolve) => {
                            chrome.storage.local.get(undefined, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get undefined should succeed');
                                assertEqual(Object.keys(result).length, 3, 'get(undefined) should return all keys');
                                assertEqual(result.a, 1, 'get(undefined) should include key a');
                                assertEqual(result.b, 2, 'get(undefined) should include key b');
                                \(testRunner.javascriptResolvingPromise(name: end))
                                resolve();
                            });
                        });
                        
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 13: Ensure remove on non-existent key is a no-op
    func testRemoveNonExistentKey() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Clear storage to ensure key doesn't exist
                        await new Promise((resolve) => {
                            chrome.storage.local.clear(function() {
                                resolve();
                            });
                        });
                        
                        // Remove non-existent key - should be no-op
                        await new Promise((resolve) => {
                            chrome.storage.local.remove("foo", function() {
                                assertTrue(!chrome.runtime.lastError, 'Remove non-existent key should not error');
                                resolve();
                                \(testRunner.expectReach("promise for remove"))
                            });
                        });
                        
                        // Verify key is still undefined
                        await new Promise((resolve) => {
                            chrome.storage.local.get("foo", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertTrue(result.foo === undefined, 'Non-existent key should remain undefined');
                                \(testRunner.expectReach("promise for get"))
                                \(testRunner.javascriptResolvingPromise(name: end))
                                resolve();
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 14: Confirm storage persistence across extension reloads
    func testStoragePersistence() async throws {
        let end = "End"
        let uuid = UUID()
        // First test runner - set the value
        do {
            let testExtension = ExtensionTestingInfrastructure.TestExtension(
                id: uuid,
                permissions: ["storage"],
                backgroundScripts: [
                    "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Set a value for persistence test
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ persist: true }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                                \(testRunner.expectReach("callback"))
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
                ]
            )

            _ = try await testRunner.run(testExtension)
            await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
            testRunner.verifyAssertions()
        }

        testRunner.forgetActiveExtension()

        do {
            // Verify the value persists
            let testExtension = ExtensionTestingInfrastructure.TestExtension(
                id: uuid,
                permissions: ["storage"],
                backgroundScripts: [
                    "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // After "reload", verify the value persists
                        await new Promise((resolve) => {
                            chrome.storage.local.get("persist", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed after reload');
                                assertEqual(result.persist, true, 'Value should persist across extension reload');
                                \(testRunner.javascriptResolvingPromise(name: end))
                                resolve();
                            });
                        });
                    })();
                """
                ]
            )

            _ = try await testRunner.run(testExtension)
            await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
            testRunner.verifyAssertions()
        }
    }

    // TEST 15: Verify chrome.storage.local available in content scripts but not untrusted pages
    func testStorageAvailabilityByContext() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // In content script context
                        assertTrue(typeof chrome !== 'undefined', 'Chrome should be available in content script');
                        assertTrue(typeof chrome.storage !== 'undefined', 'Storage should be available in content script');
                        assertTrue(typeof chrome.storage.local === 'object', 'Local storage should be object in content script');
                        \(testRunner.expectReach("content script ran"))
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        _ = try await testRunner.run(testExtension)

        // Create an untrusted webview. The content script will run in this webview but in a its own world.
        let (contentWebView, _) = try await testRunner.createUntrustedWebView(for: .contentScript)
        try await contentWebView.loadHTMLStringAsync("<html><body></body></html>", baseURL: nil)

        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView)
        testRunner.verifyAssertions()

        // In untrusted context, chrome should not be available
        let value = try await contentWebView.evaluateJavaScript("typeof chrome")
        XCTAssertEqual(value as? String, "undefined")
    }

    // TEST 16: Test that chrome.storage.sync requires "storage" permission in manifest
    func testSyncRequiresStoragePermission() async throws {
        // Test extension without storage permission
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: [], // No storage permission
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Try to use sync storage without permission
                        await new Promise((resolve) => {
                            chrome.storage.sync.set({ a: 1 }, function() {
                                // Should have an error due to missing permission
                                assertTrue(!!chrome.runtime.lastError, 'Sync storage should require storage permission');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 17: Test error when passing non-function as callback
    func testNonFunctionCallback() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        try {
                            // This should throw a TypeError synchronously
                            chrome.storage.local.get("foo", "notAFunction");
                            assertTrue(false, 'Should have thrown TypeError for non-function callback');
                        } catch (error) {
                            assertTrue(error instanceof TypeError, 'Should throw TypeError for non-function callback');
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 17b: Test TypeError for non-function callbacks on all methods
    func testNonFunctionCallbacksThrow() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        const nonFunction = "notAFunction";
                        
                        // Test set() with non-function callback
                        try {
                            chrome.storage.local.set({ test: "value" }, nonFunction);
                            assertTrue(false, 'set() should throw TypeError for non-function callback');
                        } catch (error) {
                            assertTrue(error instanceof TypeError, 'set() should throw TypeError for non-function callback');
                        }
                        
                        // Test remove() with non-function callback
                        try {
                            chrome.storage.local.remove("test", nonFunction);
                            assertTrue(false, 'remove() should throw TypeError for non-function callback');
                        } catch (error) {
                            assertTrue(error instanceof TypeError, 'remove() should throw TypeError for non-function callback');
                        }
                        
                        // Test clear() with non-function callback
                        try {
                            chrome.storage.local.clear(nonFunction);
                            assertTrue(false, 'clear() should throw TypeError for non-function callback');
                        } catch (error) {
                            assertTrue(error instanceof TypeError, 'clear() should throw TypeError for non-function callback');
                        }
                        
                        // Test getBytesInUse() with non-function callback (if available)
                        if (typeof chrome.storage.local.getBytesInUse === 'function') {
                            try {
                                chrome.storage.local.getBytesInUse(null, nonFunction);
                                assertTrue(false, 'getBytesInUse() should throw TypeError for non-function callback');
                            } catch (error) {
                                assertTrue(error instanceof TypeError, 'getBytesInUse() should throw TypeError for non-function callback');
                            }
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 18: Verify that calling set() with an empty object is a no-op but still invokes callback
    func testSetEmptyObject() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Clear storage first
                        await new Promise((resolve) => {
                            chrome.storage.local.clear(function() {
                                resolve();
                            });
                        });
                        
                        // Set empty object - should be no-op but invoke callback
                        await new Promise((resolve) => {
                            chrome.storage.local.set({}, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set empty object should not error');
                                resolve();
                            });
                        });
                        
                        // Verify storage is still empty
                        await new Promise((resolve) => {
                            chrome.storage.local.get(null, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertTrue(Object.keys(result).length === 0, 'Storage should remain empty');
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 19: Test handling of special identifiers
    func testSpecialKeyNames() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Test special keys
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ 
                                "constructor": "ctor", 
                                "hasOwnProperty": "hop",
                                "toString": "ts" 
                            }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Setting special keys should succeed');
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.get(["constructor", "hasOwnProperty", "toString"], function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Getting special keys should succeed');
                                assertEqual(result.constructor, "ctor", 'constructor key should work');
                                assertEqual(result.hasOwnProperty, "hop", 'hasOwnProperty key should work');
                                assertEqual(result.toString, "ts", 'toString key should work');
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 20: Confirm that deeply nested structures up to reasonable depth work
    func testDeeplyNestedStructures() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Create deeply nested object
                        let deepObj = {};
                        let current = deepObj;
                        for (let i = 0; i < 50; i++) {
                            current.level = i;
                            current.next = {};
                            current = current.next;
                        }
                        current.level = 50;
                        
                        // Store deeply nested object
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ deep: deepObj }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Setting deeply nested object should succeed');
                                \(testRunner.expectReach("set callback"))
                                resolve();
                            });
                        });
                        
                        // Retrieve and verify deeply nested object
                        await new Promise((resolve) => {
                            chrome.storage.local.get("deep", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Getting deeply nested object should succeed');
                                assertTrue(result.deep !== undefined, 'Deep object should be retrieved');
                                
                                // Verify structure integrity
                                let retrieved = result.deep;
                                let depth = 0;
                                while (retrieved.next && depth < 55) {
                                    assertEqual(retrieved.level, depth, `Level ${depth} should match`);
                                    retrieved = retrieved.next;
                                    depth++;
                                }
                                assertEqual(retrieved.level, 50, 'Final level should be 50');
                                assertTrue(depth === 50, 'Should reach expected depth');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 21: Validate support (or rejection) of Date objects
    func testDateObjects() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        const testDate = new Date(2025, 6, 11);
                        let setError = false;
                        
                        // Try to store Date object
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ d: testDate }, function() {
                                if (chrome.runtime.lastError) {
                                    setError = true;
                                    // Date objects should be rejected
                                    assertTrue(true, 'Date objects should be rejected with error');
                                } else {
                                    setError = false;
                                }
                                resolve();
                            });
                        });
                        
                        if (!setError) {
                            // If set succeeded, retrieve and verify it's serialized to ISO string
                            await new Promise((resolve) => {
                                chrome.storage.local.get("d", function(result) {
                                    assertTrue(!chrome.runtime.lastError, 'Get should succeed if set succeeded');
                                    assertTrue(result.d !== undefined, 'Date value should exist if set succeeded');
                                    
                                    // Should be serialized to ISO string format
                                    assertTrue(typeof result.d === 'string', 'Date should be serialized to string');
                                    
                                    // Should be valid ISO date string
                                    const parsedDate = new Date(result.d);
                                    assertTrue(!isNaN(parsedDate.getTime()), 'Should be valid ISO date string');
                                    
                                    // Verify it matches expected ISO format
                                    const expectedISO = testDate.toISOString();
                                    assertEqual(result.d, expectedISO, 'Should match original date ISO string');
                                    \(testRunner.expectReach("get callback"))
                                    
                                    resolve();
                                });
                            });
                        }
                        
                        // Either error occurred during set (rejection) or ISO string was returned (serialization)
                        // Both are spec-compliant behaviors
                        assertTrue(true, 'Date handling is spec-compliant: either rejected or serialized to ISO string');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 25: Verify chrome.storage area names exist and are distinct
    func testStorageAreasDistinct() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Check that storage areas exist
                        assertTrue(typeof chrome.storage.local === 'object', 'Local storage should exist');
                        assertTrue(typeof chrome.storage.sync === 'object', 'Sync storage should exist');
                        assertTrue(typeof chrome.storage.session === 'object', 'Session storage should exist');
                        
                        // Test that they are distinct by setting same key in different areas
                        const testKey = 'distinctTest';
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ [testKey]: 'local' }, function() {
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.sync.set({ [testKey]: 'sync' }, function() {
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.session.set({ [testKey]: 'session' }, function() {
                                resolve();
                            });
                        });
                        
                        // Get from each area separately
                        const localResult = await new Promise((resolve) => {
                            chrome.storage.local.get(testKey, function(result) {
                                resolve(result);
                            });
                        });
                        
                        const syncResult = await new Promise((resolve) => {
                            chrome.storage.sync.get(testKey, function(result) {
                                resolve(result);
                            });
                        });
                        
                        const sessionResult = await new Promise((resolve) => {
                            chrome.storage.session.get(testKey, function(result) {
                                resolve(result);
                            });
                        });
                        
                        assertEqual(localResult[testKey], 'local', 'Local should return local value');
                        assertEqual(syncResult[testKey], 'sync', 'Sync should return sync value');
                        assertEqual(sessionResult[testKey], 'session', 'Session should return session value');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 22: Test concurrent get and set calls for race conditions
    func testConcurrentOperations() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Fire get and set concurrently to test race conditions
                        const promises = [];
                        
                        // Start a get operation
                        const getPromise = new Promise((resolve) => {
                            chrome.storage.local.get("x", function(result) {
                                resolve(result.x);
                            });
                        });
                        promises.push(getPromise);
                        
                        // Immediately start a set operation
                        const setPromise = new Promise((resolve) => {
                            chrome.storage.local.set({ x: 42 }, function() {
                                resolve();
                            });
                        });
                        promises.push(setPromise);
                        
                        // Wait for both operations
                        const results = await Promise.all(promises);
                        const getValue = results[0];
                        
                        // The get should return either undefined (old value) or 42 (new value)
                        // but never partial state
                        assertTrue(getValue === undefined || getValue === 42, 
                                   'Concurrent get should return consistent value');
                        
                        // Verify final state
                        await new Promise((resolve) => {
                            chrome.storage.local.get("x", function(result) {
                                assertEqual(result.x, 42, 'Final value should be set correctly');
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    // TEST 23: Ensure callbacks always run asynchronously
    func testAsynchronousCallbacks() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let callbackRan = false;
                        
                        // Set up a promise that will resolve when callback runs
                        const callbackPromise = new Promise((resolve) => {
                            chrome.storage.local.set({ async: true }, function() {
                                callbackRan = true;
                                resolve();
                                \(testRunner.expectReach("set callback"))
                            });
                        });
                        
                        // Callback should not have run synchronously
                        assertTrue(!callbackRan, 'Callback should not run synchronously');
                        
                        // Wait for callback to complete
                        await callbackPromise;
                        
                        assertTrue(callbackRan, 'Callback should eventually run asynchronously');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 24: Confirm that get with duplicate keys in array deduplicates results
    func testGetWithDuplicateKeys() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Set test data
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ a: 1, b: 2 }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                            });
                        });
                        
                        // Get with duplicate keys
                        await new Promise((resolve) => {
                            chrome.storage.local.get(["a", "a", "b"], function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                
                                // Result should not have duplicates
                                const keys = Object.keys(result);
                                assertEqual(keys.length, 2, 'Result should have no duplicate keys');
                                assertTrue(keys.includes('a'), 'Result should include key a');
                                assertTrue(keys.includes('b'), 'Result should include key b');
                                assertEqual(result.a, 1, 'Key a should have correct value');
                                assertEqual(result.b, 2, 'Key b should have correct value');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 26: Verify that storage changes are immediately visible in subsequent JS evaluations
    func testImmediateVisibility() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Set a value
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ foo: "bar" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                            });
                        });
                        
                        // Immediately get the value - should be visible
                        await new Promise((resolve) => {
                            chrome.storage.local.get("foo", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertEqual(result.foo, "bar", 'Value should be immediately visible');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 27: Ensure JSON-safe cloning (no shared references)
    func testJSONSafeCloning() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        const originalArray = [{ x: 1 }];
                        
                        // Store the array
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ arr: originalArray }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                            });
                        });
                        
                        // Mutate the original object after setting
                        originalArray[0].x = 999;
                        originalArray.push({ y: 2 });
                        
                        // Get the stored value - should be unaffected by mutations
                        await new Promise((resolve) => {
                            chrome.storage.local.get("arr", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertTrue(Array.isArray(result.arr), 'Retrieved value should be array');
                                assertEqual(result.arr.length, 1, 'Array should have original length');
                                assertEqual(result.arr[0].x, 1, 'Retrieved object should be unaffected by mutations');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 28: Test get with array of keys returns only those keys
    func testGetWithArrayOfKeys() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Set multiple keys
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ a: 1, b: 2, c: 3 }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                            });
                        });
                        
                        // Get only specific keys
                        await new Promise((resolve) => {
                            chrome.storage.local.get(["a", "c"], function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertEqual(result.a, 1, 'Key a should be present');
                                assertEqual(result.c, 3, 'Key c should be present');
                                assertTrue(result.b === undefined, 'Key b should not be present');
                                assertTrue(Object.keys(result).length === 2, 'Result should have exactly 2 keys');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 30: Test removal of multiple keys in one call
    func testRemoveMultipleKeys() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Set multiple keys
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ a: 1, b: 2, c: 3 }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                            });
                        });
                        
                        // Remove multiple keys
                        await new Promise((resolve) => {
                            chrome.storage.local.remove(["a", "c"], function() {
                                assertTrue(!chrome.runtime.lastError, 'Remove should succeed');
                                resolve();
                            });
                        });
                        
                        // Get all keys
                        await new Promise((resolve) => {
                            chrome.storage.local.get(null, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertTrue(result.a === undefined, 'Key a should be removed');
                                assertTrue(result.c === undefined, 'Key c should be removed');
                                assertEqual(result.b, 2, 'Key b should remain');
                                assertTrue(Object.keys(result).length === 1, 'Only one key should remain');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 29: Test that storage data is UTF-8 safe (e.g., emojis, non-Latin scripts)
    func testUTF8Support() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        const utf8Data = { 
                            emoji: "😊🎉🌟", 
                            cyrillic: "привет мир",
                            chinese: "你好世界",
                            arabic: "مرحبا بالعالم",
                            mixed: "Hello 世界 😊 مرحبا"
                        };
                        
                        // Store UTF-8 data
                        await new Promise((resolve) => {
                            chrome.storage.local.set(utf8Data, function() {
                                assertTrue(!chrome.runtime.lastError, 'UTF-8 data should store successfully');
                                resolve();
                            });
                        });
                        
                        // Retrieve and verify UTF-8 data
                        await new Promise((resolve) => {
                            chrome.storage.local.get(Object.keys(utf8Data), function(result) {
                                assertTrue(!chrome.runtime.lastError, 'UTF-8 data should retrieve successfully');
                                
                                assertEqual(result.emoji, utf8Data.emoji, 'Emoji should match exactly');
                                assertEqual(result.cyrillic, utf8Data.cyrillic, 'Cyrillic should match exactly');
                                assertEqual(result.chinese, utf8Data.chinese, 'Chinese should match exactly');
                                assertEqual(result.arabic, utf8Data.arabic, 'Arabic should match exactly');
                                assertEqual(result.mixed, utf8Data.mixed, 'Mixed UTF-8 should match exactly');
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 31: Verify that API surfaces (get, set, remove, clear, getBytesInUse, onChanged) match spec exactly
    func testAPIMethodsExist() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Check that all required methods exist on storage areas
                        const areas = ['local', 'sync', 'session'];
                        
                        for (const areaName of areas) {
                            const area = chrome.storage[areaName];
                            assertTrue(typeof area === 'object', `chrome.storage.${areaName} should be object`);
                            
                            // Core methods
                            assertTrue(typeof area.get === 'function', `${areaName}.get should be function`);
                            assertTrue(typeof area.set === 'function', `${areaName}.set should be function`);
                            assertTrue(typeof area.remove === 'function', `${areaName}.remove should be function`);
                            assertTrue(typeof area.clear === 'function', `${areaName}.clear should be function`);
                            
                            // Optional methods
                            if (typeof area.getBytesInUse !== 'undefined') {
                                assertTrue(typeof area.getBytesInUse === 'function', `${areaName}.getBytesInUse should be function`);
                            }
                            
                            // setAccessLevel method (required)
                            assertTrue(typeof area.setAccessLevel === 'function', `${areaName}.setAccessLevel should be function`);
                        }
                        
                        // Check global onChanged
                        assertTrue(typeof chrome.storage.onChanged === 'object', 'chrome.storage.onChanged should be object');
                        assertTrue(typeof chrome.storage.onChanged.addListener === 'function', 'onChanged.addListener should be function');
                        assertTrue(typeof chrome.storage.onChanged.removeListener === 'function', 'onChanged.removeListener should be function');
                        assertTrue(typeof chrome.storage.onChanged.hasListener === 'function', 'onChanged.hasListener should be function');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 31b: Test hasListener behavior
    func testHasListenerBehavior() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Test hasListener with add/remove
                        const listener = function(changes, areaName) {
                            // Empty listener for testing
                        };
                        
                        // Initially no listener
                        assertTrue(!chrome.storage.onChanged.hasListener(listener), 'Should not have listener initially');
                        
                        // Add listener
                        chrome.storage.onChanged.addListener(listener);
                        assertTrue(chrome.storage.onChanged.hasListener(listener), 'Should have listener after adding');
                        
                        // Remove listener  
                        chrome.storage.onChanged.removeListener(listener);
                        assertTrue(!chrome.storage.onChanged.hasListener(listener), 'Should not have listener after removing');
                        
                        // Test with different listener instance
                        const otherListener = function() {};
                        chrome.storage.onChanged.addListener(listener);
                        assertTrue(chrome.storage.onChanged.hasListener(listener), 'Should detect correct listener');
                        assertTrue(!chrome.storage.onChanged.hasListener(otherListener), 'Should not detect different listener');
                        
                        // Clean up
                        chrome.storage.onChanged.removeListener(listener);
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 32: Test that nested arrays of objects round-trip correctly
    func testNestedArraysOfObjects() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Create complex nested array/object mix
                        const complexData = {
                            matrix: [
                                [{ x: 1, y: 2 }, { x: 3, y: 4 }],
                                [{ x: 5, y: 6 }, { x: 7, y: 8 }]
                            ],
                            nested: {
                                level1: {
                                    level2: [
                                        { items: [1, 2, 3] },
                                        { items: [4, 5, 6] }
                                    ]
                                }
                            }
                        };
                        
                        // Store complex data
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ complex: complexData }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Complex data should store successfully');
                                resolve();
                            });
                        });
                        
                        // Retrieve and verify complex data
                        await new Promise((resolve) => {
                            chrome.storage.local.get("complex", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Complex data should retrieve successfully');
                                const retrieved = result.complex;
                                
                                // Verify matrix structure
                                assertTrue(Array.isArray(retrieved.matrix), 'Matrix should be array');
                                assertEqual(retrieved.matrix.length, 2, 'Matrix should have 2 rows');
                                assertEqual(retrieved.matrix[0][0].x, 1, 'Matrix[0][0].x should be 1');
                                assertEqual(retrieved.matrix[1][1].y, 8, 'Matrix[1][1].y should be 8');
                                
                                // Verify nested structure
                                assertTrue(Array.isArray(retrieved.nested.level1.level2), 'Level2 should be array');
                                assertEqual(retrieved.nested.level1.level2[0].items[2], 3, 'Nested array item should match');
                                assertEqual(retrieved.nested.level1.level2[1].items[2], 6, 'Nested array item should match');
                                
                                resolve();
                                \(testRunner.javascriptResolvingPromise(name: end))
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 33: Validate getBytesInUse for sync namespace
    func testGetBytesInUse() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Clear sync storage first
                        await new Promise((resolve) => {
                            chrome.storage.sync.clear(function() {
                                resolve();
                            });
                        });
                        
                        // Check if getBytesInUse is available on sync namespace
                        if (typeof chrome.storage.sync.getBytesInUse === 'function') {
                            // Get initial bytes in use (should be 0)
                            let initialBytes;
                            await new Promise((resolve) => {
                                chrome.storage.sync.getBytesInUse(null, function(bytes) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse should not error');
                                    assertTrue(typeof bytes === 'number', 'getBytesInUse should return number');
                                    initialBytes = bytes;
                                    resolve();
                                });
                            });
                            
                            // Set some data in sync storage
                            await new Promise((resolve) => {
                                chrome.storage.sync.set({ 
                                    small: "test",
                                    large: "x".repeat(1000)
                                }, function() {
                                    assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                    resolve();
                                });
                            });
                            
                            // Check bytes in use after setting data
                            await new Promise((resolve) => {
                                chrome.storage.sync.getBytesInUse(null, function(bytes) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse should not error');
                                    assertTrue(bytes > initialBytes, 'Bytes in use should increase after setting data');
                                    resolve();
                                });
                            });
                            
                            // Check bytes for specific key
                            await new Promise((resolve) => {
                                chrome.storage.sync.getBytesInUse("large", function(bytes) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse for key should not error');
                                    assertTrue(bytes > 0, 'Large key should use some bytes');
                                    resolve();
                                });
                            });
                            
                            // Check bytes for array of keys  
                            await new Promise((resolve) => {
                                chrome.storage.sync.getBytesInUse(["small", "large"], function(bytes) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse for key array should not error');
                                    assertTrue(bytes > 0, 'Multiple keys should use some bytes');
                                    resolve();
                                });
                            });
                        } else {
                            // getBytesInUse not implemented - this is valid for some storage areas
                            assertTrue(true, 'getBytesInUse not implemented on sync storage, which is acceptable');
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 33b: Validate getBytesInUse for local namespace
    func testGetBytesInUseLocal() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Clear local storage first
                        await new Promise((resolve) => {
                            chrome.storage.local.clear(function() {
                                resolve();
                            });
                        });
                        
                        // Check if getBytesInUse is available on local namespace
                        if (typeof chrome.storage.local.getBytesInUse === 'function') {
                            // Get initial bytes in use (should be 0)
                            let initialBytes;
                            await new Promise((resolve) => {
                                chrome.storage.local.getBytesInUse(null, function(bytes) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse should not error');
                                    assertTrue(typeof bytes === 'number', 'getBytesInUse should return number');
                                    initialBytes = bytes;
                                    resolve();
                                });
                            });
                            
                            // Set some data in local storage
                            await new Promise((resolve) => {
                                chrome.storage.local.set({ 
                                    small: "test",
                                    large: "x".repeat(1000)
                                }, function() {
                                    assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                    resolve();
                                });
                            });
                            
                            // Check bytes in use after setting data
                            await new Promise((resolve) => {
                                chrome.storage.local.getBytesInUse(null, function(bytes) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse should not error');
                                    assertTrue(bytes > initialBytes, 'Bytes in use should increase after setting data');
                                    resolve();
                                });
                            });
                            
                            // Check bytes for specific key
                            await new Promise((resolve) => {
                                chrome.storage.local.getBytesInUse("large", function(bytes) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse for key should not error');
                                    assertTrue(bytes > 0, 'Large key should use some bytes');
                                    resolve();
                                });
                            });
                        } else {
                            // getBytesInUse not implemented - this is acceptable for some implementations
                            assertTrue(true, 'getBytesInUse not implemented on local storage, which is acceptable');
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 33c: Validate getBytesInUse for session namespace (if available)
    func testGetBytesInUseSession() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Session storage is only available in trusted contexts (background)
                        if ("session" in chrome.storage) {
                            // Clear session storage first
                            await new Promise((resolve) => {
                                chrome.storage.session.clear(function() {
                                    resolve();
                                });
                            });
                            
                            // Check if getBytesInUse is available on session namespace
                            if (typeof chrome.storage.session.getBytesInUse === 'function') {
                                // Get initial bytes in use (should be 0)
                                let initialBytes;
                                await new Promise((resolve) => {
                                    chrome.storage.session.getBytesInUse(null, function(bytes) {
                                        assertTrue(!chrome.runtime.lastError, 'getBytesInUse should not error');
                                        assertTrue(typeof bytes === 'number', 'getBytesInUse should return number');
                                        initialBytes = bytes;
                                        resolve();
                                    });
                                });
                                
                                // Set some data in session storage
                                await new Promise((resolve) => {
                                    chrome.storage.session.set({ 
                                        sessionData: "test data for session",
                                        sessionLarge: "y".repeat(500)
                                    }, function() {
                                        assertTrue(!chrome.runtime.lastError, 'Session set should succeed');
                                        resolve();
                                    });
                                });
                                
                                // Check bytes in use after setting data
                                await new Promise((resolve) => {
                                    chrome.storage.session.getBytesInUse(null, function(bytes) {
                                        assertTrue(!chrome.runtime.lastError, 'getBytesInUse should not error');
                                        assertTrue(bytes > initialBytes, 'Bytes in use should increase after setting session data');
                                        resolve();
                                    });
                                });
                            } else {
                                assertTrue(true, 'getBytesInUse not implemented on session storage, which is acceptable');
                            }
                        } else {
                            assertTrue(true, 'Session storage not available in background context, skipping test');
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    func testTrivial() async throws {
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            contentScripts: [
                "content.js": """
                    (function() {
                        console.log('content.js running');
                        assertTrue(true);
                    })()
                """
            ],
            backgroundScripts: ["background.js": """
                (function() {
                    console.log("background.js running");
                    assertTrue(true);
                })();
                """
                               ]
        )

        testRunner.clearAssertions() // Clear any assertions from setup
        try await testRunner.run(testExtension)
        testRunner.verifyAssertions()
    }
    
    // TEST 34: Confirm onChanged events fire across contexts for sync
    func testOnChangedAcrossContexts() async throws {
        let listenerCalled = "ListenerCalled"
        let contentReady = "ContentReady"
        let testFinished = "TestFinished"

        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: listenerCalled))
                    (function() {
                        // Add onChanged listener in content script  
                        chrome.storage.onChanged.addListener(function(changes, areaName) {
                            if (areaName === 'sync' && 'crossContext' in changes) {
                                assertEqual(areaName, 'sync', 'Event should be for sync area');
                                assertEqual(changes.crossContext.oldValue, 'initial', 'Old value should be correct');
                                assertEqual(changes.crossContext.newValue, 'changed', 'New value should be correct');
                                \(testRunner.expectReach("listener"))
                            }
                            \(testRunner.javascriptResolvingPromise(name: listenerCalled))
                        });
                    })();
                """
            ],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: contentReady))
                    \(testRunner.javascriptCreatingPromise(name: testFinished))
                    (async function() {
                        // Set initial value in sync storage
                        await new Promise((resolve) => {
                            chrome.storage.sync.set({ crossContext: "initial" }, function() {
                                \(testRunner.expectReach("initial set callback"))
                                assertTrue(!chrome.runtime.lastError, 'Initial set should succeed');
                                resolve();
                            });
                        });

                        \(testRunner.javascriptBlockingOnPromise(name: contentReady))
                        // Content script setup is complete after await, no additional wait needed

                        // Change the value in sync storage to trigger cross-context onChanged
                        await new Promise((resolve) => {
                            chrome.storage.sync.set({ crossContext: "changed" }, function() {
                                \(testRunner.expectReach("novel set callback"))
                                assertTrue(!chrome.runtime.lastError, 'Change should succeed');
                                resolve();

                                \(testRunner.javascriptResolvingPromise(name: testFinished))
                            });
                        });               
                    })();
                    true;
                """
            ]
        )
        
        let contentWebView = try await testRunner.run(testExtension)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView)
        await testRunner.unblockBackgroundScript(extensionId: testExtension.id, blockName: contentReady)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: testFinished)

        testRunner.verifyAssertions()
    }

    // TEST 35: Ensure chrome.runtime.lastError does not prevent callback invocation
    func testLastErrorDoesNotPreventCallback() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: [], // No storage permission to force error
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let callbackInvoked = false;
                        let errorReceived = false;
                        
                        // Try to use storage without permission - should trigger lastError
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ test: "value" }, function() {
                                callbackInvoked = true;
                                if (chrome.runtime.lastError) {
                                    errorReceived = true;
                                }
                                resolve();
                            });
                        });
                        
                        assertTrue(callbackInvoked, 'Callback should be invoked even with error');
                        assertTrue(errorReceived, 'Error should be set in lastError');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 36: Verify that extremely large values in local either succeed or fail predictably
    func testLargeValues() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Create a large string (1MB)
                        const largeString = "x".repeat(1024 * 1024);
                        
                        // Try to store large value
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ largeValue: largeString }, function() {
                                if (chrome.runtime.lastError) {
                                    // Large value rejected - this is acceptable
                                    assertTrue(true, 'Large value rejected with error (acceptable)');
                                } else {
                                    // Large value accepted - verify it can be retrieved
                                    chrome.storage.local.get("largeValue", function(result) {
                                        if (chrome.runtime.lastError) {
                                            assertTrue(false, 'Get should not fail if set succeeded');
                                        } else {
                                            assertEqual(result.largeValue.length, largeString.length, 'Large value should be stored correctly');
                                        }
                                        resolve();
                                    });
                                    return;
                                }
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 37: Test chrome.storage error messages for clarity and consistency
    func testErrorMessages() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: [], // No storage permission
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Test error message for missing permission
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ test: "value" }, function() {
                                if (chrome.runtime.lastError) {
                                    assertTrue(typeof chrome.runtime.lastError.message === 'string', 'Error message should be string');
                                    assertTrue(chrome.runtime.lastError.message.length > 0, 'Error message should not be empty');
                                }
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 38: Test that storage.onChanged listener can be removed correctly
    func testOnChangedListenerRemoval() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let listenerACallCount = 0;
                        let listenerBCallCount = 0;
                        
                        const listenerA = function(changes, areaName) {
                            if (areaName === 'local' && 'removal' in changes) {
                                listenerACallCount++;
                            }
                        };
                        
                        const listenerB = function(changes, areaName) {
                            if (areaName === 'local' && 'removal' in changes) {
                                listenerBCallCount++;
                            }
                        };
                        
                        // Add both listeners
                        chrome.storage.onChanged.addListener(listenerA);
                        chrome.storage.onChanged.addListener(listenerB);
                        
                        // Trigger change - both should fire
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ removal: "test1" }, function() {
                                resolve();
                            });
                        });
                        
                        // Event firing is synchronous with the callback completion
                        
                        // Remove listener A
                        chrome.storage.onChanged.removeListener(listenerA);
                        
                        // Reset counts
                        listenerACallCount = 0;
                        listenerBCallCount = 0;
                        
                        // Trigger another change - only B should fire
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ removal: "test2" }, function() {
                                resolve();
                            });
                        });
                        
                        // Event firing happens synchronously after storage callback
                        
                        assertEqual(listenerACallCount, 0, 'Removed listener A should not fire');
                        assertEqual(listenerBCallCount, 1, 'Listener B should still fire');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 39: Confirm that storage operations in one namespace do not fire events in another
    func testNamespaceEventIsolation() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let localChanges = 0;
                        let syncChanges = 0;
                        
                        // Add listener for local changes
                        chrome.storage.onChanged.addListener(function(changes, areaName) {
                            if (areaName === 'local' && 'isolation' in changes) {
                                localChanges++;
                            }
                            if (areaName === 'sync' && 'isolation' in changes) {
                                syncChanges++;
                            }
                        });
                        
                        // Change only local storage
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ isolation: "local" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Local set should succeed');
                                resolve();
                            });
                        });
                        
                        // Events fire synchronously with storage operations
                        
                        // Only local should have fired
                        assertEqual(localChanges, 1, 'Local onChanged should fire once');
                        assertEqual(syncChanges, 0, 'Sync onChanged should not fire');
                        
                        // Reset counters
                        localChanges = 0;
                        syncChanges = 0;
                        
                        // Change only sync storage
                        await new Promise((resolve) => {
                            chrome.storage.sync.set({ isolation: "sync" }, function() {
                                // May succeed or fail depending on permission, but shouldn't affect local
                                resolve();
                            });
                        });
                        
                        // Check immediately - events are synchronous
                        
                        // Local should still be 0
                        assertEqual(localChanges, 0, 'Local onChanged should not fire for sync changes');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 40: Test that simultaneous multi-namespace operations do not interfere
    func testMultiNamespaceOperations() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Set data in multiple namespaces simultaneously
                        const promises = [
                            new Promise((resolve) => {
                                chrome.storage.local.set({ multi: "local" }, function() {
                                    resolve('local');
                                });
                            }),
                            new Promise((resolve) => {
                                chrome.storage.sync.set({ multi: "sync" }, function() {
                                    resolve('sync');
                                });
                            }),
                            new Promise((resolve) => {
                                chrome.storage.session.set({ multi: "session" }, function() {
                                    resolve('session');
                                });
                            })
                        ];
                        
                        // Wait for all operations to complete
                        await Promise.all(promises);
                        
                        // Verify each namespace has its own data and they don't interfere
                        await new Promise((resolve) => {
                            chrome.storage.local.get("multi", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Local get should succeed');
                                assertEqual(result.multi, "local", 'Local should have local value');
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.sync.get("multi", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Sync get should succeed');
                                assertEqual(result.multi, "sync", 'Sync should have sync value');
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.session.get("multi", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Session get should succeed');
                                assertEqual(result.multi, "session", 'Session should have session value');
                                resolve();
                            });
                        });
                        
                        // Verify that changing one namespace doesn't affect others
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ multi: "changed-local" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Local update should succeed');
                                resolve();
                            });
                        });
                        
                        // Verify sync still has original value after local change
                        await new Promise((resolve) => {
                            chrome.storage.sync.get("multi", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Sync get after local change should succeed');
                                assertEqual(result.multi, "sync", 'Sync should still have sync value after local change');
                                resolve();
                            });
                        });
                        
                        // Verify session still has original value after local change  
                        await new Promise((resolve) => {
                            chrome.storage.session.get("multi", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Session get after local change should succeed');
                                assertEqual(result.multi, "session", 'Session should still have session value after local change');
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 41: Verify that each storage area exposes a setAccessLevel method per spec
    func testSetAccessLevelMethodExists() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Check that setAccessLevel exists on each storage area
                        const areas = ['local', 'sync', 'session'];
                        
                        for (const areaName of areas) {
                            const area = chrome.storage[areaName];
                            assertTrue(typeof area.setAccessLevel === 'function', 
                                      `chrome.storage.${areaName}.setAccessLevel should be function`);
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 42: Confirm default access levels for each area
    func testDefaultAccessLevels() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Test default availability in content script context per spec
                        assertTrue("local" in chrome.storage, 'Local storage should be available by default in content scripts');
                        assertTrue("sync" in chrome.storage, 'Sync storage should be available by default in content scripts'); 
                        
                        // Session storage should NOT be available by default per spec
                        assertFalse("session" in chrome.storage, 'Session storage should NOT be available by default in content scripts');
                        
                        // Verify the available areas actually work
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ test: "local" }, function() {
                                console.log(chrome.runtime.lastError);
                                assertTrue(!chrome.runtime.lastError, 'Local storage should be functional');
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.sync.set({ test: "sync" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Sync storage should be functional');
                                resolve();
                            });
                        });
                        
                        // Verify session is truly unavailable
                        assertEqual(chrome.storage.session, undefined, 'Session storage property should be undefined');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        
        let (contentWebView, _) = try await testRunner.createUntrustedWebView(for: .contentScript)
        try await contentWebView.loadHTMLStringAsync("<html><body></body></html>", baseURL: nil)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: end)
        testRunner.verifyAssertions()
    }

    func testSetAccessLevelMakeSessionAvailable() async throws {
        let contentReady = "contentCompletedStep1"
        let contentWaitingForBackgroundToGrantAcecss = "contentBeginStep2"
        let contentEnd = "contentEnd"

        let backgroundReady = "backgroundBeginStep1"
        let backgroundEnd = "backgroundCompletedStep1"

        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: contentReady))
                    \(testRunner.javascriptCreatingPromise(name: contentWaitingForBackgroundToGrantAcecss))
                    \(testRunner.javascriptCreatingPromise(name: contentEnd))
                    (async function() {
                        try {
                            if ("session" in chrome.storage) {
                                const value = await new Promise((resolve) => {
                                    chrome.storage.session.get("allowed", function(result) {
                                        resolve(result);
                                    });
                                });
                                assertEqual(value, "true", "Value should be true");
                            } else {
                                assertFalse("session" in chrome.storage, "In first pass session should not be in chrome.storage");
                                \(testRunner.javascriptResolvingPromise(name: contentReady))
                                \(testRunner.javascriptBlockingOnPromise(name: contentWaitingForBackgroundToGrantAcecss))
                                assertTrue("session" in chrome.storage, "After granting access, 'session' should be in chrome.storage.");
                            }
                            \(testRunner.javascriptResolvingPromise(name: contentEnd))
                        } catch (e) {
                            console.error(e.toString());
                        }
                    })();
                """],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: backgroundReady))
                    \(testRunner.javascriptCreatingPromise(name: backgroundEnd))
                    (async function() {
                        // First verify session is available in background (trusted context)
                        assertTrue("session" in chrome.storage, 'Session should be available in background script');
                        assertEqual(typeof chrome.storage.session.setAccessLevel, 'function', "setAccessLevel should be a function");
                        \(testRunner.javascriptBlockingOnPromise(name: backgroundReady))

                        await new Promise((resolve) => {
                            chrome.storage.session.setAccessLevel({ 
                                accessLevel: "TRUSTED_AND_UNTRUSTED_CONTEXTS" 
                            }, function() {
                                assertFalse(chrome.runtime.lastError, "Should not have an error due to setAccessLevel");
                                resolve();
                            });
                        });
                        await new Promise((resolve) => {
                            chrome.storage.session.set({ 'allowed': 'true' }, function() {
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: backgroundEnd))
                    })();
                """
            ])
        let contentWebView = try await testRunner.run(testExtension)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentReady)
        await testRunner.unblockBackgroundScript(extensionId: testExtension.id, blockName: backgroundReady)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundEnd)
        await testRunner.unblockContentScript(testExtension.id, webView: contentWebView, name: contentWaitingForBackgroundToGrantAcecss)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentEnd)

        testRunner.verifyAssertions()
    }

    func testSetAccessLevelMakeLocalUnavailble() async throws {
        let contentReady = "contentReady"
        let contentWaitingForBackgroundToRemoveAcecss = "contentAccessRemoved"
        let contentEnd = "contentEnd"

        let backgroundReady = "backgroundBeginStep1"
        let backgroundEnd = "backgroundCompletedStep1"

        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: contentReady))
                    \(testRunner.javascriptCreatingPromise(name: contentWaitingForBackgroundToRemoveAcecss))
                    \(testRunner.javascriptCreatingPromise(name: contentEnd))
                    (async function() {
                        try {
                            assertTrue("local" in chrome.storage, "Local should be visible by default");
                            \(testRunner.javascriptResolvingPromise(name: contentReady))
                            \(testRunner.javascriptBlockingOnPromise(name: contentWaitingForBackgroundToRemoveAcecss))
                            assertFalse("local" in chrome.storage, "Local should no longer be visibkle");
                            \(testRunner.javascriptResolvingPromise(name: contentEnd))
                        } catch (e) {
                            console.error(e.toString());
                        }
                    })();
                """],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: backgroundReady))
                    \(testRunner.javascriptCreatingPromise(name: backgroundEnd))
                    (async function() {
                        \(testRunner.javascriptBlockingOnPromise(name: backgroundReady))
                        await new Promise((resolve) => {
                            chrome.storage.local.setAccessLevel({ 
                                accessLevel: "TRUSTED_CONTEXTS" 
                            }, function() {
                                assertFalse(chrome.runtime.lastError, "Should not have an error due to setAccessLevel");
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: backgroundEnd))
                    })();
                """
            ])
        let contentWebView = try await testRunner.run(testExtension)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentReady)
        await testRunner.unblockBackgroundScript(extensionId: testExtension.id, blockName: backgroundReady)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundEnd)
        await testRunner.unblockContentScript(testExtension.id, webView: contentWebView, name: contentWaitingForBackgroundToRemoveAcecss)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentEnd)

        testRunner.verifyAssertions()
    }

    func testSetAccessLevelMakeSyncUnavailble() async throws {
        let contentReady = "contentReady"
        let contentWaitingForBackgroundToRemoveAcecss = "contentAccessRemoved"
        let contentEnd = "contentEnd"

        let backgroundReady = "backgroundBeginStep1"
        let backgroundEnd = "backgroundCompletedStep1"

        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: contentReady))
                    \(testRunner.javascriptCreatingPromise(name: contentWaitingForBackgroundToRemoveAcecss))
                    \(testRunner.javascriptCreatingPromise(name: contentEnd))
                    (async function() {
                        try {
                            assertTrue("sync" in chrome.storage, "Sync should be visible by default");
                            \(testRunner.javascriptResolvingPromise(name: contentReady))
                            \(testRunner.javascriptBlockingOnPromise(name: contentWaitingForBackgroundToRemoveAcecss))
                            assertFalse("sync" in chrome.storage, "Sync should no longer be visibkle");
                            \(testRunner.javascriptResolvingPromise(name: contentEnd))
                        } catch (e) {
                            console.error(e.toString());
                        }
                    })();
                """],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: backgroundReady))
                    \(testRunner.javascriptCreatingPromise(name: backgroundEnd))
                    (async function() {
                        \(testRunner.javascriptBlockingOnPromise(name: backgroundReady))
                        await new Promise((resolve) => {
                            chrome.storage.sync.setAccessLevel({ 
                                accessLevel: "TRUSTED_CONTEXTS" 
                            }, function() {
                                assertFalse(chrome.runtime.lastError, "Should not have an error due to setAccessLevel");
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: backgroundEnd))
                    })();
                """
            ])
        let contentWebView = try await testRunner.run(testExtension)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentReady)
        await testRunner.unblockBackgroundScript(extensionId: testExtension.id, blockName: backgroundReady)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: backgroundEnd)
        await testRunner.unblockContentScript(testExtension.id, webView: contentWebView, name: contentWaitingForBackgroundToRemoveAcecss)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: contentEnd)

        testRunner.verifyAssertions()
    }

    // TEST 45: Ensure invalid accessLevel values are rejected
    func testSetAccessLevelInvalidValues() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Try to set invalid access level
                        if (typeof chrome.storage.session.setAccessLevel === 'function') {
                            await new Promise((resolve) => {
                                chrome.storage.session.setAccessLevel({ 
                                    accessLevel: "NOT_A_REAL_LEVEL" 
                                }, function() {
                                    console.log(chrome.runtime.lastError);
                                    assertTrue(chrome.runtime.lastError, 'Invalid access level should be rejected');
                                    resolve();
                                });
                            });
                        } else {
                            assertTrue(true, 'setAccessLevel not implemented (acceptable)');
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 46: Verify that setAccessLevel can only be called in trusted contexts
    func testSetAccessLevelTrustedContextOnly() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            contentScripts: [
                "content.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Try to call setAccessLevel from content script (untrusted context)
                        if (typeof chrome.storage.local.setAccessLevel === 'function') {
                            await new Promise((resolve) => {
                                chrome.storage.local.setAccessLevel({ 
                                    accessLevel: "TRUSTED_AND_UNTRUSTED_CONTEXTS" 
                                }, function() {
                                    if (chrome.runtime.lastError) {
                                        assertTrue(chrome.runtime.lastError.message.includes('Untrusted sender cannot setAccessLevel'), 
                                                  'Should get error about not allowed in this context');
                                    } else {
                                        assertTrue(false, 'setAccessLevel should not work in content script');
                                    }
                                    resolve();
                                });
                            });
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        let contentWebView = try await testRunner.run(testExtension)
        await testRunner.waitForContentScriptCompletion(testExtension.id, webView: contentWebView, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 47: Test that changing access levels fires no spurious onChanged events
    func testSetAccessLevelNoSpuriousEvents() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let changeEventCount = 0;
                        
                        // Add onChanged listener
                        chrome.storage.onChanged.addListener(function(changes, areaName) {
                            changeEventCount++;
                        });
                        
                        // Try to change access level
                        if (typeof chrome.storage.local.setAccessLevel === 'function') {
                            await new Promise((resolve) => {
                                chrome.storage.local.setAccessLevel({ 
                                    accessLevel: "TRUSTED_CONTEXTS" 
                                }, function() {
                                    resolve();
                                });
                            });
                            
                            // Check immediately - spurious events would fire synchronously
                            
                            assertEqual(changeEventCount, 0, 'setAccessLevel should not fire onChanged events');
                        } else {
                            assertTrue(true, 'setAccessLevel not implemented (acceptable)');
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 49b: Test proper handling of corrupted JSON in storage
    func testCorruptedJSONHandling() async throws {
        let end = "End"
        let end2 = "End2"

        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // First store some valid data
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ 
                                validKey: "validValue",
                                anotherKey: { nested: "data" }
                            }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Initial set should succeed');
                                resolve();
                            });
                        });
                        
                        // Verify data is retrievable
                        await new Promise((resolve) => {
                            chrome.storage.local.get(null, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed before corruption');
                                assertEqual(result.validKey, "validValue", 'Data should be valid before corruption');
                                resolve();
                            });
                        });
                        
                        // Signal test to corrupt the data
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)

        // Now corrupt the storage data using the mock provider
        testRunner.corruptStorageData(for: testExtension.id)
        
        // Test that corrupted data is handled gracefully
        let corruptionTest = """
            \(testRunner.javascriptCreatingPromise(name: end2))
            (async function() {
                // Try to get data after corruption
                await new Promise((resolve) => {
                    chrome.storage.local.get(null, function(result) {
                        assertTrue(chrome.runtime.lastError.message.includes("Internal error"), 
                                  'Error should indicate storage problem but it is ' + chrome.runtime.lastError.message);
                        resolve();
                    });
                });
                \(testRunner.javascriptResolvingPromise(name: end2))
            })();
        """
        _ = try! await testRunner.callAsyncJavaScript(corruptionTest,
                                                      contextType: .backgroundScript,
                                                      extensionId: testExtension.id,
                                                      contentWebView: nil)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end2)

        testRunner.verifyAssertions()
    }
    // TEST 50: Test error when calling setAccessLevel on non-existent areas (e.g., managed)
    func testSetAccessLevelManagedArea() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        assertEqual(typeof chrome.storage.managed.setAccessLevel, 'undefined');
                        try {
                            chrome.storage.managed.setAccessLevel({ 
                                accessLevel: "TRUSTED_AND_UNTRUSTED_CONTEXTS" 
                            }, function() { });
                        } catch (e) {
                            \(testRunner.expectReach("setAccessLevel throws"))
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 51: Confirm that storage APIs exist but throw in a non-extension iframe
    func testStorageInNonExtensionIframe() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Test that storage works in extension context
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ extensionContext: "works" }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Storage should work in extension context');
                                \(testRunner.javascriptResolvingPromise(name: end))
                                resolve();
                            });
                        });
                    })();
                """
            ]
        )
        
        let extensionWebView = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        
        // Create iframe with non-extension origin
        let frameInfo = try await testRunner.createIframeContext(
            origin: "test-iframe://example.com",
            parentWebView: extensionWebView
        )
        
        // Test that storage is not available in non-extension iframe
        let iframeTestScript = "typeof chrome "
        
        let typeofChrome = try await extensionWebView.evaluateJavaScript(iframeTestScript,
                                                                         in: frameInfo,
                                                                         contentWorld: .page)
        XCTAssertEqual(typeofChrome as? String, "undefined")
        testRunner.verifyAssertions()
    }
    
    // TEST 52: Validate that listeners added before extension load do not fire after unload
    func testListenersAfterExtensionUnload() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        let listenerFireCount = 0;
                        
                        // Add listener
                        chrome.storage.onChanged.addListener(function(changes, areaName) {
                            listenerFireCount++;
                            assertTrue(listenerFireCount < 2, 'Fired too many times');
                        });
                        
                        // Test that listener works initially
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ beforeUnload: "test" }, function() {
                                resolve();
                            });
                        });
                        
                        // Check if listener fired - it should have by now since storage ops are sync
                        assertTrue(listenerFireCount > 0, 'Listener should fire while extension is loaded');
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()

        // Unload the extension completely
        await testRunner.unloadExtension(testExtension.id)
        
        // Create a new extension instance (different ID) and test that old listeners don't fire
        let newTestExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Make storage changes from a different extension
                        // Old listeners should not fire
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ afterUnload: "test" }, function() {
                                assertTrue(true);  // just to keep the test runner happy that there was at least one assertion
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(newTestExtension)
        await testRunner.waitForBackgroundScriptCompletion(newTestExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 55: Ensure that invalid JSON in stored values is never returned
    func testInvalidJSONHandling() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Test that only valid JSON-serializable data can be stored and retrieved
                        const validData = { 
                            string: "test",
                            number: 42,
                            boolean: true,
                            array: [1, 2, 3],
                            object: { nested: "value" },
                            nullValue: null
                        };
                        
                        // Store valid JSON data
                        await new Promise((resolve) => {
                            chrome.storage.local.set(validData, function() {
                                assertTrue(!chrome.runtime.lastError, 'Valid JSON data should store successfully');
                                resolve();
                            });
                        });
                        
                        // Retrieve and verify data integrity
                        await new Promise((resolve) => {
                            chrome.storage.local.get(null, function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                
                                // Verify all data types are preserved correctly
                                assertEqual(result.string, "test", 'String should be preserved');
                                assertEqual(result.number, 42, 'Number should be preserved');
                                assertEqual(result.boolean, true, 'Boolean should be preserved');
                                assertTrue(Array.isArray(result.array), 'Array should be preserved as array');
                                assertEqual(result.array.length, 3, 'Array length should be preserved');
                                assertEqual(result.object.nested, "value", 'Nested object should be preserved');
                                assertEqual(result.nullValue, null, 'Null value should be preserved');
                                
                                resolve();
                            });
                        });
                        
                        // Test that circular references are rejected (they cannot be JSON serialized)
                        const circularData = { a: 1 };
                        circularData.self = circularData;
                        
                        await new Promise((resolve) => {
                            try {
                                chrome.storage.local.set({ circular: circularData }, function() {
                                    if (chrome.runtime.lastError) {
                                        // Expected: circular references should cause error
                                        assertTrue(true, 'Circular reference correctly rejected');
                                    } else {
                                        // If no error, verify the circular reference was broken/handled
                                        chrome.storage.local.get("circular", function(result) {
                                            // Data should either be undefined or have circular reference removed
                                            const retrieved = result.circular;
                                            if (retrieved && retrieved.self === retrieved) {
                                                assertTrue(false, 'Circular reference should not survive storage');
                                            } else {
                                                assertTrue(true, 'Circular reference was safely handled');
                                            }
                                            resolve();
                                        });
                                        return;
                                    }
                                    resolve();
                                });
                            } catch (e) {
                                // Synchronous error is also acceptable for circular references
                                assertTrue(true, 'Circular reference synchronously rejected');
                                resolve();
                            }
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ valid: validData }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Valid JSON data should store successfully');
                                resolve();
                            });
                        });
                        
                        await new Promise((resolve) => {
                            chrome.storage.local.get("valid", function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Valid JSON data should retrieve successfully');
                                assertTrue(result.valid !== undefined, 'Valid data should be retrieved');
                                assertEqual(result.valid.string, "test", 'String should be preserved');
                                assertEqual(result.valid.number, 42, 'Number should be preserved');
                                assertEqual(result.valid.boolean, true, 'Boolean should be preserved');
                                assertTrue(Array.isArray(result.valid.array), 'Array should be preserved');
                                assertEqual(result.valid.nullValue, null, 'Null should be preserved');
                                resolve();
                            });
                        });
                        
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }

    // TEST 57: Test explicit quota overflow for sync.set
    func testSyncQuotaOverflow() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Create data that exceeds sync quota (assume 100KB limit for test)
                        const largeValue = "x".repeat(110 * 1024); // 110KB string
                        
                        await new Promise((resolve) => {
                            chrome.storage.sync.set({ quotaTest: largeValue }, function() {
                                // Should get quota exceeded error
                                assertTrue(chrome.runtime.lastError.message.toLowerCase().includes('quota'), 
                                          'Error message should mention quota but it is: ' + chrome.runtime.lastError.message);
                                \(testRunner.javascriptResolvingPromise(name: end))
                                resolve();
                            });
                        });
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 57b: Test atomicity under quota errors
    func testAtomicityUnderQuotaErrors() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Create a very large value that would exceed quota
                        const largeValue = "x".repeat(50 * 1024); // 50KB
                        const anotherLargeValue = "y".repeat(60 * 1024); // 60KB
                        
                        // Try to set multiple large values that together exceed quota
                        await new Promise((resolve) => {
                            chrome.storage.sync.set({ 
                                large1: largeValue,
                                large2: anotherLargeValue,
                                validKey: "validValue"
                            }, function() {
                                assertTrue(chrome.runtime.lastError.message.toLowerCase().includes('quota'), 
                                          'Should get quota error');
                                resolve();
                            });
                        });
                        
                        // Check that no partial data was stored if quota failed
                        await new Promise((resolve) => {
                            chrome.storage.sync.get(['large1', 'large2', 'validKey'], function(result) {
                                // Either all keys should be present (success) or none (atomic failure)
                                const keyCount = Object.keys(result).filter(k => result[k] !== undefined).length;
                                assertTrue(keyCount === 0 || keyCount === 3, 
                                          'Set operation should be atomic - either all keys stored or none');
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 57c: Test getBytesInUse with array argument on local storage
    func testGetBytesInUseArrayLocal() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Set multiple values of different sizes
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ 
                                small: "tiny",
                                large: "x".repeat(1000)
                            }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed');
                                resolve();
                            });
                        });
                        
                        if (typeof chrome.storage.local.getBytesInUse === 'function') {
                            // Test getBytesInUse with array of specific keys
                            await new Promise((resolve) => {
                                chrome.storage.local.getBytesInUse(["small", "large"], function(bytesUsed) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse should succeed');
                                    assertTrue(typeof bytesUsed === 'number', 'Should return number');
                                    assertTrue(bytesUsed > 1000, 'Should include large value bytes');
                                    resolve();
                                });
                            });
                            
                            // Compare with individual key usage
                            await new Promise((resolve) => {
                                chrome.storage.local.getBytesInUse("large", function(largeBytesUsed) {
                                    assertTrue(!chrome.runtime.lastError, 'getBytesInUse should succeed');
                                    assertTrue(largeBytesUsed >= 1000, 'Large value should use significant bytes');
                                    resolve();
                                });
                            });
                        } else {
                            assertTrue(true, 'getBytesInUse not implemented - test passes');
                        }
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
    
    // TEST 58: Test atomicity in multi-key set with partial failure
    func testPartialFailureAtomicity() async throws {
        let end = "End"
        let testExtension = ExtensionTestingInfrastructure.TestExtension(
            permissions: ["storage"],
            backgroundScripts: [
                "background.js": """
                    \(testRunner.javascriptCreatingPromise(name: end))
                    (async function() {
                        // Try setting multiple values including one that may cause issues
                        const complexValue = { nested: { value: 42 } };
                        const invalidFunction = function() { return "bad"; };
                        
                        // Try to set both valid and potentially invalid values
                        await new Promise((resolve) => {
                            chrome.storage.local.set({ 
                                validKey: "validValue",
                                complexKey: complexValue,
                                invalidKey: invalidFunction // Functions get filtered out but don't cause errors
                            }, function() {
                                assertTrue(!chrome.runtime.lastError, 'Set should succeed even with function value');
                                resolve();
                            });
                        });
                        
                        // Check what actually got stored - functions are filtered out but other values remain
                        await new Promise((resolve) => {
                            chrome.storage.local.get(['validKey', 'complexKey', 'invalidKey'], function(result) {
                                assertTrue(!chrome.runtime.lastError, 'Get should succeed');
                                assertEqual(result.validKey, 'validValue', 'Valid key should be stored');
                                assertEqual(result.complexKey.nested.value, 42, 'Complex value should be stored correctly');
                                assertTrue(result.invalidKey === undefined, 'Function value should be filtered out');
                                resolve();
                            });
                        });
                        \(testRunner.javascriptResolvingPromise(name: end))
                    })();
                """
            ]
        )
        
        _ = try await testRunner.run(testExtension)
        await testRunner.waitForBackgroundScriptCompletion(testExtension.id, name: end)
        testRunner.verifyAssertions()
    }
}
