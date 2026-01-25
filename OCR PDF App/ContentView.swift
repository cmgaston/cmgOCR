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
    static var readableContentTypes: [UTType] { [.plainText] }
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
    @State private var viewModel = OCRViewModel()
    @State private var isImporterPresented = false
    @State private var isExporting = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let url = viewModel.selectedURL {
                    HSplitView {
                        // Sinistra: Anteprima documento PDF
                        VStack {
                            PDFKitRepresentedView(url: url)
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Destra: Risultato OCR o Elaborazione
                        VStack {
                            if viewModel.isProcessing {
                                VStack(spacing: 20) {
                                    ProgressView(value: viewModel.progress, total: 1.0)
                                        .progressViewStyle(.linear)
                                        .padding()
                                    Text("Analisi in corso... \(Int(viewModel.progress * 100))%")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if viewModel.recognizedText.isEmpty {
                                ContentUnavailableView {
                                    Label("Pronto per l'OCR", systemImage: "doc.text.magnifyingglass")
                                } description: {
                                    Text("Clicca su 'Inizia OCR' per estrarre il testo dal documento.")
                                } actions: {
                                    Button("Inizia OCR") {
                                        Task {
                                            await viewModel.startOCR()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                VStack(spacing: 0) {
                                    TextEditor(text: $viewModel.recognizedText)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(8)
                                        .scrollContentBackground(.hidden)
                                        .background(Color(NSColor.textBackgroundColor))
                                    
                                    Divider()
                                    
                                    Button(action: { isExporting = true }) {
                                        HStack {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Esporta il testo (.txt)")
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.accentColor)
                                    .padding()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.textBackgroundColor))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("Nessun documento", systemImage: "pdfview.fill")
                    } description: {
                        Text("Trascina o seleziona un file PDF per iniziare.")
                    } actions: {
                        Button("Seleziona PDF") {
                            isImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .background(.ultraThinMaterial)
                }
            }
            .navigationTitle(viewModel.selectedURL?.lastPathComponent ?? "Vision OCR Pro")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isImporterPresented = true }) {
                        Label("Cambia PDF", systemImage: "doc.badge.plus")
                    }
                    .disabled(viewModel.isProcessing)
                }
                
                if viewModel.selectedURL != nil && !viewModel.isProcessing {
                    ToolbarItem(placement: .primaryAction) {
                        if viewModel.recognizedText.isEmpty {
                            Button("Inizia OCR") {
                                Task { await viewModel.startOCR() }
                            }
                            .keyboardShortcut("R", modifiers: .command)
                        } else {
                            Button("Esporta") {
                                isExporting = true
                            }
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
            .fileExporter(
                isPresented: $isExporting,
                document: TextDocument(text: viewModel.recognizedText),
                contentType: .plainText,
                defaultFilename: (viewModel.selectedURL?.deletingPathExtension().lastPathComponent ?? "testo_estratto") + ".txt"
            ) { result in
                if case .failure(let error) = result {
                    viewModel.errorMessage = "Errore durante l'esportazione: \(error.localizedDescription)"
                }
            }
            .dropDestination(for: URL.self) { items, location in
                guard let url = items.first else { return false }
                
                // Verifichiamo che sia un PDF (estensione o tipo)
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
}

#Preview {
    ContentView()
}
