//
//  iTermBrowserPageSaverTests.swift
//  iTerm2XCTests
//
//  Created by Claude on 6/24/25.
//

import XCTest
import WebKit
@testable import iTerm2SharedARC

@available(macOS 11.0, *)
@MainActor
class iTermBrowserPageSaverTests: XCTestCase {
    private var testHelper: iTermBrowserPageSaverTestHelper!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testHelper = try iTermBrowserPageSaverTestHelper()
    }
    
    override func tearDownWithError() throws {
        testHelper = nil
        try super.tearDownWithError()
    }
    
    // MARK: - Basic Functionality Tests
    
    func testBasicPageSaving() async throws {
        // Load the test page
        try await testHelper.loadTestPage()

        // Save the page and get results
        let (originalHTML, savedHTML, savedFolder) = try await testHelper.savePageAndVerify()

        // Verify the saved page integrity
        try testHelper.verifyPageIntegrity(originalHTML: originalHTML, savedHTML: savedHTML, savedFolder: savedFolder)

        print("✅ Basic page saving test passed")
    }
    
    func testDOCTYPEPreservation() async throws {
        try await testHelper.loadTestPage()
        let (_, savedHTML, _) = try await testHelper.savePageAndVerify()
        
        XCTAssertTrue(savedHTML.hasPrefix("<!DOCTYPE html>"), "DOCTYPE should be preserved")
        print("✅ DOCTYPE preservation test passed")
    }
    
    func testCSSInlining() async throws {
        try await testHelper.loadTestPage()
        let (_, savedHTML, _) = try await testHelper.savePageAndVerify()
        
        // Should have style tags instead of link tags
        XCTAssertTrue(savedHTML.contains("<style>"), "CSS should be inlined as style tags")
        XCTAssertFalse(savedHTML.contains("<link rel=\"stylesheet\""), "CSS link tags should be replaced")
        
        // Should contain actual CSS content
        XCTAssertTrue(savedHTML.contains("font-family: Arial"), "CSS content should be preserved")
        XCTAssertTrue(savedHTML.contains("#333"), "CSS color values should be preserved")
        
        print("✅ CSS inlining test passed")
    }
    
    func testResourceDownloading() async throws {
        try await testHelper.loadTestPage()
        let (_, _, savedFolder) = try await testHelper.savePageAndVerify()
        
        let resourcesFolder = savedFolder.appendingPathComponent("resources")
        let resourceFiles = try FileManager.default.contentsOfDirectory(atPath: resourcesFolder.path)
        
        // Check that resources were downloaded
        XCTAssertTrue(resourceFiles.contains { $0.hasSuffix(".png") }, "PNG images should be saved")
        XCTAssertTrue(resourceFiles.contains { $0.hasSuffix(".js") }, "JavaScript files should be saved")
        
        print("✅ Resource downloading test passed - \(resourceFiles.count) resources saved")
    }
    
    func testLocalResourceReferences() async throws {
        try await testHelper.loadTestPage()
        let (_, savedHTML, _) = try await testHelper.savePageAndVerify()
        
        // Images should reference local resources
        XCTAssertTrue(savedHTML.contains("src=\"resources/"), "Images should reference local resources folder")
        
        // CSS background images should reference local resources
        XCTAssertTrue(savedHTML.contains("url('resources/"), "CSS background images should reference local files")
        
        // Should not contain absolute URLs to the test server
        XCTAssertFalse(savedHTML.contains("http://localhost"), "Should not contain absolute URLs to test server")
        
        print("✅ Local resource references test passed")
    }
    
    func testOriginalPageRemainsIntact() async throws {
        try await testHelper.loadTestPage()
        
        // Get the original functional content before saving
        let originalImageSrc = try await testHelper.getImageSrc()
        let originalTitle = try await testHelper.getPageTitle()
        let originalCSSLinks = try await testHelper.getCSSLinkCount()
        
        // Verify we have the expected original content
        XCTAssertTrue(originalImageSrc.contains("test-image.png"), "Original image src should be present")
        XCTAssertFalse(originalImageSrc.contains("resources/"), "Original should not have local paths")
        XCTAssertEqual(originalTitle, "Test Page", "Original title should be present")
        XCTAssertGreaterThan(originalCSSLinks, 0, "Should have CSS links")
        
        // Save the page
        let (_, savedHTML, _) = try await testHelper.savePageAndVerify()
        
        // Get the functional content after saving
        let imageSrcAfterSaving = try await testHelper.getImageSrc()
        let titleAfterSaving = try await testHelper.getPageTitle()
        let cssLinksAfterSaving = try await testHelper.getCSSLinkCount()
        
        // Verify the functional aspects of the original page are unchanged
        XCTAssertEqual(originalImageSrc, imageSrcAfterSaving, "Original image src should be unchanged after saving")
        XCTAssertEqual(originalTitle, titleAfterSaving, "Original title should be unchanged after saving")
        XCTAssertEqual(originalCSSLinks, cssLinksAfterSaving, "CSS links should remain in original page")
        
        // Verify the saved HTML is different and has local references
        XCTAssertTrue(savedHTML.contains("src=\"resources/"), "Saved HTML should have local resource references")
        XCTAssertTrue(savedHTML.contains("<style>"), "Saved HTML should have inlined CSS")
        XCTAssertFalse(savedHTML.contains("http://localhost"), "Saved HTML should not contain original server URLs")
        
        // Verify data-saved-* attributes were added but don't break the page functionality
        let pageHasDataAttributes = try await testHelper.pageHasDataSavedAttributes()
        XCTAssertTrue(pageHasDataAttributes, "Page should have data-saved-* attributes after saving")
        
        // Verify the image is still visible and functional in the original page
        let imageIsVisible = try await testHelper.isImageVisible()
        XCTAssertTrue(imageIsVisible, "Image should still be visible in original page after saving")
        
        print("✅ Original page remains functionally intact test passed")
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyPage() async throws {
        try await testHelper.createAndLoadMinimalPage()
        let (_, savedHTML, savedFolder) = try await testHelper.savePageAndVerify()
        
        XCTAssertTrue(savedHTML.hasPrefix("<!DOCTYPE html>"), "DOCTYPE should be preserved")
        XCTAssertTrue(savedHTML.contains("<title>Minimal</title>"), "Title should be preserved")
        
        // Should still create resources folder even if empty
        let resourcesFolder = savedFolder.appendingPathComponent("resources")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourcesFolder.path), "Resources folder should exist")
        
        print("✅ Empty page test passed")
    }
    
    func testPageWithNoResources() async throws {
        try await testHelper.createAndLoadTextOnlyPage()
        let (_, savedHTML, savedFolder) = try await testHelper.savePageAndVerify()
        
        XCTAssertTrue(savedHTML.contains("Text Only Page"), "Content should be preserved")
        XCTAssertFalse(savedHTML.contains("src=\"resources/"), "Should not reference any resources")
        
        // Resources folder might be empty but should exist
        let resourcesFolder = savedFolder.appendingPathComponent("resources")
        if FileManager.default.fileExists(atPath: resourcesFolder.path) {
            let resourceFiles = try FileManager.default.contentsOfDirectory(atPath: resourcesFolder.path)
            XCTAssertTrue(resourceFiles.isEmpty, "Resources folder should be empty")
        }
        
        print("✅ No resources test passed")
    }
    
    func testPageWithFailedResources() async throws {
        try await testHelper.createAndLoadPageWithBrokenLinks()
        let (_, savedHTML, savedFolder) = try await testHelper.savePageAndVerify()
        
        // Should handle failed resources gracefully
        XCTAssertTrue(savedHTML.contains("Page with Broken Links"), "Content should be preserved")
        
        // Failed resources should not break the saving process
        let resourcesFolder = savedFolder.appendingPathComponent("resources")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourcesFolder.path), "Resources folder should exist")
        
        print("✅ Failed resources test passed")
    }
    
    // MARK: - Complex Scenarios
    
    func testComplexPageStructure() async throws {
        try await testHelper.createAndLoadComplexPage()
        let (_, savedHTML, savedFolder) = try await testHelper.savePageAndVerify()
        
        // Should preserve complex structure
        XCTAssertTrue(savedHTML.contains("Complex Test Page"), "Title should be preserved")
        XCTAssertTrue(savedHTML.contains("<iframe"), "Iframe should be preserved")
        XCTAssertTrue(savedHTML.contains("<video"), "Video element should be preserved")
        XCTAssertTrue(savedHTML.contains("<audio"), "Audio element should be preserved")
        
        // Resources should be downloaded
        let resourcesFolder = savedFolder.appendingPathComponent("resources")
        let resourceFiles = try FileManager.default.contentsOfDirectory(atPath: resourcesFolder.path)
        XCTAssertFalse(resourceFiles.isEmpty, "Should have downloaded resources")
        
        print("✅ Complex page structure test passed - \(resourceFiles.count) resources")
    }
    
    func testCSSWithMultipleUrlReferences() async throws {
        try await testHelper.createAndLoadPageWithComplexCSS()
        let (_, savedHTML, _) = try await testHelper.savePageAndVerify()
        
        // CSS should be inlined with all URL references rewritten
        XCTAssertTrue(savedHTML.contains("<style>"), "CSS should be inlined")
        XCTAssertTrue(savedHTML.contains("font-family: 'TestFont'"), "Font family should be preserved")
        
        // Multiple background images should be handled
        if savedHTML.contains("background:") {
            XCTAssertTrue(savedHTML.contains("url('resources/"), "Background URLs should be rewritten")
        }
        
        print("✅ Multiple CSS URL references test passed")
    }
    
    func testNestedResourceReferences() async throws {
        try await testHelper.createAndLoadPageWithNestedCSS()
        let (_, savedHTML, savedFolder) = try await testHelper.savePageAndVerify()
        
        // Should handle nested @import statements
        XCTAssertTrue(savedHTML.contains("<style>"), "CSS should be inlined")
        XCTAssertTrue(savedHTML.contains("Nested CSS Test"), "Content should be preserved")
        
        // Check that nested resources were processed
        let resourcesFolder = savedFolder.appendingPathComponent("resources")
        let resourceFiles = try FileManager.default.contentsOfDirectory(atPath: resourcesFolder.path)
        XCTAssertFalse(resourceFiles.isEmpty, "Should have processed nested resources")
        
        print("✅ Nested resource references test passed")
    }
    
    // MARK: - Performance Tests
    
    func testSavePerformance() async throws {
        try await testHelper.loadTestPage()
        
        let startTime = Date()
        let (_, _, _) = try await testHelper.savePageAndVerify()
        let endTime = Date()
        
        let duration = endTime.timeIntervalSince(startTime)
        XCTAssertLessThan(duration, 10.0, "Page saving should complete within 10 seconds")
        
        print("✅ Performance test passed - saved in \(String(format: "%.2f", duration)) seconds")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidSaveLocation() async throws {
        try await testHelper.loadTestPage()

        // Try to save to a location that doesn't exist and can't be created
        let invalidSSHLocation = SSHLocation(path: "/invalid/path/that/cannot/be/created", endpoint: LocalhostEndpoint.instance)

        let baseURL = await testHelper.testWebView.url!
        let pageSaver = iTermBrowserPageSaver(webView: testHelper.testWebView, baseURL: baseURL)

        do {
            try await pageSaver.savePageWithResources(to: invalidSSHLocation)
            XCTFail("Should have thrown an error for invalid save location")
        } catch {
            // Expected to throw an error
            XCTAssertTrue(error is CocoaError || error is PageSaveError, "Should throw appropriate error type")
            print("✅ Invalid save location test passed - correctly threw error")
        }
    }
    
    func testNetworkFailureHandling() async throws {
        // Stop the HTTP server to simulate network failure
        await testHelper.stopServer()

        // Try to load page - this should fail gracefully
        do {
            try await testHelper.loadTestPage()
            XCTFail("Should have failed to load page with server stopped")
        } catch {
            // Expected to fail
            print("✅ Network failure handling test passed - correctly handled server failure")
        }

        // Restart server for cleanup
        await testHelper.startServer()
    }
}
