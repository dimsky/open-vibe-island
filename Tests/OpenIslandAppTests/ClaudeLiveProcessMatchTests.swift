import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct ClaudeLiveProcessMatchTests {
    private func candidate(id: String, transcriptPath: String) -> AgentSession {
        AgentSession(
            id: id,
            title: "Claude",
            tool: .claudeCode,
            phase: .completed,
            summary: "",
            updatedAt: Date(timeIntervalSince1970: 0),
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: transcriptPath)
        )
    }

    private func claudeProcess(
        sessionID: String? = nil,
        transcriptPath: String? = nil
    ) -> ActiveAgentProcessDiscovery.ProcessSnapshot {
        .init(
            tool: .claudeCode,
            sessionID: sessionID,
            workingDirectory: nil,
            terminalTTY: nil,
            transcriptPath: transcriptPath
        )
    }

    @Test
    func keepsCandidateMatchedByTranscriptPathDropsUnmatched() {
        let alive = candidate(id: "a", transcriptPath: "/p/a.jsonl")
        let dead = candidate(id: "b", transcriptPath: "/p/b.jsonl")

        let matched = ProcessMonitoringCoordinator.liveClaudeCandidateIDs(
            among: [alive, dead],
            matching: [claudeProcess(transcriptPath: "/p/a.jsonl")]
        )

        #expect(matched == ["a"])
    }

    @Test
    func keepsCandidateMatchedBySessionID() {
        let alive = candidate(id: "sess-1", transcriptPath: "/p/x.jsonl")

        let matched = ProcessMonitoringCoordinator.liveClaudeCandidateIDs(
            among: [alive],
            matching: [claudeProcess(sessionID: "sess-1")]
        )

        #expect(matched == ["sess-1"])
    }

    @Test
    func dropsEveryCandidateWhenNoLiveProcess() {
        let candidates = [
            candidate(id: "a", transcriptPath: "/p/a.jsonl"),
            candidate(id: "b", transcriptPath: "/p/b.jsonl")
        ]

        let matched = ProcessMonitoringCoordinator.liveClaudeCandidateIDs(
            among: candidates,
            matching: []
        )

        #expect(matched.isEmpty)
    }
}
