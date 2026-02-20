
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export Document
struct TextDocument: FileDocument {
    // Dynamic definition based on extension to avoid missing Info.plist errors
    static let markdownType = UTType(tag: "md", tagClass: .filenameExtension, conformingTo: .plainText) ?? .plainText
    
    static var readableContentTypes: [UTType] { [markdownType, .rtf] }
    static var writableContentTypes: [UTType] { [markdownType, .rtf] }
    
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if configuration.contentType == .rtf {
            guard let data = MarkdownToRTFConverter.convert(text) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return .init(regularFileWithContents: data)
        } else {
            let data = text.data(using: .utf8) ?? Data()
            return .init(regularFileWithContents: data)
        }
    }
}
