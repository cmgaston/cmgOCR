
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
                defaultFilename: (viewModel.selectedURL?.deletingPathExtension().lastPathComponent ?? "extracted_text")
            ) { result in
                if case .failure(let error) = result {
                    viewModel.errorMessage = String(localized: "Error during export: \(error.localizedDescription)")
                }
            }
            .dropDestination(for: URL.self) { items, location in
                guard let url = items.first else { return false }
                let allowedExtensions = ["pdf", "png", "jpg", "jpeg", "tiff", "bmp"]
                if allowedExtensions.contains(url.pathExtension.lowercased()) {
                    viewModel.selectFile(at: url)
                    return true
                }
                return false
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.selectFile(at: url)
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
            if viewModel.isImageFile, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            } else {
                PDFKitRepresentedView(url: url)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
            
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
            Text("Processing... \(viewModel.progress, format: .percent)")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyOCRView: some View {
        ContentUnavailableView {
            Label("Ready for OCR", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("Click 'Start OCR' to extract text from the document.")
        } actions: {
            Button("Start OCR") {
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
                Text("Export Text")
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
            Label("No Document", systemImage: "doc.viewfinder")
        } description: {
            Text("Drag or select a PDF or Image file to start.")
        } actions: {
            Button("Select File") { isImporterPresented = true }
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
        if viewModel.selectedURL != nil {
            ToolbarItem(placement: .navigation) {
                Button(action: { viewModel.closeFile() }) {
                    Label("Close File", systemImage: "xmark")
                }
                .disabled(viewModel.isProcessing)
                .help("Close current file")
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: { isImporterPresented = true }) {
                Label("Change File", systemImage: "doc.badge.plus")
            }
            .disabled(viewModel.isProcessing)
        }
        
        if viewModel.selectedURL != nil && !viewModel.isProcessing {
            ToolbarItem(placement: .primaryAction) {
                if viewModel.recognizedText.isEmpty {
                    Button("Start OCR") { Task { await viewModel.startOCR() } }
                        .keyboardShortcut("R", modifiers: .command)
                } else {
                    Button("Export") { isExporting = true }
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
                Label("Copy Text", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.recognizedText.isEmpty)
        }
    }
}

