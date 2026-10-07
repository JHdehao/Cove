import SwiftUI

/// Renders the Markdown the models write — headings, lists, checkboxes, quotes,
/// paragraphs — in Claude's reading style. Inline formatting and links (citations
/// become "cove://seg/N" links) go through AttributedString.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private enum Block {
        case heading(Int, String)
        case bullet(String, checkbox: Bool?, indent: Int, ordered: Bool = false)
        case quote(String)
        case paragraph(String)
        case rule
    }

    private var blocks: [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " }.count / 2
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix { $0 == "#" }.count
                blocks.append(.heading(level, line.dropFirst(level).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(6)), checkbox: !line.hasPrefix("- [ ]"), indent: indent))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2)), checkbox: nil, indent: indent))
            } else if let match = line.firstMatch(of: #/^(\d+)[.)]\s+(.*)$/#) {
                flush()
                blocks.append(.bullet("\(match.1). \(match.2)", checkbox: nil, indent: indent, ordered: true))
            } else if line.hasPrefix(">") {
                flush()
                blocks.append(.quote(line.dropFirst().trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" {
                flush()
                blocks.append(.rule)
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level <= 1 ? .system(.title2, design: .serif).weight(.semibold)
                      : level == 2 ? .system(.title3, design: .serif).weight(.semibold) : .headline)
                .padding(.top, level <= 2 ? 8 : 4)
        case .bullet(let text, let checkbox, let indent, let ordered):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let checkbox {
                    Image(systemName: checkbox ? "checkmark.square" : "square")
                        .foregroundStyle(CoveColor.accent)
                } else if ordered {
                    // "1. …": the number is the marker.
                    EmptyView()
                } else {
                    Text("•").foregroundStyle(CoveColor.accent)
                }
                inline(text)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            inline(text)
                .font(.system(.body, design: .serif))
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(CoveColor.accent).frame(width: 3)
                }
        case .paragraph(let text):
            inline(text)
        case .rule:
            Divider()
        }
    }

    private func inline(_ text: String) -> Text {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        return Text(attributed).foregroundStyle(CoveColor.text)
    }
}
