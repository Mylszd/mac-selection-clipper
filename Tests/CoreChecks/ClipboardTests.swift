import Foundation
import AppKit
import ClipperClipboard

extension CoreTests {
    func testClipboardArchivePreservesAllItemsAndRepresentations() throws {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let first = NSPasteboardItem(), second = NSPasteboardItem()
        first.setString("中文🙂", forType: .string)
        first.setData(Data("{\\rtf1 sample}".utf8), forType: .rtf)
        first.setString("<b>中文🙂</b>", forType: .html)
        first.setData(Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff]), forType: .png)
        second.setString("file:///tmp/clipper-test.txt", forType: .fileURL)
        second.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.custom"))
        pb.writeObjects([first, second])
        let archive = try PasteboardArchive.capture(pb)
        pb.clearContents(); pb.setString("new copy", forType: .string)
        let expected = pb.changeCount
        XCTAssertTrue(archive.restore(pb, expectedChangeCount: expected))
        let items = try XCTUnwrap(pb.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].string(forType: .string), "中文🙂")
        XCTAssertEqual(items[0].data(forType: .rtf), Data("{\\rtf1 sample}".utf8))
        XCTAssertEqual(items[0].string(forType: .html), "<b>中文🙂</b>")
        XCTAssertEqual(items[0].data(forType: .png), Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff]))
        XCTAssertEqual(items[1].string(forType: .fileURL), "file:///tmp/clipper-test.txt")
        XCTAssertEqual(items[1].data(forType: NSPasteboard.PasteboardType("com.example.custom")), Data([1, 2, 3]))
    }
    func testClipboardConflictNeverOverwritesNewerUserCopy() throws {
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        pb.setString("original", forType: .string)
        let archive = try PasteboardArchive.capture(pb)
        pb.clearContents(); pb.setString("synthetic copy", forType: .string)
        let expected = pb.changeCount
        pb.clearContents(); pb.setString("newer user copy", forType: .string)
        XCTAssertFalse(archive.restore(pb, expectedChangeCount: expected))
        XCTAssertEqual(pb.string(forType: .string), "newer user copy")
    }
    func testClipboardEmptyArchiveAndUnsupportedPayloadGuards() throws {
        let pb = NSPasteboard.withUniqueName(); defer { pb.releaseGlobally() }
        pb.clearContents(); let empty = try PasteboardArchive.capture(pb)
        pb.setString("temporary", forType: .string)
        XCTAssertTrue(empty.restore(pb, expectedChangeCount: pb.changeCount))
        XCTAssertTrue(pb.pasteboardItems?.isEmpty ?? true)
        let promised = NSPasteboardItem()
        promised.setData(Data([1]), forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"))
        pb.writeObjects([promised])
        XCTAssertThrowsError(try PasteboardArchive.capture(pb))
        pb.clearContents(); pb.setData(Data(repeating: 42, count: 200), forType: .png)
        XCTAssertThrowsError(try PasteboardArchive.capture(pb, byteLimit: 100))
    }
    func testCopyReceiptRequiresFreshStableClipboardAndExplicitAppConsent() {
        XCTAssertFalse(CopyFallbackPolicy.allows(enabled: false, bundleID: "test", allowedApps: ["test"], secure: false))
        XCTAssertFalse(CopyFallbackPolicy.allows(enabled: true, bundleID: "other", allowedApps: ["test"], secure: false))
        XCTAssertFalse(CopyFallbackPolicy.allows(enabled: true, bundleID: "test", allowedApps: ["test"], secure: true))
        XCTAssertTrue(CopyFallbackPolicy.allows(enabled: true, bundleID: "test", allowedApps: ["test"], secure: false))
        XCTAssertEqual(CopyFallbackPolicy.mode(enabled: true, allApps: true, bundleID: "any.app", allowedApps: ["test"], secure: false), .menuOnly)
        XCTAssertEqual(CopyFallbackPolicy.mode(enabled: true, allApps: true, bundleID: "test", allowedApps: ["test"], secure: false), .menuOrKey)
        XCTAssertEqual(CopyFallbackPolicy.mode(enabled: true, allApps: false, bundleID: "any.app", allowedApps: ["test"], secure: false), CopyFallbackPolicy.Mode.none)
        XCTAssertEqual(CopyFallbackPolicy.mode(enabled: true, allApps: true, bundleID: "com.apple.finder", allowedApps: ["com.apple.finder"], secure: false), CopyFallbackPolicy.Mode.none)
        XCTAssertEqual(CopyFallbackPolicy.mode(enabled: true, allApps: true, bundleID: "test", allowedApps: ["test"], secure: true), CopyFallbackPolicy.Mode.none)
        XCTAssertEqual(CopyFallbackPolicy.mode(enabled: false, allApps: true, bundleID: "test", allowedApps: ["test"], secure: false), CopyFallbackPolicy.Mode.none)
        XCTAssertFalse(CopyFallbackPolicy.hasFreshStableCopy(before: 5, observed: 5, current: 5))
        XCTAssertFalse(CopyFallbackPolicy.hasFreshStableCopy(before: 5, observed: 6, current: 7))
        XCTAssertTrue(CopyFallbackPolicy.hasFreshStableCopy(before: 5, observed: 7, current: 7)) // apps may clear+write (two increments)
        XCTAssertTrue(CopyFallbackPolicy.hasFreshStableCopy(before: 5, observed: 6, current: 6))
    }
}
