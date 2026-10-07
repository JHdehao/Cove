import EventKit
import SwiftUI

/// Fix one line of the transcript: the words, and who said it.
struct SegmentEditor: View {
    let segment: Segment
    let speakers: [String]
    let onSave: (Segment) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var speaker = ""
    @State private var newSpeaker = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 140)
                } header: {
                    Text(clockString(segment.start))
                } footer: {
                    Text("改过的文字会用在之后重新生成的纪要和对话里。")
                }
                .coveCard()
                Section("说话人") {
                    Picker("说话人", selection: $speaker) {
                        Text(String(localized: "未标注")).tag("")
                        ForEach(speakers, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("或填一个新名字", text: $newSpeaker)
                }
                .coveCard()
            }
            .coveGroupedBackground()
            .navigationTitle("编辑这一句")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var edited = segment
                        edited.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = newSpeaker.trimmingCharacters(in: .whitespaces)
                        edited.speaker = name.isEmpty ? (speaker.isEmpty ? nil : speaker) : name
                        onSave(edited)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                text = segment.text
                speaker = segment.speaker ?? ""
            }
        }
    }
}

/// Check the to-dos the minutes found before they go to Reminders: untick, reword, add the owner.
struct ActionItemsSheet: View {
    let meetingTitle: String
    @State var items: [Item]
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var saving = false

    struct Item: Identifiable {
        let id = UUID()
        var text: String
        var include = true
    }

    init(meetingTitle: String, items: [String]) {
        self.meetingTitle = meetingTitle
        _items = State(initialValue: items.map { Item(text: $0.replacingOccurrences(of: " — 待定", with: "")) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($items) { $item in
                        HStack(alignment: .top) {
                            Button { item.include.toggle() } label: {
                                Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.include ? CoveColor.accent : .secondary)
                            }
                            .buttonStyle(.borderless)
                            TextField("待办", text: $item.text, axis: .vertical)
                        }
                    }
                } footer: {
                    Text("格式：任务 — 负责人 — 截止时间。模型可能漏掉没明说负责人的分工，可以在这里补上。")
                }
                .coveCard()
                if let message {
                    Text(message).font(.callout)
                }
            }
            .coveGroupedBackground()
            .navigationTitle("确认待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入 \(items.filter(\.include).count) 条") { Task { await save() } }
                        .disabled(saving || !items.contains(where: \.include))
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let store = EKEventStore()
        do {
            guard try await store.requestFullAccessToReminders() else {
                message = String(localized: "没有提醒事项的权限。请到系统设置 → 隐私与安全性 → 提醒事项里打开 Cove。")
                return
            }
            let chosen = items.filter { $0.include && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            for item in chosen {
                let reminder = EKReminder(eventStore: store)
                reminder.title = item.text
                reminder.notes = String(localized: "来自会议：\(meetingTitle)")
                reminder.calendar = store.defaultCalendarForNewReminders()
                try store.save(reminder, commit: false)
            }
            try store.commit()
            message = String(localized: "已导入 \(chosen.count) 条待办到提醒事项。")
        } catch {
            message = String(localized: "导入失败：\(error.localizedDescription)")
        }
    }
}
