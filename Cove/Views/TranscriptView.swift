import SwiftUI

/// The transcript, a line per utterance. Tap a line to hear it; the line playing is
/// highlighted; long-press a line to correct it or a speaker to rename them everywhere.
struct TranscriptView: View {
    let meeting: Meeting
    let player: AudioPlayer
    @Binding var focused: Int?
    let rename: (String) -> Void
    let edit: (Int) -> Void

    var body: some View {
        let segments = meeting.segments
        let speakers = Array(Set(segments.compactMap(\.speaker))).sorted()
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if segments.isEmpty {
                        Text("还没有转录内容。").foregroundStyle(.secondary).padding(.top, 40)
                    }
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        row(index: index, segment: segment, previous: index > 0 ? segments[index - 1] : nil, speakers: speakers)
                            .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: focused) { _, index in
                guard let index else { return }
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
            .onAppear {
                if let focused { proxy.scrollTo(focused, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func row(index: Int, segment: Segment, previous: Segment?, speakers: [String]) -> some View {
        let playing = player.isPlaying && player.currentTime >= segment.start && player.currentTime < segment.end
        VStack(alignment: .leading, spacing: 4) {
            if let speaker = segment.speaker, speaker != previous?.speaker {
                Text(speaker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoveColor.speaker(speakers.firstIndex(of: speaker) ?? 0))
                    .contextMenu {
                        Button { rename(speaker) } label: { Label("重命名说话人", systemImage: "pencil") }
                    }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(clockString(segment.start))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(segment.text)
                    .foregroundStyle(CoveColor.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CoveColor.accent.opacity(playing || focused == index ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focused = index
            player.seek(segment.start)
        }
        .contextMenu {
            Button { edit(index) } label: { Label("编辑这一句", systemImage: "pencil") }
            if let speaker = segment.speaker {
                Button { rename(speaker) } label: { Label("重命名「\(speaker)」", systemImage: "person.text.rectangle") }
            }
            Button { UIPasteboard.general.string = segment.text } label: { Label("拷贝", systemImage: "doc.on.doc") }
        }
    }
}
