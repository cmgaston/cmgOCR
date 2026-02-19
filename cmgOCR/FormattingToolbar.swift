
import SwiftUI
import AppKit

struct FormattingToolbar: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    
    var body: some View {
        HStack(spacing: 12) {
            // Text Group
            HStack(spacing: 4) {
                toolbarButton(systemName: "bold", action: toggleBold, tooltip: "Bold (Cmd+B)", accessibilityLabel: "Bold")
                toolbarButton(systemName: "italic", action: toggleItalic, tooltip: "Italic (Cmd+I)", accessibilityLabel: "Italic")
            }
            .padding(4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            // Quote Group
            HStack(spacing: 4) {
                toolbarButton(systemName: "quote.opening", action: toggleQuote, tooltip: "Quote (Cmd+\\)", accessibilityLabel: "Quote")
            }
            .padding(4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            // Title Group
            HStack(spacing: 4) {
                toolbarButton(text: "H1", action: toggleH1, tooltip: "Header 1 (Cmd+1)", accessibilityLabel: "Header 1")
                toolbarButton(text: "H2", action: toggleH2, tooltip: "Header 2 (Cmd+2)", accessibilityLabel: "Header 2")
                toolbarButton(text: "H3", action: toggleH3, tooltip: "Header 3 (Cmd+3)", accessibilityLabel: "Header 3")
                toolbarButton(text: "H4", action: toggleH4, tooltip: "Header 4 (Cmd+4)", accessibilityLabel: "Header 4")
            }
            .padding(4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func toggleH1() { applyBlockPrefix("# ") }
    private func toggleH2() { applyBlockPrefix("## ") }
    private func toggleH3() { applyBlockPrefix("### ") }
    private func toggleH4() { applyBlockPrefix("#### ") }
    private func toggleQuote() { applyBlockPrefix("> ") }
    private func toggleItalic() { applyInlineFormatting(delimiter: "*") }
    private func toggleBold() { applyInlineFormatting(delimiter: "**") }

    // MARK: - Helper Methods
    
    private func applyBlockPrefix(_ prefix: String) {
        let range = selectedRange
        guard range.location != NSNotFound else { return }
        
        // ... (rest of the method logic is unchanged, just ensuring I don't break it)
        let nsString = text as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        let lineContent = nsString.substring(with: lineRange)
        
        var newText: String
        var newLocation = range.location
        
        if prefix.hasPrefix("#") {
            var hashesCount = 0
            for char in lineContent {
                if char == "#" {
                    hashesCount += 1
                } else {
                    break
                }
            }
            
            if hashesCount > 0 {
                var existingPrefixLength = hashesCount
                let afterHashes = lineContent.dropFirst(hashesCount)
                if afterHashes.hasPrefix(" ") {
                    existingPrefixLength += 1
                }
                
                let existingPrefix = String(lineContent.prefix(existingPrefixLength))
                let lineWithoutPrefix = String(lineContent.dropFirst(existingPrefixLength))
                
                if existingPrefix == prefix {
                    newText = nsString.replacingCharacters(in: lineRange, with: lineWithoutPrefix)
                    newLocation = max(lineRange.location, range.location - existingPrefixLength)
                } else {
                    newText = nsString.replacingCharacters(in: lineRange, with: prefix + lineWithoutPrefix)
                    newLocation = max(lineRange.location, range.location - existingPrefixLength + prefix.count)
                }
            } else {
                newText = nsString.replacingCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
                newLocation = range.location + prefix.count
            }
        } else {
            if lineContent.hasPrefix(prefix) {
                let updatedLine = String(lineContent.dropFirst(prefix.count))
                newText = nsString.replacingCharacters(in: lineRange, with: updatedLine)
                newLocation = max(lineRange.location, range.location - prefix.count)
            } else {
                newText = nsString.replacingCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
                newLocation = range.location + prefix.count
            }
        }
        
        text = newText
        selectedRange = NSRange(location: newLocation, length: range.length)
    }

    private func applyInlineFormatting(delimiter: String) {
        let range = selectedRange
        guard range.location != NSNotFound else { return }
        
        let nsString = text as NSString
        
        if range.length > 0 {
            guard range.location + range.length <= nsString.length else { return }
            let selectedText = nsString.substring(with: range)
            
            if selectedText.hasPrefix(delimiter) && selectedText.hasSuffix(delimiter) {
                let start = selectedText.index(selectedText.startIndex, offsetBy: delimiter.count)
                let end = selectedText.index(selectedText.endIndex, offsetBy: -delimiter.count)
                let newSnippet = String(selectedText[start..<end])
                
                let newText = nsString.replacingCharacters(in: range, with: newSnippet)
                text = newText
                selectedRange = NSRange(location: range.location, length: range.length - (delimiter.count * 2))
            } else {
                let newSnippet = "\(delimiter)\(selectedText)\(delimiter)"
                let newText = nsString.replacingCharacters(in: range, with: newSnippet)
                text = newText
                selectedRange = NSRange(location: range.location, length: range.length + (delimiter.count * 2))
            }
        } else {
            let newSnippet = "\(delimiter)\(delimiter)"
            let newText = nsString.replacingCharacters(in: range, with: newSnippet)
            text = newText
            selectedRange = NSRange(location: range.location + delimiter.count, length: 0)
        }
    }
    
    // MARK: - Toolbar Item Builder
    
    @ViewBuilder
    private func toolbarButton(systemName: String? = nil, text: String? = nil, action: @escaping () -> Void, tooltip: LocalizedStringKey, accessibilityLabel: LocalizedStringKey) -> some View {
        Button(action: action) {
            Group {
                if let systemName = systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .semibold))
                } else if let text = text {
                    Text(text)
                        .font(.system(size: 12, weight: .black))
                }
            }
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(0.05))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(accessibilityLabel)
        .keyboardShortcut(getShortcut(for: systemName, or: text))
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func getShortcut(for systemName: String?, or text: String?) -> KeyboardShortcut? {
        if let sn = systemName {
            switch sn {
            case "bold": return .init("b", modifiers: .command)
            case "italic": return .init("i", modifiers: .command)
            case "quote.opening": return .init("\\", modifiers: .command)
            default: return nil
            }
        }
        if let t = text {
            switch t {
            case "H1": return .init("1", modifiers: .command)
            case "H2": return .init("2", modifiers: .command)
            case "H3": return .init("3", modifiers: .command)
            case "H4": return .init("4", modifiers: .command)
            default: return nil
            }
        }
        return nil
    }
}
