import AppKit
import SwiftUI

/// Shared markdown renderer for chat messages and project plans.
/// Handles common block markdown, thematic breaks, and GitHub-style tables.
struct MarkdownTextView: View, Equatable {
    let text: String
    var animateTransitions: Bool = true

    static func == (lhs: MarkdownTextView, rhs: MarkdownTextView) -> Bool {
        lhs.text == rhs.text && lhs.animateTransitions == rhs.animateTransitions
    }

    var body: some View {
        let blocks = parseBlocks()
        let blockTransition = animateTransitions
            ? AnyTransition.opacity.combined(with: .offset(y: 6))
            : .identity

        let stack = VStack(alignment: .leading, spacing: Theme.spacingSM) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                Group {
                    switch block {
                    case .heading(let level, let content):
                        headingView(level: level, content: content)
                    case .codeBlock(let language, let code):
                        codeBlockView(language: language, code: code)
                    case .paragraph(let content):
                        Text(LocalizedStringKey(content))
                            .font(Theme.geist(13))
                            .foregroundStyle(.primary)
                    case .listItem(let content):
                        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                            Text("•")
                                .foregroundStyle(Theme.textTertiary)
                            Text(LocalizedStringKey(content))
                                .font(Theme.geist(13))
                        }
                    case .checklistItem(let checked, let content):
                        HStack(alignment: .firstTextBaseline, spacing: Theme.spacingSM) {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.caption)
                                .foregroundStyle(checked ? Theme.success : Theme.textTertiary)
                            Text(LocalizedStringKey(content))
                                .font(Theme.geist(13))
                        }
                    case .thematicBreak:
                        thematicBreakView()
                    case .table(let headers, let alignments, let rows):
                        tableView(headers: headers, alignments: alignments, rows: rows)
                    }
                }
                .transition(blockTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if animateTransitions {
            stack
                .animation(.easeOut(duration: 0.22), value: blocks.count)
        } else {
            stack
        }
    }

    // MARK: - Block views

    private func headingView(level: Int, content: String) -> some View {
        Text(LocalizedStringKey(content))
            .font(level == 1 ? .title2 : level == 2 ? .title3 : .headline)
            .fontWeight(.semibold)
            .padding(.top, level == 1 ? Theme.spacingSM : Theme.spacingXS)
    }

    private func codeBlockView(language: String, code: String) -> some View {
        MarkdownCodeBlockView(language: language, code: code)
    }

    private func thematicBreakView() -> some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.vertical, Theme.spacingSM)
    }

    private func tableView(
        headers: [String],
        alignments: [TableColumnAlignment],
        rows: [[String]]
    ) -> some View {
        let columnCount = headers.count
        let lastRowIndex = rows.count - 1

        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                        tableCellView(
                            content: header,
                            alignment: alignments[index],
                            isHeader: true,
                            rowIndex: nil,
                            isLastColumn: index == columnCount - 1,
                            isLastRow: rows.isEmpty
                        )
                    }
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
                            tableCellView(
                                content: cell,
                                alignment: alignments[columnIndex],
                                isHeader: false,
                                rowIndex: rowIndex,
                                isLastColumn: columnIndex == columnCount - 1,
                                isLastRow: rowIndex == lastRowIndex
                            )
                        }
                    }
                }
            }
            .background(Theme.surfaceElevated.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .stroke(Theme.separator, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableCellView(
        content: String,
        alignment: TableColumnAlignment,
        isHeader: Bool,
        rowIndex: Int?,
        isLastColumn: Bool,
        isLastRow: Bool
    ) -> some View {
        let backgroundColor: Color
        if isHeader {
            backgroundColor = Theme.accent.opacity(0.08)
        } else if let rowIndex, !rowIndex.isMultiple(of: 2) {
            backgroundColor = Theme.separator.opacity(0.6)
        } else {
            backgroundColor = .clear
        }

        return ZStack(alignment: alignment.frameAlignment) {
            Text(LocalizedStringKey(content))
                .font(isHeader ? .subheadline.weight(.semibold) : Theme.geist(13))
                .multilineTextAlignment(alignment.textAlignment)
                .frame(maxWidth: .infinity, alignment: alignment.frameAlignment)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.vertical, Theme.spacingSM)
        }
        .frame(minWidth: 120, maxWidth: .infinity, alignment: alignment.frameAlignment)
        .background(backgroundColor)
        .overlay(alignment: .trailing) {
            if !isLastColumn {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLastRow {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
            }
        }
    }

    private struct MarkdownCodeBlockView: View {
        let language: String
        let code: String
        @State private var isCopied = false

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.spacingSM) {
                HStack(spacing: Theme.spacingXS) {
                    if !language.isEmpty {
                        Text(language)
                            .font(Theme.geistMono(10))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Theme.textPrimary.opacity(0.08))
                            )
                    }

                    Spacer(minLength: 0)

                    Button {
                        copyCode()
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isCopied ? Theme.success : Theme.textTertiary)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.textPrimary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isCopied ? "Copied" : "Copy code")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(Theme.codeFontSmall)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Theme.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
        }

        private func copyCode() {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isCopied = false
            }
        }
    }

    // MARK: - Parser

    private enum Block {
        case heading(level: Int, content: String)
        case codeBlock(language: String, code: String)
        case paragraph(content: String)
        case listItem(content: String)
        case checklistItem(checked: Bool, content: String)
        case thematicBreak
        case table(headers: [String], alignments: [TableColumnAlignment], rows: [[String]])
    }

    private enum TableColumnAlignment {
        case leading
        case center
        case trailing

        var frameAlignment: Alignment {
            switch self {
            case .leading:
                .leading
            case .center:
                .center
            case .trailing:
                .trailing
            }
        }

        var textAlignment: TextAlignment {
            switch self {
            case .leading:
                .leading
            case .center:
                .center
            case .trailing:
                .trailing
            }
        }
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let codeLine = lines[i]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(codeLine)
                    i += 1
                }
                let code = codeLines.joined(separator: "\n")
                if !code.isEmpty {
                    blocks.append(.codeBlock(language: language, code: code))
                }
                continue
            }

            // Heading
            if trimmed.hasPrefix("###") {
                let content = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { blocks.append(.heading(level: 3, content: content)) }
                i += 1
                continue
            }
            if trimmed.hasPrefix("##") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { blocks.append(.heading(level: 2, content: content)) }
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { blocks.append(.heading(level: 1, content: content)) }
                i += 1
                continue
            }

            // Thematic break
            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            // Table
            if let parsedTable = parseTable(startingAt: i, in: lines) {
                blocks.append(parsedTable.block)
                i = parsedTable.nextIndex
                continue
            }

            // Checklist item
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let content = String(trimmed.dropFirst(6))
                blocks.append(.checklistItem(checked: true, content: content))
                i += 1
                continue
            }
            if trimmed.hasPrefix("- [ ] ") {
                let content = String(trimmed.dropFirst(6))
                blocks.append(.checklistItem(checked: false, content: content))
                i += 1
                continue
            }

            // List item
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2))
                blocks.append(.listItem(content: content))
                i += 1
                continue
            }

            // Numbered list
            if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let content = String(trimmed[match.upperBound...])
                blocks.append(.listItem(content: content))
                i += 1
                continue
            }

            // Empty line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Paragraph — collect consecutive non-empty, non-special lines
            var paraLines: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || startsNewBlock(at: i, in: lines) {
                    break
                }
                paraLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(content: paraLines.joined(separator: " ")))
        }

        return blocks
    }

    private func startsNewBlock(at index: Int, in lines: [String]) -> Bool {
        guard index < lines.count else { return false }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") || trimmed.hasPrefix("```") {
            return true
        }
        if isThematicBreak(trimmed) {
            return true
        }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") || trimmed.hasPrefix("- [ ] ") {
            return true
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return true
        }
        if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
            return true
        }

        return parseTable(startingAt: index, in: lines) != nil
    }

    private func isThematicBreak(_ line: String) -> Bool {
        line.range(
            of: #"^(-\s*){3,}$|^(\*\s*){3,}$|^(_\s*){3,}$"#,
            options: .regularExpression
        ) != nil
    }

    private func parseTable(startingAt index: Int, in lines: [String]) -> (block: Block, nextIndex: Int)? {
        guard index + 1 < lines.count else { return nil }

        guard let headerCells = parseTableRow(lines[index]), headerCells.count > 1 else {
            return nil
        }
        guard let separatorCells = parseTableRow(lines[index + 1]) else {
            return nil
        }

        let columnCount = headerCells.count
        let normalizedSeparatorCells = normalizeCells(separatorCells, to: columnCount)
        guard normalizedSeparatorCells.allSatisfy(isTableSeparatorCell) else {
            return nil
        }

        let alignments = normalizedSeparatorCells.map(parseTableAlignment)
        let normalizedHeaders = normalizeCells(headerCells, to: columnCount)

        var rows: [[String]] = []
        var cursor = index + 2

        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let cells = parseTableRow(lines[cursor]) else {
                break
            }

            rows.append(normalizeCells(cells, to: columnCount))
            cursor += 1
        }

        return (.table(headers: normalizedHeaders, alignments: alignments, rows: rows), cursor)
    }

    private func parseTableRow(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }

        var working = trimmed
        if working.hasPrefix("|") {
            working.removeFirst()
        }
        if working.hasSuffix("|") {
            working.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var activeCodeDelimiterLength: Int?
        let characters = Array(working)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\\" {
                if index + 1 < characters.count {
                    current.append(characters[index + 1])
                    index += 2
                } else {
                    current.append(character)
                    index += 1
                }
                continue
            }

            if character == "`" {
                var delimiterLength = 1
                while index + delimiterLength < characters.count && characters[index + delimiterLength] == "`" {
                    delimiterLength += 1
                }

                current.append(String(repeating: "`", count: delimiterLength))
                if activeCodeDelimiterLength == delimiterLength {
                    activeCodeDelimiterLength = nil
                } else if activeCodeDelimiterLength == nil {
                    activeCodeDelimiterLength = delimiterLength
                }

                index += delimiterLength
                continue
            }

            if character == "|" && activeCodeDelimiterLength == nil {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
                index += 1
                continue
            }

            current.append(character)
            index += 1
        }

        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private func normalizeCells(_ cells: [String], to count: Int) -> [String] {
        if cells.count == count {
            return cells
        }
        if cells.count > count {
            return Array(cells.prefix(count))
        }

        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func isTableSeparatorCell(_ cell: String) -> Bool {
        cell.range(of: #"^:?-{1,}:?$"#, options: .regularExpression) != nil
    }

    private func parseTableAlignment(_ cell: String) -> TableColumnAlignment {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        let hasLeadingColon = trimmed.hasPrefix(":")
        let hasTrailingColon = trimmed.hasSuffix(":")

        switch (hasLeadingColon, hasTrailingColon) {
        case (true, true):
            return .center
        case (false, true):
            return .trailing
        default:
            return .leading
        }
    }
}
