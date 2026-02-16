
//
//  ContentView.swift
//  cmgOCR
//
//  Created by Cristiano M. Gaston on 23/01/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel: OCRViewModel

    init(viewModel: OCRViewModel = OCRViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }
    @State private var isImporterPresented = false
    @State private var isExporting = false
    @State private var selectedRange = NSRange(location: 0, length: 0)
    
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
            .navigationTitle(viewModel.selectedURL?.lastPathComponent ?? "cmgOCR")
            .toolbar { toolbarContent }
            .fileExporter(
                isPresented: $isExporting,
                document: TextDocument(text: viewModel.recognizedText),
                contentTypes: [TextDocument.markdownType, .rtf],
                defaultFilename: (viewModel.selectedURL?.deletingPathExtension().lastPathComponent ?? "testo_estratto")
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
            Text("Analisi in corso... \(viewModel.progress, format: .percent)")
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
            FormattingToolbar(text: $viewModel.recognizedText, selectedRange: $selectedRange)
            Divider()
            MacTextEditor(text: $viewModel.recognizedText, selectedRange: $selectedRange)
                .background(Color(NSColor.textBackgroundColor))
            Divider()
            exportButton
        }
    }
    
    private var exportButton: some View {
        Button(action: { isExporting = true }) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Esporta il testo")
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
