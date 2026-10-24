import AppKit
import SwiftUI

nonisolated enum CodeLanguage { case css, javascript }

/// Lightweight code editor: NSTextView + regex highlighting + line numbers.
/// Deliberately dependency-free; good enough for theme CSS and short scripts.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let language: CodeLanguage
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = CodeTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        scroll.documentView = textView
        let ruler = LineNumberRulerView(textView: textView)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        tv.isEditable = isEditable
        if tv.string != text && !context.coordinator.isEditing {
            tv.string = text
            context.coordinator.highlight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: NSTextView?
        var isEditing = false
        private let debouncer = Debouncer(delay: .milliseconds(120))

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            isEditing = true
            parent.text = tv.string
            isEditing = false
            debouncer.call { [weak self] in self?.highlight() }
            (tv.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
        }

        func highlight() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            SyntaxHighlighter.apply(to: storage, language: parent.language, dark: tv.effectiveAppearance.isDark)
        }
    }
}

final class CodeTextView: NSTextView {
    override func insertTab(_ sender: Any?) { insertText("  ", replacementRange: selectedRange()) }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        (delegate as? CodeEditorView.Coordinator)?.highlight()
    }
}

// MARK: - Highlighter

enum SyntaxHighlighter {
    private struct Rule { let regex: NSRegularExpression; let color: (Bool) -> NSColor }

    private static func rx(_ p: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: opts)
    }

    private static let cssRules: [Rule] = [
        Rule(regex: rx(#"[^{}/;]+(?=\s*\{)"#), color: { $0 ? NSColor(red: 0.98, green: 0.78, blue: 0.5, alpha: 1) : NSColor(red: 0.6, green: 0.3, blue: 0.0, alpha: 1) }),
        Rule(regex: rx(#"(?<=[{;\n])\s*[-\w]+(?=\s*:)"#), color: { $0 ? NSColor(red: 0.6, green: 0.8, blue: 1, alpha: 1) : NSColor(red: 0.1, green: 0.35, blue: 0.7, alpha: 1) }),
        Rule(regex: rx(#"--[\w-]+"#), color: { $0 ? NSColor(red: 0.75, green: 0.65, blue: 1, alpha: 1) : NSColor(red: 0.45, green: 0.25, blue: 0.75, alpha: 1) }),
        Rule(regex: rx(#"#[0-9a-fA-F]{3,8}\b|\b\d+(\.\d+)?(px|em|rem|%|vh|vw|ms|s|deg)?\b"#), color: { $0 ? NSColor(red: 0.7, green: 0.9, blue: 0.7, alpha: 1) : NSColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1) }),
        Rule(regex: rx(#"!important|@[\w-]+"#), color: { _ in NSColor(red: 0.85, green: 0.35, blue: 0.4, alpha: 1) }),
        Rule(regex: rx(#""[^"\n]*"|'[^'\n]*'"#), color: { $0 ? NSColor(red: 0.85, green: 0.6, blue: 0.5, alpha: 1) : NSColor(red: 0.65, green: 0.2, blue: 0.15, alpha: 1) }),
        Rule(regex: rx(#"/\*[\s\S]*?\*/"#), color: { $0 ? NSColor(white: 0.5, alpha: 1) : NSColor(white: 0.55, alpha: 1) })
    ]

    private static let jsRules: [Rule] = [
        Rule(regex: rx(#"\b(const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|new|delete|typeof|instanceof|in|of|class|extends|super|this|try|catch|finally|throw|async|await|yield|import|export|default|static|get|set|void|null|undefined|true|false)\b"#), color: { $0 ? NSColor(red: 0.98, green: 0.55, blue: 0.65, alpha: 1) : NSColor(red: 0.65, green: 0.1, blue: 0.45, alpha: 1) }),
        Rule(regex: rx(#"\b\d+(\.\d+)?\b"#), color: { $0 ? NSColor(red: 0.7, green: 0.9, blue: 0.7, alpha: 1) : NSColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1) }),
        Rule(regex: rx(#"[A-Za-z_$][\w$]*(?=\s*\()"#), color: { $0 ? NSColor(red: 0.6, green: 0.8, blue: 1, alpha: 1) : NSColor(red: 0.1, green: 0.35, blue: 0.7, alpha: 1) }),
        Rule(regex: rx(#""(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`"#), color: { $0 ? NSColor(red: 0.85, green: 0.6, blue: 0.5, alpha: 1) : NSColor(red: 0.65, green: 0.2, blue: 0.15, alpha: 1) }),
        Rule(regex: rx(#"//[^\n]*|/\*[\s\S]*?\*/"#), color: { $0 ? NSColor(white: 0.5, alpha: 1) : NSColor(white: 0.55, alpha: 1) })
    ]

    static func apply(to storage: NSTextStorage, language: CodeLanguage, dark: Bool) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length < 400_000 else { return }
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.foregroundColor, value: dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.12, alpha: 1), range: full)
        storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular), range: full)
        let rules = language == .css ? cssRules : jsRules
        let s = storage.string as NSString
        for rule in rules {
            for m in rule.regex.matches(in: s as String, range: full) {
                storage.addAttribute(.foregroundColor, value: rule.color(dark), range: m.range)
            }
        }
        storage.endEditing()
    }
}

// MARK: - Line numbers

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView)
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let container = tv.textContainer else { return }
        let dark = effectiveAppearance.isDark
        (dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: dark ? NSColor(white: 0.45, alpha: 1) : NSColor(white: 0.6, alpha: 1)
        ]
        let visible = tv.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: container)
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let text = tv.string as NSString
        var lineNumber = 1
        var index = 0
        while index < charRange.location { index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0))); lineNumber += 1 }
        index = charRange.location
        while index < NSMaxRange(charRange) || (index == 0 && text.length == 0) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let gr = lm.glyphRange(forCharacterRange: NSRange(location: lineRange.location, length: 0), actualCharacterRange: nil)
            let lineRect = lm.lineFragmentRect(forGlyphAt: min(gr.location, max(0, lm.numberOfGlyphs - 1)), effectiveRange: nil)
            let y = lineRect.minY - visible.minY + tv.textContainerInset.height
            let str = "\(lineNumber)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + (lineRect.height - size.height) / 2), withAttributes: attrs)
            lineNumber += 1
            if lineRange.length == 0 { break }
            index = NSMaxRange(lineRange)
            if index >= text.length { break }
        }
    }
}
