import Foundation
import ClipperCore

final class CoreTests {
    func testLatestWinsAndPauseDiscardsPendingCapture() {
        var state = SelectionState()
        let old = state.beginCapture(), new = state.beginCapture()
        state.accept(record("old"), sequence: old)
        XCTAssertNil(state.preview)
        state.accept(record("new"), sequence: new)
        XCTAssertEqual(state.preview?.text, "new")
        let pending = state.beginCapture()
        state.setPaused(true)
        state.accept(record("late"), sequence: pending)
        XCTAssertEqual(state.preview?.text, "new")
    }
    func testEmptyRetainsPreviewAndSaveAcknowledgesOnlyFrozenID() {
        var state = SelectionState()
        state.accept(record("first"), sequence: state.beginCapture())
        let frozen = state.preview!
        state.accept(record("   \n"), sequence: state.beginCapture())
        XCTAssertEqual(state.preview?.id, frozen.id)
        state.accept(record("second"), sequence: state.beginCapture())
        state.markSaved(frozen.id)
        XCTAssertFalse(state.isSaved)
        state.markSaved(state.preview!.id)
        XCTAssertTrue(state.isSaved)
    }
    func testRoundTripEscapingUnicodeAndIdempotentSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MarkdownFileStore(root: root)
        let clip = ClipRecord(sourceApp: "Chrome: \"test\"\n你好", sourceBundleID: "com.test", sourceTitle: "a\\b", text: "中文 👨‍👩‍👧‍👦\n# Heading\n---\n```\n\n")
        let url = try store.save(clip)
        try XCTAssertEqual(try store.save(clip), url)
        let restored = try XCTUnwrap(store.load().records.first)
        XCTAssertEqual(restored.id, clip.id)
        XCTAssertEqual(restored.text, clip.text)
        XCTAssertEqual(restored.sourceApp, clip.sourceApp)
        XCTAssertEqual(restored.sourceTitle, clip.sourceTitle)
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970, clip.createdAt.timeIntervalSince1970, accuracy: 0.001)
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("source_app: \"Chrome: \\\"test\\\"\\n你好\""))
        XCTAssertTrue(raw.hasSuffix(clip.text))
    }
    func testWriteFailureThrowsAndDoesNotProduceRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("block directory".utf8).write(to: root)
        XCTAssertThrowsError(try MarkdownFileStore(root: root).save(record("keep for retry")))
    }
    func testLongTextAndDistinctUUIDsDoNotCollide() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MarkdownFileStore(root: root)
        let a = record(String(repeating: "你好🙂\n", count: 25000)), b = record("b")
        try XCTAssertNotEqual(try store.save(a), try store.save(b))
        try XCTAssertEqual(try store.load().records.count, 2)
        try XCTAssertTrue(try store.load().records.contains { $0.id == a.id && $0.text == a.text })
    }
    func testPrivacyExcludesOwnIgnoredAndSecureContexts() {
        XCTAssertFalse(CapturePolicy.allows(bundleID: "self", ownBundleID: "self", ignored: [], secure: false))
        XCTAssertFalse(CapturePolicy.allows(bundleID: "secret", ownBundleID: "self", ignored: ["secret"], secure: false))
        XCTAssertFalse(CapturePolicy.allows(bundleID: "chrome", ownBundleID: "self", ignored: [], secure: true))
        XCTAssertTrue(CapturePolicy.allows(bundleID: "chrome", ownBundleID: "self", ignored: [], secure: false))
    }
    private func record(_ text: String) -> ClipRecord { ClipRecord(sourceApp: "Test", sourceBundleID: "com.test", text: text) }
}

extension CoreTests {
    func testClearInvalidatesPendingAndResumeDoesNotResurrectOldResult() {
        var state = SelectionState()
        let pending = state.beginCapture()
        state.clear()
        state.accept(record("must not return"), sequence: pending)
        XCTAssertNil(state.preview)
        let old = state.beginCapture()
        state.setPaused(true); state.setPaused(false)
        state.accept(record("stale before pause"), sequence: old)
        XCTAssertNil(state.preview)
        state.accept(record("fresh"), sequence: state.beginCapture())
        XCTAssertEqual(state.preview?.text, "fresh")
    }
    func testCorruptFileIsReportedWithoutHidingValidRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MarkdownFileStore(root: root)
        _ = try store.save(record("valid"))
        try Data("---\nid: invalid\n---\n\nbroken".utf8).write(to: root.appendingPathComponent("broken.md"))
        let result = try store.load()
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.text, "valid")
        XCTAssertEqual(result.unreadableFiles, 1)
    }
    func testConflictingContentCannotOverwriteSavedFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MarkdownFileStore(root: root), a = record("original")
        let b = ClipRecord(id: a.id, createdAt: a.createdAt, capturedAt: a.capturedAt, sourceApp: a.sourceApp, sourceBundleID: a.sourceBundleID, text: "changed")
        try store.save(a)
        XCTAssertThrowsError(try store.save(b))
        try XCTAssertEqual(try store.load().records.first?.text, "original")
    }
    func testNullMetadataAndTextBoundariesArePreserved() throws {
        for body in ["\nleading\n\ntrailing\n", "---\nkey: value\n", "🙂中文\u{2028}line", "<script>alert(1)</script>"] {
            let original = record(body)
            let parsed = try MarkdownFileStore.parse(MarkdownFileStore.markdown(original))
            XCTAssertEqual(parsed.text, body)
            XCTAssertNil(parsed.sourceURL)
            XCTAssertNil(parsed.sourceTitle)
        }
    }
}

extension CoreTests {
    func testExplicitManualPasteWorksWhileAutomaticCaptureIsPaused() {
        var state = SelectionState(); state.setPaused(true)
        state.setManualPreview(record("manual"))
        XCTAssertEqual(state.preview?.text, "manual")
        XCTAssertTrue(state.paused)
        state.accept(record("automatic"), sequence: state.beginCapture())
        XCTAssertEqual(state.preview?.text, "manual")
    }
}

extension CoreTests {
    func testFailedFrozenSaveSurvivesNewSelectionAndCanRetry() {
        let a = record("A"), b = record("B")
        var state = SelectionState(), ledger = SaveLedger()
        state.setManualPreview(a)
        XCTAssertTrue(ledger.begin(a)); XCTAssertFalse(ledger.begin(a))
        state.setManualPreview(b)
        ledger.finish(a.id, succeeded: false)
        XCTAssertEqual(ledger.failed[a.id]?.text, "A")
        XCTAssertEqual(state.preview?.text, "B")
        XCTAssertTrue(ledger.pending.isEmpty)
        XCTAssertTrue(ledger.begin(a)); ledger.finish(a.id, succeeded: true)
        XCTAssertTrue(ledger.failed.isEmpty)
    }
    func testHistoryKeepsPhysicalURLsAfterRenameAndDuplicateMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MarkdownFileStore(root: root), clip = record("renamed")
        let original = try store.save(clip), renamed = root.appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: original, to: renamed)
        let copied = root.appendingPathComponent("copied.md")
        try FileManager.default.copyItem(at: renamed, to: copied)
        let history = try store.load()
        XCTAssertEqual(Set(history.entries.map { $0.url.resolvingSymlinksInPath() }), Set([renamed.resolvingSymlinksInPath(), copied.resolvingSymlinksInPath()]))
        XCTAssertEqual(history.records.count, 2)
    }
    func testMouseGestureAcceptsActivationDragAndRejectsOrdinaryClick() {
        var gesture = MouseSelectionGesture()
        gesture.down(x: 10, y: 10); gesture.move()
        XCTAssertTrue(gesture.finish(x: 100, y: 10, clicks: 1, shift: false))
        gesture.down(x: 10, y: 10)
        XCTAssertFalse(gesture.finish(x: 10, y: 10, clicks: 1, shift: false))
        gesture.down(x: 10, y: 10)
        XCTAssertTrue(gesture.finish(x: 10, y: 10, clicks: 2, shift: false))
        gesture.down(x: 10, y: 10); gesture.clear()
        XCTAssertFalse(gesture.finish(x: 100, y: 10, clicks: 1, shift: false))
    }
}

extension CoreTests {
    func testDuplicatePreviewAndManualPasteDoNotSuppressLaterAutomaticSelection() {
        var state = SelectionState()
        let a = record("A")
        state.accept(a, sequence: state.beginCapture())
        state.accept(record("A"), sequence: state.beginCapture())
        XCTAssertEqual(state.preview?.id, a.id)
        state.markSaved(a.id)
        state.accept(record("A"), sequence: state.beginCapture())
        XCTAssertFalse(state.isSaved)
        XCTAssertNotEqual(state.preview?.id, a.id)
        state.setManualPreview(record("B"))
        state.accept(record("A"), sequence: state.beginCapture())
        XCTAssertEqual(state.preview?.text, "A")
    }
}

extension CoreTests {
    func testPublicAXUTF16RangesPreserveUnicodeAndRejectInvalidBounds() {
        XCTAssertEqual(SelectionTextRange.extract(from: "A🙂中文B", ranges: [NSRange(location: 1, length: 4)]), "🙂中文")
        XCTAssertEqual(SelectionTextRange.extract(from: "first / second", ranges: [NSRange(location: 0, length: 5), NSRange(location: 8, length: 6)]), "first\nsecond")
        XCTAssertNil(SelectionTextRange.extract(from: "abc", ranges: [NSRange(location: 9, length: 1)]))
        XCTAssertNil(SelectionTextRange.extract(from: "abc", ranges: [NSRange(location: 1, length: Int.max)]))
        XCTAssertNil(SelectionTextRange.extract(from: "🙂", ranges: [NSRange(location: 1, length: 1)]))
        XCTAssertNil(SelectionTextRange.extract(from: "abc", ranges: [NSRange(location: 1, length: 0)]))
    }
}

extension CoreTests {
    func testInboxEntryQuotesBodyAndCarriesSource() {
        let clip = ClipRecord(capturedAt: Date(timeIntervalSince1970: 0), sourceApp: "Google Chrome", sourceBundleID: "com.google.Chrome", sourceTitle: "标题\n两行", sourceURL: "https://example.com/a", text: "# 不是标题\n\n---\n中文 👋")
        let entry = InboxFileStore.entry(for: clip, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(entry.contains("### 1970-01-01 00:00 · Google Chrome"))
        XCTAssertTrue(entry.contains("> 来源：Google Chrome — 标题 两行 · <https://example.com/a>"))
        XCTAssertTrue(entry.contains("> # 不是标题\n>\n> ---\n> 中文 👋"))
        XCTAssertTrue(entry.contains(InboxFileStore.marker(clip.id)))
        XCTAssertFalse(entry.contains("\n# 不是标题"))
    }
    func testInboxAppendCreatesHeaderKeepsUserEditsAndIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = InboxFileStore(fileURL: dir.appendingPathComponent("Inbox/划词摘录.md"))
        let a = record("第一条"), b = record("第二条")
        try store.append(a)
        var text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix(InboxFileStore.header))
        // User organizes: deletes everything after the header and adds a note without trailing newline.
        try (InboxFileStore.header + "我的整理笔记").write(to: store.fileURL, atomically: true, encoding: .utf8)
        try store.append(b); try store.append(b)
        text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("我的整理笔记\n"))
        XCTAssertFalse(text.contains("> 第一条"))
        XCTAssertEqual(text.components(separatedBy: InboxFileStore.marker(b.id)).count, 2)
    }
}
