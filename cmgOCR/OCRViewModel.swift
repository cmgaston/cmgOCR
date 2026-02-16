
import SwiftUI
import PDFKit
import Vision

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
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        
        // Verifichiamo se il file è leggibile.
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
            errorMessage = String(localized: "Access error: the file is not readable.")
        }
    }
    
    deinit {
        selectedURL?.stopAccessingSecurityScopedResource()
    }

    func startOCR() async {
        guard let url = selectedURL else { return }
        
        isProcessing = true
        errorMessage = nil
        recognizedText = ""
        progress = 0.0
        
        do {
            guard let document = PDFDocument(url: url) else {
                throw NSError(domain: "cmgOCR", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "The file is not a valid PDF.")])
            }
            
            let pageCount = document.pageCount
            var accumulatedText = ""
            
            for i in 0..<pageCount {
                guard let page = document.page(at: i) else { continue }
                if let image = pageToImage(page) {
                    let pageText = try await recognizeTextWithElements(in: image)
                    let pageHeader = String.localizedStringWithFormat(String(localized: "--- PAGE %lld ---\n\n"), i + 1)
                    accumulatedText += pageHeader + pageText + "\n\n"
                }
                
                await MainActor.run {
                    progress = Double(i + 1) / Double(pageCount)
                }
            }
            
            recognizedText = accumulatedText
        } catch {
            errorMessage = String(localized: "Error: \(error.localizedDescription)")
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
