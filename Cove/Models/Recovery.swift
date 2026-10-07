import Foundation
import SwiftData

/// At launch, closes meetings whose recording never finished (the app was killed or
/// crashed mid-meeting): the parts written so far are joined, and what was transcribed
/// and noted up to then is already in the library.
enum Recovery {
    /// Runs once per launch, before anything new can be recorded. Returns how many were recovered.
    @MainActor
    static func run(_ context: ModelContext) async -> Int {
        guard !didRun else { return 0 }
        didRun = true
        let open = (try? context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.isRecording }))) ?? []
        for meeting in open {
            if let url = meeting.audioURL, let duration = try? await AudioParts.join(meeting.partsDirectory, into: url) {
                meeting.duration = max(meeting.duration, duration)
                // Captions stop wherever the app did; the last minute or so may be missing from them.
                if duration > (meeting.segments.last?.end ?? 0) + 60 { meeting.needsRetranscribe = true }
            } else if meeting.audioURL.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
                meeting.audioFileName = nil
            }
            meeting.isRecording = false
        }
        try? context.save()
        return open.count
    }

    @MainActor private static var didRun = false
}
