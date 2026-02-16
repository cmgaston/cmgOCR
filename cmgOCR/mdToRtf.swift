import Foundation
import AppKit

class MarkdownToRTFConverter {
    
    static func convert(_ markdownContent: String) -> Data? {
        let result = NSMutableAttributedString()
        let lines = markdownContent.components(separatedBy: .newlines)
        
        let baseFont = NSFont.systemFont(ofSize: 12)
        let boldFont = NSFont.boldSystemFont(ofSize: 12)
        let italicFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.italic), size: 12) ?? baseFont
        let codeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 8
        
        for line in lines {
            var processedLine = line
            var attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .paragraphStyle: paragraphStyle
            ]
            
            // Headers
            if processedLine.hasPrefix("# ") {
                processedLine = String(processedLine.dropFirst(2))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 24)
            } else if processedLine.hasPrefix("## ") {
                processedLine = String(processedLine.dropFirst(3))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 20)
            } else if processedLine.hasPrefix("### ") {
                processedLine = String(processedLine.dropFirst(4))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 16)
            } else if processedLine.hasPrefix("#### ") {
                processedLine = String(processedLine.dropFirst(5))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 14)
            } else if processedLine.hasPrefix("##### ") {
                processedLine = String(processedLine.dropFirst(6))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 13)
            } else if processedLine.hasPrefix("###### ") {
                processedLine = String(processedLine.dropFirst(7))
                attributes[.font] = NSFont.boldSystemFont(ofSize: 12)
            }
            
            let lineString = NSMutableAttributedString(string: processedLine, attributes: attributes)
            
            // Grassetto **testo**
            var range = NSRange(location: 0, length: lineString.length)
            if let boldPattern = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: []) {
                let matches = boldPattern.matches(in: lineString.string, options: [], range: range).reversed()
                for match in matches {
                    let contentRange = match.range(at: 1)
                    let fullRange = match.range
                    let content = (lineString.string as NSString).substring(with: contentRange)
                    lineString.replaceCharacters(in: fullRange, with: content)
                    lineString.addAttribute(.font, value: boldFont, range: NSRange(location: fullRange.location, length: content.count))
                }
            }
            
            // Corsivo *testo* o _testo_
            range = NSRange(location: 0, length: lineString.length)
            if let italicPattern = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)|_(.+?)_", options: []) {
                let matches = italicPattern.matches(in: lineString.string, options: [], range: range).reversed()
                for match in matches {
                    let contentRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                    let fullRange = match.range
                    let content = (lineString.string as NSString).substring(with: contentRange)
                    lineString.replaceCharacters(in: fullRange, with: content)
                    lineString.addAttribute(.font, value: italicFont, range: NSRange(location: fullRange.location, length: content.count))
                }
            }
            
            // Codice inline `testo`
            range = NSRange(location: 0, length: lineString.length)
            if let codePattern = try? NSRegularExpression(pattern: "`(.+?)`", options: []) {
                let matches = codePattern.matches(in: lineString.string, options: [], range: range).reversed()
                for match in matches {
                    let contentRange = match.range(at: 1)
                    let fullRange = match.range
                    let content = (lineString.string as NSString).substring(with: contentRange)
                    lineString.replaceCharacters(in: fullRange, with: content)
                    lineString.addAttribute(.font, value: codeFont, range: NSRange(location: fullRange.location, length: content.count))
                    lineString.addAttribute(.backgroundColor, value: NSColor.lightGray.withAlphaComponent(0.2), range: NSRange(location: fullRange.location, length: content.count))
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
            print("Errore conversione RTF: \(error)")
            return nil
        }
    }
}
