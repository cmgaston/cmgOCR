//
//  ContentView.swift
//  OCR PDF App
//
//  Created by Cristiano M. Gaston on 23/01/26.
//



import SwiftUI
import PDFKit
import Vision
import UniformTypeIdentifiers
import AppKit

// MARK: - Modello Strutturale
struct TextElement {
    let observation: VNRecognizedTextObservation
    let text: String
    let avgHeight: CGFloat
    
    var isTitle: Bool {
        observation.boundingBox.height > (avgHeight * 1.8)
    }
    
    var isHeader: Bool {
        observation.boundingBox.height > (avgHeight * 1.3) && !isTitle
    }
    
    func shouldWrapToNextLine(nextElement: TextElement?) -> Bool {
        guard let next = nextElement else { return false }
        let currentY = observation.boundingBox.origin.y
        let nextY = next.observation.boundingBox.origin.y
        let verticalGap = currentY - nextY
        return verticalGap > (observation.boundingBox.height * 1.5)
    }
}

// MARK: - Componente Visualizzatore PDF
struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - ViewModel
@Observable
class OCRViewModel {
    var recognizedText: String = ""
    var isProcessing: Bool = false
    var progress: Double = 0.0
    var errorMessage: String? = nil
    var selectedURL: URL? = nil

    func selectPDF(at url: URL) {
        // Rilasciamo la risorsa precedente se esiste
        selectedURL?.stopAccessingSecurityScopedResource()
        
        // Per i file provenienti da Drag & Drop o File Picker, dobbiamo chiedere l'accesso.
        // Se l'URL non è security-scoped, startAccessing restituirà false, ma potremmo
        // comunque avere accesso se siamo fuori dalla sandbox o in una cartella autorizzata.
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        
        // Verifichiamo se il file è leggibile. 
        // Nota: se è security-scoped, DEVE essere chiamato startAccessing prima di questa verifica.
        if FileManager.default.isReadableFile(atPath: url.path) {
            selectedURL = url
            recognizedText = ""
            errorMessage = nil
            progress = 0.0
        } else {
            // Se non è leggibile e avevamo ottenuto un accesso di sicurezza, lo rilasciamo subito
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
            errorMessage = "Errore di accesso: il file non è leggibile."
        }
    }

    func startOCR() async {
        guard let url = selectedURL else { return }
        
        isProcessing = true
        errorMessage = nil
        recognizedText = ""
        progress = 0.0
        
        do {
            guard let document = PDFDocument(url: url) else {
                throw NSError(domain: "OCRApp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Il file non è un PDF valido."])
            }
            
            let pageCount = document.pageCount
            var accumulatedText = ""
            
            for i in 0..<pageCount {
                guard let page = document.page(at: i) else { continue }
                if let image = pageToImage(page) {
                    let pageText = try await recognizeTextWithElements(in: image)
                    accumulatedText += "--- PAGINA \(i + 1) ---\n\n" + pageText + "\n\n"
                }
                
                await MainActor.run {
                    progress = Double(i + 1) / Double(pageCount)
                }
            }
            
            recognizedText = accumulatedText
        } catch {
            errorMessage = "Errore: \(error.localizedDescription)"
        }
        
        isProcessing = false
    }

    private func pageToImage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let nsImage = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            return true
        }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func recognizeTextWithElements(in image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(returning: "")
                    return
                }
                
                let sortedObs = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                let avgHeight = sortedObs.map { $0.boundingBox.height }.reduce(0, +) / CGFloat(sortedObs.count)
                
                let elements = sortedObs.compactMap { obs -> TextElement? in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    return TextElement(observation: obs, text: text, avgHeight: avgHeight)
                }
                
                var output = ""
                for (index, element) in elements.enumerated() {
                    let next = (index + 1 < elements.count) ? elements[index + 1] : nil
                    var text = element.text
                    
                    if element.isTitle {
                        output += "\n# " + text.uppercased() + "\n"
                    } else if element.isHeader {
                        output += "\n## " + text + "\n"
                    } else {
                        let shouldWrap = element.shouldWrapToNextLine(nextElement: next)
                        
                        if text.hasSuffix("-") && next != nil {
                            // Rimuove il trattino di a capo e unisce alla parola successiva senza spazi
                            text.removeLast()
                            output += text
                        } else {
                            output += text
                            if shouldWrap {
                                output += "\n\n"
                            } else {
                                output += " "
                            }
                        }
                    }
                }
                continuation.resume(returning: output)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["it-IT", "en-US"]
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Documento per Esportazione
struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, UTType(tag: "md", tagClass: .filenameExtension, conformingTo: .plainText)!] }
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
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}

// MARK: - Interfaccia Utente
struct ContentView: View {
    @State private var viewModel: OCRViewModel

    init(viewModel: OCRViewModel = OCRViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }
    @State private var isImporterPresented = false
    @State private var isExporting = false
    @State private var selectedRange = NSRange(location: 0, length: 0)

    private func toggleH1() {
        applyBlockPrefix("# ")
    }

    private func toggleH2() {
        applyBlockPrefix("## ")
    }

    private func toggleH3() {
        applyBlockPrefix("### ")
    }

    private func toggleH4() {
        applyBlockPrefix("#### ")
    }

    private func toggleQuote() {
        applyBlockPrefix("> ")
    }

    private func applyBlockPrefix(_ prefix: String) {
        let range = selectedRange
        guard range.location != NSNotFound else { return }
        
        let currentText = viewModel.recognizedText
        let nsString = currentText as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        let lineContent = nsString.substring(with: lineRange)
        
        var newText: String
        var newLocation = range.location
        
        if lineContent.hasPrefix(prefix) {
            // Rimuovi il prefisso
            let updatedLine = String(lineContent.dropFirst(prefix.count))
            newText = nsString.replacingCharacters(in: lineRange, with: updatedLine)
            newLocation = max(lineRange.location, range.location - prefix.count)
        } else {
            // Aggiungi il prefisso
            newText = nsString.replacingCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
            newLocation = range.location + prefix.count
        }
        
        viewModel.recognizedText = newText
        selectedRange = NSRange(location: newLocation, length: range.length)
    }

    private func toggleItalic() {
        applyInlineFormatting(delimiter: "*")
    }

    private func toggleBold() {
        applyInlineFormatting(delimiter: "**")
    }

    private func applyInlineFormatting(delimiter: String) {
        let range = selectedRange
        guard range.location != NSNotFound else { return }
        
        let currentText = viewModel.recognizedText
        let nsString = currentText as NSString
        
        if range.length > 0 {
            guard range.location + range.length <= nsString.length else { return }
            let selectedText = nsString.substring(with: range)
            
            if selectedText.hasPrefix(delimiter) && selectedText.hasSuffix(delimiter) {
                // Rimuovi formattazione
                let start = selectedText.index(selectedText.startIndex, offsetBy: delimiter.count)
                let end = selectedText.index(selectedText.endIndex, offsetBy: -delimiter.count)
                let newSnippet = String(selectedText[start..<end])
                
                let newText = nsString.replacingCharacters(in: range, with: newSnippet)
                viewModel.recognizedText = newText
                selectedRange = NSRange(location: range.location, length: range.length - (delimiter.count * 2))
            } else {
                // Aggiungi formattazione
                let newSnippet = "\(delimiter)\(selectedText)\(delimiter)"
                let newText = nsString.replacingCharacters(in: range, with: newSnippet)
                viewModel.recognizedText = newText
                selectedRange = NSRange(location: range.location, length: range.length + (delimiter.count * 2))
            }
        } else {
            // Nessuna selezione: inserisci i delimitatori e sposta il cursore al centro
            let newSnippet = "\(delimiter)\(delimiter)"
            let newText = nsString.replacingCharacters(in: range, with: newSnippet)
            viewModel.recognizedText = newText
            selectedRange = NSRange(location: range.location + delimiter.count, length: 0)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let url = viewModel.selectedURL {
                    mainContentView(for: url)
                } else {
                    noDocumentView
                }
                
                if let error = viewModel.errorMessage {
                    errorOverlay(error)
                }
            }
            .navigationTitle(viewModel.selectedURL?.lastPathComponent ?? "CMG MyOCR App")
            .toolbar { toolbarContent }
            .fileExporter(
                isPresented: $isExporting,
                document: TextDocument(text: viewModel.recognizedText),
                contentType: .plainText, // Usiamo plainText come base per compatibilità
                defaultFilename: (viewModel.selectedURL?.deletingPathExtension().lastPathComponent ?? "testo_estratto") + ".md"
            ) { result in
                if case .failure(let error) = result {
                    viewModel.errorMessage = "Errore durante l'esportazione: \(error.localizedDescription)"
                }
            }
            .dropDestination(for: URL.self) { items, location in
                guard let url = items.first else { return false }
                if url.pathExtension.lowercased() == "pdf" {
                    viewModel.selectPDF(at: url)
                    return true
                }
                return false
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.selectPDF(at: url)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
    
    @ViewBuilder
    private func mainContentView(for url: URL) -> some View {
        HSplitView {
            PDFKitRepresentedView(url: url)
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            
            ocrSideView
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
        }
    }
    
    @ViewBuilder
    private var ocrSideView: some View {
        if viewModel.isProcessing {
            processingView
        } else if viewModel.recognizedText.isEmpty {
            emptyOCRView
        } else {
            editorView
        }
    }
    
    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView(value: viewModel.progress, total: 1.0)
                .progressViewStyle(.linear)
                .padding()
            Text("Analisi in corso... \(Int(viewModel.progress * 100))%")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyOCRView: some View {
        ContentUnavailableView {
            Label("Pronto per l'OCR", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Clicca su 'Inizia OCR' per estrarre il testo dal documento.")
        } actions: {
            Button("Inizia OCR") {
                Task { await viewModel.startOCR() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private var editorView: some View {
        VStack(spacing: 0) {
            formattingToolbar
            Divider()
            MacTextEditor(text: $viewModel.recognizedText, selectedRange: $selectedRange)
                .background(Color(NSColor.textBackgroundColor))
            Divider()
            exportButton
        }
    }
    
    private var formattingToolbar: some View {
        HStack(spacing: 12) {
            // Gruppo Testo
            HStack(spacing: 4) {
                toolbarButton(systemName: "bold", action: toggleBold, tooltip: "Grassetto (Cmd+B)")
                toolbarButton(systemName: "italic", action: toggleItalic, tooltip: "Corsivo (Cmd+I)")
            }
            .padding(4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            // Gruppo Titoli
            HStack(spacing: 4) {
                toolbarButton(text: "H1", action: toggleH1, tooltip: "Titolo 1 (Cmd+1)")
                toolbarButton(text: "H2", action: toggleH2, tooltip: "Titolo 2 (Cmd+2)")
                toolbarButton(text: "H3", action: toggleH3, tooltip: "Titolo 3 (Cmd+3)")
                toolbarButton(text: "H4", action: toggleH4, tooltip: "Titolo 4 (Cmd+4)")
            }
            .padding(4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            // Gruppo Citazione
            HStack(spacing: 4) {
                toolbarButton(systemName: "quote.opening", action: toggleQuote, tooltip: "Citazione (Cmd+\\)")
            }
            .padding(4)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func toolbarButton(systemName: String? = nil, text: String? = nil, action: @escaping () -> Void, tooltip: String) -> some View {
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
    
    private var exportButton: some View {
        Button(action: { isExporting = true }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Esporta il testo (.md)")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .padding()
    }
    
    private var noDocumentView: some View {
        ContentUnavailableView {
            Label("Nessun documento", systemImage: "pdfview.fill")
        } description: {
            Text("Trascina o seleziona un file PDF per iniziare.")
        } actions: {
            Button("Seleziona PDF") { isImporterPresented = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
    
    private func errorOverlay(_ error: String) -> some View {
        Text(error)
            .foregroundColor(.red)
            .padding()
            .background(.ultraThinMaterial)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { isImporterPresented = true }) {
                Label("Cambia PDF", systemImage: "doc.badge.plus")
            }
            .disabled(viewModel.isProcessing)
        }
        
        if viewModel.selectedURL != nil && !viewModel.isProcessing {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.recognizedText.isEmpty {
                    Button("Inizia OCR") { Task { await viewModel.startOCR() } }
                        .keyboardShortcut("R", modifiers: .command)
                } else {
                    Button("Esporta") { isExporting = true }
                        .keyboardShortcut("S", modifiers: .command)
                }
            }
        }
        
        ToolbarItem(placement: .secondaryAction) {
            Button(action: {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(viewModel.recognizedText, forType: .string)
            }) {
                Label("Copia Testo", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.recognizedText.isEmpty)
        }
    }
}

// MARK: - Custom Text Editor for Selection Support
struct MacTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        context.coordinator.isUpdatingFromBinding = true
        
        if textView.string != text {
            textView.string = text
        }
        
        if textView.selectedRange() != selectedRange {
            textView.setSelectedRange(selectedRange)
        }
        
        context.coordinator.isUpdatingFromBinding = false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextEditor
        var isUpdatingFromBinding = false
        
        init(_ parent: MacTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromBinding,
                  let textView = notification.object as? NSTextView else { return }
            
            let newText = textView.string
            if parent.text != newText {
                parent.text = newText
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdatingFromBinding,
                  let textView = notification.object as? NSTextView else { return }
            
            let newRange = textView.selectedRange()
            if parent.selectedRange != newRange {
                // Aggiorniamo la selezione immediatamente per evitare race conditions
                // durante la digitazione veloce.
                Task { @MainActor in
                    self.parent.selectedRange = newRange
                }
            }
        }
    }
}

#Preview("Stato Iniziale") {
    ContentView()
}

#Preview("Documento Caricato") {
    let vm = OCRViewModel()
    // Simuliamo un documento caricato e del testo estratto
    vm.selectedURL = URL(fileURLWithPath: "/tmp/anteprima.pdf")
    vm.recognizedText = """
    # Titolo Documento
    
    Questo è un esempio di testo estratto tramite OCR. Puoi vedere come appare la barra di formattazione qui sopra:
    
    *   Testo in **grassetto** per evidenziare concetti.
    *   Testo in *corsivo* per enfasi.
    
    ## Sezione 2
    Usa le scorciatoie Cmd+B, Cmd+I o i pulsanti H2/H3 per strutturare il tuo markdown.
    """
    return ContentView(viewModel: vm)
}
