import Foundation
import AppKit

class MarkdownToRTFConverter {

    // Compiled once — not inside the per-line loop
    private static let boldPattern   = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    private static let italicPattern = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|_(.+?)_")
    private static let codePattern   = try? NSRegularExpression(pattern: "`(.+?)`")

    static func convert(_ markdownContent: String) -> Data? {
        let result = NSMutableAttributedString()
        let lines = markdownContent.components(separatedBy: .newlines)

        let baseFont = NSFont.systemFont(ofSize: 12)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 8
        
        for line in lines {
            var processedLine = line
            var attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .paragraphStyle: paragraphStyle
            ]
            
            // Headers — checked longest-prefix-first to avoid "# " matching "## ", "### ", etc.
            if processedLine.hasPrefix("###### ") {
                processedLine = String(processedLine.dropFirst(7))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 12)
            } else if processedLine.hasPrefix("##### ") {
                processedLine = String(processedLine.dropFirst(6))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 13)
            } else if processedLine.hasPrefix("#### ") {
                processedLine = String(processedLine.dropFirst(5))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 14)
            } else if processedLine.hasPrefix("### ") {
                processedLine = String(processedLine.dropFirst(4))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 16)
            } else if processedLine.hasPrefix("## ") {
                processedLine = String(processedLine.dropFirst(3))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 20)
            } else if processedLine.hasPrefix("# ") {
                processedLine = String(processedLine.dropFirst(2))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 24)
            }
            
            let lineString = NSMutableAttributedString(string: processedLine, attributes: attributes)
            
            // Bold **text** — traits applied on top of the existing font to preserve header size
            var range = NSRange(location: 0, length: lineString.length)
            if let boldPattern = Self.boldPattern {
                let matches = boldPattern.matches(in: lineString.string, options: [], range: range).reversed()
                for match in matches {
                    let contentRange = match.range(at: 1)
                    let fullRange = match.range
                    let content = (lineString.string as NSString).substring(with: contentRange)
                    lineString.replaceCharacters(in: fullRange, with: content)
                    let spanRange = NSRange(location: fullRange.location, length: content.count)
                    let base = lineString.attribute(.font, at: fullRange.location, effectiveRange: nil) as? NSFont ?? baseFont
                    let bolded = NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
                    lineString.addAttribute(.font, value: bolded, range: spanRange)
                }
            }

            // Italic *text* or _text_ — same: inherit existing font size
            range = NSRange(location: 0, length: lineString.length)
            if let italicPattern = Self.italicPattern {
                let matches = italicPattern.matches(in: lineString.string, options: [], range: range).reversed()
                for match in matches {
                    let contentRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                    let fullRange = match.range
                    let content = (lineString.string as NSString).substring(with: contentRange)
                    lineString.replaceCharacters(in: fullRange, with: content)
                    let spanRange = NSRange(location: fullRange.location, length: content.count)
                    let base = lineString.attribute(.font, at: fullRange.location, effectiveRange: nil) as? NSFont ?? baseFont
                    let italicized = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
                    lineString.addAttribute(.font, value: italicized, range: spanRange)
                }
            }

            // Inline code `text`
            range = NSRange(location: 0, length: lineString.length)
            if let codePattern = Self.codePattern {
                let matches = codePattern.matches(in: lineString.string, options: [], range: range).reversed()
                for match in matches {
                    let contentRange = match.range(at: 1)
                    let fullRange = match.range
                    let content = (lineString.string as NSString).substring(with: contentRange)
                    lineString.replaceCharacters(in: fullRange, with: content)
                    let spanRange = NSRange(location: fullRange.location, length: content.count)
                    lineString.addAttribute(.font, value: codeFont, range: spanRange)
                    lineString.addAttribute(.backgroundColor, value: NSColor.lightGray.withAlphaComponent(0.2), range: spanRange)
                }
            }
            
            result.append(lineString)
            result.append(NSAttributedString(string: "\n"))
        }
        
        do {
            return try result.data(
                from: NSRange(location: 0, length: result.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        } catch {
            print("RTF conversion error: \(error)")
            return nil
        }
    }
}
