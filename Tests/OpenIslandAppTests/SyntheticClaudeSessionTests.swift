import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct SyntheticClaudeSessionTests {
    /// A live Claude process with no tracked/transcript-discovered session
    /// produces a synthetic row. It must be enriched from the open transcript
    /// (real summary, metadata, and last-activity time) rather than a
    /// contentless "detected from …" placeholder pinned to `now`
    /// (symptoms A/B/D).
    @Test
    func syntheticSessionIsEnrichedFromTranscript() throws {
        let lastTimestamp = "2026-05-29T12:00:30.500Z"
        let (root, fileURL) = try makeTranscript(
            cwd: "/tmp/island-work",
            lines: [
                #"{"sessionId":"sess-1","cwd":"/tmp/island-work","timestamp":"2026-05-29T12:00:00.000Z","type":"user","message":{"role":"user","content":[{"type":"text","text":"Ship the feature"}]}}"#,
                "{\"sessionId\":\"sess-1\",\"cwd\":\"/tmp/island-work\",\"timestamp\":\"\(lastTimestamp)\",\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Shipped and verified\"}]}}",
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = ProcessMonitoringCoordinator()
        coordinator.syntheticClaudeSessionPrefix = "synthetic-"

        let process = ActiveAgentProcessDiscovery.ProcessSnapshot(
            tool: .claudeCode,
            sessionID: nil,
            workingDirectory: "/tmp/island-work",
            terminalTTY: "/dev/ttys010",
            terminalApp: "ghostty",
            transcriptPath: fileURL.path
        )

        let farFutureNow = Date(timeIntervalSince1970: 2_000_000_000)
        let merged = coordinator.mergedWithSyntheticClaudeSessions(
            existingSessions: [],
            activeProcesses: [process],
            now: farFutureNow
        )

        let expectedDate = try #require(
            ClaudeTranscriptDiscovery().session(forTranscriptAt: fileURL.path)?.updatedAt
        )

        let synthetic = try #require(merged.first { coordinator.isSyntheticClaudeSession($0) })
        #expect(synthetic.summary == "Shipped and verified")
        #expect(synthetic.claudeMetadata?.lastAssistantMessage == "Shipped and verified")
        #expect(synthetic.claudeMetadata?.initialUserPrompt == "Ship the feature")
        #expect(synthetic.updatedAt == expectedDate)
        #expect(synthetic.updatedAt != farFutureNow)
        #expect(synthetic.isProcessAlive)
    }

    /// Re-running reconciliation must reuse the existing synthetic session
    /// instead of rebuilding it with `updatedAt = now` every cycle — that churn
    /// was why the age badge appeared to count from app launch.
    @Test
    func syntheticSessionTimeIsStableAcrossReconcileCycles() throws {
        let (root, fileURL) = try makeTranscript(
            cwd: "/tmp/island-work",
            lines: [
                #"{"sessionId":"sess-2","cwd":"/tmp/island-work","timestamp":"2026-05-29T08:00:00.000Z","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Initial answer"}]}}"#,
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        // Pin the transcript's mtime so the cheap per-cycle refresh is a no-op.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_780_000_000)],
            ofItemAtPath: fileURL.path
        )

        let coordinator = ProcessMonitoringCoordinator()
        coordinator.syntheticClaudeSessionPrefix = "synthetic-"

        let process = ActiveAgentProcessDiscovery.ProcessSnapshot(
            tool: .claudeCode,
            sessionID: nil,
            workingDirectory: "/tmp/island-work",
            terminalTTY: "/dev/ttys011",
            terminalApp: "ghostty",
            transcriptPath: fileURL.path
        )

        let firstPass = coordinator.mergedWithSyntheticClaudeSessions(
            existingSessions: [],
            activeProcesses: [process],
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let first = try #require(firstPass.first { coordinator.isSyntheticClaudeSession($0) })

        let secondPass = coordinator.mergedWithSyntheticClaudeSessions(
            existingSessions: firstPass,
            activeProcesses: [process],
            now: Date(timeIntervalSince1970: 2_000_000_500)
        )
        let second = try #require(secondPass.first { coordinator.isSyntheticClaudeSession($0) })

        #expect(first.id == second.id)
        #expect(second.updatedAt == first.updatedAt)
    }

    // MARK: - Helpers

    private func makeTranscript(cwd: String, lines: [String]) throws -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-synthetic-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("transcript.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        return (root, fileURL)
    }
}
