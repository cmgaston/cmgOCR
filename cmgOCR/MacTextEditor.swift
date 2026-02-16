
import SwiftUI
import AppKit

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
