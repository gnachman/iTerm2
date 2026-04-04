import Foundation
import ObjectiveC.runtime
import XCTest
@testable import iTerm2SharedARC

private final class HookedUserDefaults: UserDefaults {
  private var storage = [String: Any]()
  private var objectForKeyCounts = [String: Int]()

  var postSetHook: (() -> Void)?

  init() {
    super.init(suiteName: UUID().uuidString)!
  }

  override func object(forKey defaultName: String) -> Any? {
    objectForKeyCounts[defaultName, default: 0] += 1
    return storage[defaultName]
  }

  override func set(_ value: Any?, forKey defaultName: String) {
    if let value {
      storage[defaultName] = value
    } else {
      storage.removeValue(forKey: defaultName)
    }
    postSetHook?()
    NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: self)
  }

  override func removeObject(forKey defaultName: String) {
    storage.removeValue(forKey: defaultName)
    NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: self)
  }

  func setRawObject(_ object: Any?, forKey key: String) {
    if let object {
      storage[key] = object
    } else {
      storage.removeValue(forKey: key)
    }
  }

  func simulateExternalChange(_ object: Any?, forKey key: String) {
    setRawObject(object, forKey: key)
    NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: self)
  }

  func readCount(for key: String) -> Int {
    objectForKeyCounts[key, default: 0]
  }

  func resetReadCount(for key: String) {
    objectForKeyCounts[key] = 0
  }
}

final class ITermPreferencesCacheRegressionTests: XCTestCase {
  private func setUserDefaultsOverrideForTesting(_ defaults: UserDefaults?) {
    let selector = NSSelectorFromString("setUserDefaultsOverrideForTesting:")
    guard let method = class_getClassMethod(iTermPreferences.self, selector) else {
      XCTFail("Missing testing hook \(selector)")
      return
    }
    typealias Function = @convention(c) (AnyClass, Selector, UserDefaults?) -> Void
    let implementation = method_getImplementation(method)
    unsafeBitCast(implementation, to: Function.self)(iTermPreferences.self, selector, defaults)
  }

  private func resetPreferenceCacheForTesting() {
    let selector = NSSelectorFromString("resetPreferenceCacheForTesting")
    guard let method = class_getClassMethod(iTermPreferences.self, selector) else {
      XCTFail("Missing testing hook \(selector)")
      return
    }
    typealias Function = @convention(c) (AnyClass, Selector) -> Void
    let implementation = method_getImplementation(method)
    unsafeBitCast(implementation, to: Function.self)(iTermPreferences.self, selector)
  }

  private func notifyPreferencesUserDefaultsDidChange(_ defaults: UserDefaults) {
    let selector = NSSelectorFromString("preferencesUserDefaultsDidChange:")
    guard let method = class_getClassMethod(iTermPreferences.self, selector) else {
      XCTFail("Missing testing hook \(selector)")
      return
    }
    typealias Function = @convention(c) (AnyClass, Selector, Notification) -> Void
    let implementation = method_getImplementation(method)
    let notification = Notification(name: UserDefaults.didChangeNotification, object: defaults)
    unsafeBitCast(implementation, to: Function.self)(iTermPreferences.self, selector, notification)
  }

  override func tearDown() {
    setUserDefaultsOverrideForTesting(nil)
    resetPreferenceCacheForTesting()
    super.tearDown()
  }

  func testReentrantReadDuringWriteSeesNewValue() {
    let defaults = HookedUserDefaults()
    setUserDefaultsOverrideForTesting(defaults)
    resetPreferenceCacheForTesting()

    defaults.simulateExternalChange(5, forKey: kPreferenceKeyTopBottomMargins)
    XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)), 5)

    var reentrantRead = Int.min
    defaults.postSetHook = {
      reentrantRead = Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins))
    }

    iTermPreferences.setInt(10, forKey: kPreferenceKeyTopBottomMargins)

    XCTAssertEqual(
      reentrantRead,
      10,
      "Readers that run during an in-process write must see the new value"
    )
    XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)), 10)
  }

  func testUnrelatedWriteOnSameDefaultsObjectDoesNotEvictCachedPreference() {
    let defaults = HookedUserDefaults()
    setUserDefaultsOverrideForTesting(defaults)
    resetPreferenceCacheForTesting()

    defaults.setRawObject(5, forKey: kPreferenceKeyTopBottomMargins)
    notifyPreferencesUserDefaultsDidChange(defaults)
    XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)), 5)

    defaults.setRawObject(["example": "value"], forKey: "NoSyncRecordedVariables")
    notifyPreferencesUserDefaultsDidChange(defaults)
    defaults.resetReadCount(for: kPreferenceKeyTopBottomMargins)

    XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)), 5)
    XCTAssertEqual(
      defaults.readCount(for: kPreferenceKeyTopBottomMargins),
      0,
      "An unrelated defaults write must not evict cached preferences"
    )
  }

  func testSequentialNotificationOnlyExternalChangesExposeLatestValue() {
    let defaults = HookedUserDefaults()
    setUserDefaultsOverrideForTesting(defaults)
    resetPreferenceCacheForTesting()

    defaults.setRawObject(5, forKey: kPreferenceKeyTopBottomMargins)
    notifyPreferencesUserDefaultsDidChange(defaults)
    XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)), 5)

    defaults.setRawObject(6, forKey: kPreferenceKeyTopBottomMargins)
    notifyPreferencesUserDefaultsDidChange(defaults)
    XCTAssertEqual(Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)), 6)

    defaults.setRawObject(7, forKey: kPreferenceKeyTopBottomMargins)
    notifyPreferencesUserDefaultsDidChange(defaults)
    XCTAssertEqual(
      Int(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins)),
      7,
      "Rapid notification-only changes must expose the latest value immediately"
    )
  }
}
