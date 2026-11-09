import Foundation
var failures = 0
func check(_ condition: Bool, _ message: String, file: StaticString, line: UInt) {
    if !condition { failures += 1; print("FAIL \(file):\(line): \(message)") }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows { check(try value(), "expected true", file: file, line: line) }
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { check(!value(), "expected false", file: file, line: line) }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { check(value == nil, "expected nil", file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) rethrows { let lhs = try a(), rhs = try b(); check(lhs == rhs, "\(lhs) != \(rhs)", file: file, line: line) }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { check(abs(a-b) <= accuracy, "dates differ", file: file, line: line) }
func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) rethrows { check(try a() != b(), "expected different values", file: file, line: line) }
func XCTUnwrap<T>(_ a: T?) throws -> T { guard let a else { throw NSError(domain: "Test unwrap", code: 1) }; return a }
func XCTAssertThrowsError<T>(_ a: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try a(); check(false, "expected thrown error", file: file, line: line) } catch {} }
let tests = CoreTests()
let cases: [(String, () throws -> Void)] = [
    ("latest wins; paused results discarded", tests.testLatestWinsAndPauseDiscardsPendingCapture),
    ("empty retains; frozen save identity", tests.testEmptyRetainsPreviewAndSaveAcknowledgesOnlyFrozenID),
    ("Markdown Unicode/YAML roundtrip; idempotency", tests.testRoundTripEscapingUnicodeAndIdempotentSave),
    ("real disk failure throws", tests.testWriteFailureThrowsAndDoesNotProduceRecord),
    ("long content; unique paths", tests.testLongTextAndDistinctUUIDsDoNotCollide),
    ("privacy policy", tests.testPrivacyExcludesOwnIgnoredAndSecureContexts),
    ("clear and resume invalidate old results", tests.testClearInvalidatesPendingAndResumeDoesNotResurrectOldResult),
    ("corrupt files are reported", tests.testCorruptFileIsReportedWithoutHidingValidRecord),
    ("saved content never overwritten", tests.testConflictingContentCannotOverwriteSavedFile),
    ("null metadata and body boundaries", tests.testNullMetadataAndTextBoundariesArePreserved),
    ("explicit paste while paused", tests.testExplicitManualPasteWorksWhileAutomaticCaptureIsPaused),
    ("failed save retained across new preview and retry", tests.testFailedFrozenSaveSurvivesNewSelectionAndCanRetry),
    ("history preserves physical paths", tests.testHistoryKeepsPhysicalURLsAfterRenameAndDuplicateMetadata),
    ("mouse gesture activation drag and click rejection", tests.testMouseGestureAcceptsActivationDragAndRejectsOrdinaryClick),
    ("duplicate and manual-to-auto transition", tests.testDuplicatePreviewAndManualPasteDoNotSuppressLaterAutomaticSelection),
    ("clipboard all-item multi-type fidelity", tests.testClipboardArchivePreservesAllItemsAndRepresentations),
    ("clipboard concurrent copy protected", tests.testClipboardConflictNeverOverwritesNewerUserCopy),
    ("clipboard empty and unsafe archives", tests.testClipboardEmptyArchiveAndUnsupportedPayloadGuards),
    ("copy fallback explicit scope and fresh receipt", tests.testCopyReceiptRequiresFreshStableClipboardAndExplicitAppConsent),
    ("public AX UTF16 range integrity", tests.testPublicAXUTF16RangesPreserveUnicodeAndRejectInvalidBounds),
    ("inbox entry quotes body and carries source", tests.testInboxEntryQuotesBodyAndCarriesSource),
    ("inbox append header, user edits, idempotent", tests.testInboxAppendCreatesHeaderKeepsUserEditsAndIsIdempotent)
]
for (name, run) in cases {
    let before = failures
    do { try run() } catch { failures += 1; print("FAIL \(name): \(error)") }
    if failures == before { print("PASS \(name)") }
}
print("\(cases.count) cases, \(failures) failures")
exit(failures == 0 ? 0 : 1)
