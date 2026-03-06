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

    static let maxCharacters = 2000

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PikoTextField

        init(_ parent: PikoTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            // Enforce character limit.
            if field.stringValue.count > PikoTextField.maxCharacters {
                field.stringValue = String(field.stringValue.prefix(PikoTextField.maxCharacters))
            }
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

// MARK: - Secure Text Field

/// Masking text field — regular NSTextField that displays bullets instead of text.
/// NSSecureTextField has broken delegate/notification behavior in .screenSaver-level
/// panels (binding never syncs). This uses a plain NSTextField with a custom formatter
/// that stores the real value while displaying bullets.
struct PikoSecureField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = .white
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.lineBreakMode = .byTruncatingTail
        field.isAutomaticTextCompletionEnabled = false
        (field.cell as? NSTextFieldCell)?.allowsEditingTextAttributes = false

        context.coordinator.field = field

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let masked = String(repeating: "\u{2022}", count: text.count)
        if field.currentEditor() == nil && field.stringValue != masked {
            field.stringValue = masked
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PikoSecureField
        weak var field: NSTextField?
        /// The actual unmasked text. We track it here because the field only shows bullets.
        private var realText: String = ""

        init(_ parent: PikoSecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let displayed = field.stringValue
            let bullet = "\u{2022}"

            // Figure out what changed: user may have typed, pasted, or deleted.
            // Bullets are our masked chars; any non-bullet char is new input.
            var newReal = ""
            var realIndex = realText.startIndex
            for char in displayed {
                if String(char) == bullet && realIndex < realText.endIndex {
                    // Existing masked character — keep original
                    newReal.append(realText[realIndex])
                    realIndex = realText.index(after: realIndex)
                } else if String(char) != bullet {
                    // New character typed/pasted
                    newReal.append(char)
                }
                // Skip extra bullets beyond realText length (shouldn't happen)
            }

            realText = newReal
            parent.text = realText

            // Re-mask the display
            let masked = String(repeating: bullet, count: realText.count)
            if field.stringValue != masked {
                // Preserve cursor position
                let editor = field.currentEditor()
                let cursorPos = editor?.selectedRange.location ?? masked.count
                field.stringValue = masked
                editor?.selectedRange = NSRange(location: min(cursorPos, masked.count), length: 0)
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            field.stringValue = String(repeating: "\u{2022}", count: realText.count)
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
