import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeTranscriptDiscoveryTests {
    // MARK: - Timestamp parsing (RC1)

    @Test
    func parseTimestampAcceptsFractionalSeconds() throws {
        // Claude transcripts emit millisecond precision; the previous bare
        // ISO8601DateFormatter returned nil for these.
        let parsed = try #require(ClaudeTranscriptDiscovery.parseTimestamp("2026-05-29T16:42:19.610Z"))
        #expect(abs(parsed.timeIntervalSince1970 - 1_780_072_939.61) < 0.001)
    }

    @Test
    func parseTimestampAcceptsWholeSeconds() throws {
        let parsed = try #require(ClaudeTranscriptDiscovery.parseTimestamp("2026-05-29T16:42:19Z"))
        #expect(abs(parsed.timeIntervalSince1970 - 1_780_072_939) < 0.001)
    }

    @Test
    func parseTimestampRejectsGarbage() {
        #expect(ClaudeTranscriptDiscovery.parseTimestamp("not-a-date") == nil)
    }

    // MARK: - End-to-end discovery

    /// Proves the regression: the session's `updatedAt` must come from the last
    /// in-content message timestamp, NOT the file's modification date. Before the
    /// fractional-seconds fix, every timestamp parse failed and `updatedAt` fell
    /// back to the file mtime, making the age badge wrong.
    @Test
    func discoveredSessionUsesLastMessageTimestampNotFileModificationDate() throws {
        let lastMessageTimestamp = "2026-05-29T16:42:19.610Z"
        let expected = try #require(ClaudeTranscriptDiscovery.parseTimestamp(lastMessageTimestamp))
        // A file mtime deliberately different from the message time but within
        // the discovery window relative to the `now` we pass below.
        let fileModificationDate = expected.addingTimeInterval(45)
        let now = expected.addingTimeInterval(90)

        let lines = [
            #"{"sessionId":"sess-abc","cwd":"/tmp/island-work","timestamp":"2026-05-29T16:42:10.100Z","type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the failing test"}]}}"#,
            #"{"sessionId":"sess-abc","cwd":"/tmp/island-work","timestamp":"2026-05-29T16:42:19.610Z","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Fixed the off-by-one"}]}}"#,
        ]

        let (root, fileURL) = try makeTranscript(lines: lines, modifiedAt: fileModificationDate)
        defer { try? FileManager.default.removeItem(at: root) }

        let discovery = ClaudeTranscriptDiscovery(rootURL: root)
        let sessions = discovery.discoverRecentSessions(now: now)

        let session = try #require(sessions.first { $0.id == "sess-abc" })
        #expect(session.updatedAt == expected)
        #expect(session.updatedAt != fileURLModificationDate(fileURL))
        #expect(session.claudeMetadata?.lastAssistantMessage == "Fixed the off-by-one")
        #expect(session.summary == "Fixed the off-by-one")
    }

    /// `session(forTranscriptAt:)` powers synthetic-session enrichment: a live
    /// process knows its transcript path but not its contents.
    @Test
    func sessionForTranscriptPathPopulatesMetadataAndTime() throws {
        let lines = [
            #"{"sessionId":"sess-xyz","cwd":"/tmp/island-work","timestamp":"2026-05-29T10:00:00.000Z","type":"user","message":{"role":"user","content":[{"type":"text","text":"Add logging"}]}}"#,
            #"{"sessionId":"sess-xyz","cwd":"/tmp/island-work","timestamp":"2026-05-29T10:05:30.250Z","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Added structured logs"}]}}"#,
        ]
        let (root, fileURL) = try makeTranscript(lines: lines, modifiedAt: .now)
        defer { try? FileManager.default.removeItem(at: root) }

        let discovery = ClaudeTranscriptDiscovery(rootURL: root)
        let session = try #require(discovery.session(forTranscriptAt: fileURL.path))

        #expect(session.id == "sess-xyz")
        #expect(session.claudeMetadata?.lastAssistantMessage == "Added structured logs")
        #expect(session.claudeMetadata?.initialUserPrompt == "Add logging")
        #expect(session.updatedAt == ClaudeTranscriptDiscovery.parseTimestamp("2026-05-29T10:05:30.250Z"))
    }

    // MARK: - Helpers

    private func makeTranscript(lines: [String], modifiedAt: Date) throws -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-transcript-tests-\(UUID().uuidString)", isDirectory: true)
        let projectDir = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let fileURL = projectDir.appendingPathComponent("sess.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: fileURL.path)

        return (root, fileURL)
    }

    private func fileURLModificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
