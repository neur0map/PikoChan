import SwiftUI
import AppKit

/// A lightweight NSTextField wrapper that avoids the ViewBridge/text-service
/// errors SwiftUI's TextField triggers inside borderless floating panels.
///
/// Disables autocorrect, spell-check, and text completion so macOS never
/// attempts to open ViewBridge connections to remote input services.
struct PikoTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .regular)
        field.textColor = .white
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail

        // Disable text completion on the field itself.
        field.isAutomaticTextCompletionEnabled = false
        (field.cell as? NSTextFieldCell)?.allowsEditingTextAttributes = false

        // Become first responder after a brief delay so the panel is ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PikoTextField

        init(_ parent: PikoTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
