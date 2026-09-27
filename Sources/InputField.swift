import AppKit
import ApplicationServices

/// Electron can expose a focused child (or no focused element) instead of its editor.
/// Resolve only editable controls in the active window, never text in the conversation.
protocol InputTree {
    associatedtype Node
    func string(_ node: Node, _ attribute: String) -> String
    func flag(_ node: Node, _ attribute: String) -> Bool?
    func element(_ node: Node, _ attribute: String) -> Node?
    func children(_ node: Node) -> [Node]
    func same(_ a: Node, _ b: Node) -> Bool
    func text(_ node: Node) -> String?
    func rangeText(_ node: Node) -> String?
}

enum InputResolver {
    static func editable<T: InputTree>(_ node: T.Node, in tree: T) -> Bool {
        [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(tree.string(node, kAXRoleAttribute)) &&
        tree.string(node, kAXSubroleAttribute) != kAXSecureTextFieldSubrole &&
        tree.flag(node, kAXEnabledAttribute) != false && tree.flag(node, kAXHiddenAttribute) != true
    }

    static func field<T: InputTree>(window: T.Node, focused: T.Node?, in tree: T) -> T.Node? {
        // A focus pointer can point inside the editor. Reject pointers outside this window.
        if var node = focused {
            var editor: T.Node?
            for _ in 0..<64 {
                if tree.string(node, kAXSubroleAttribute) == kAXSecureTextFieldSubrole || tree.flag(node, kAXHiddenAttribute) == true { return nil }
                if editor == nil, editable(node, in: tree) { editor = node }
                if tree.same(node, window) { if let editor { return editor }; break }
                guard let parent = tree.element(node, kAXParentAttribute) else { break }
                node = parent
            }
        }
        var fields: [T.Node] = [], marked: [T.Node] = []
        var stack: [(T.Node, Int)] = [(window, 0)], visited = 0
        while let (node, depth) = stack.popLast() {
            visited += 1
            guard visited <= 3000, depth <= 60 else { return nil } // incomplete scan is not proof
            if tree.flag(node, kAXHiddenAttribute) == true || tree.string(node, kAXSubroleAttribute) == kAXSecureTextFieldSubrole { continue }
            if editable(node, in: tree) {
                fields.append(node)
                if tree.flag(node, kAXFocusedAttribute) == true { marked.append(node) }
            } else {
                stack += tree.children(node).reversed().map { ($0, depth + 1) }
            }
        }
        if marked.count == 1 { return marked[0] }
        return fields.count == 1 ? fields[0] : nil
    }

    static func read<T: InputTree>(_ node: T.Node, in tree: T) -> String? {
        guard editable(node, in: tree) else { return nil }
        if let value = tree.text(node), !value.isEmpty { return value }
        if let value = tree.rangeText(node) { return value }
        // Traverse this editor only. History, titles, labels and placeholders are not input.
        var pieces: [String] = [], stack = [(node, 0)], visited = 0
        while let (child, depth) = stack.popLast() {
            visited += 1
            guard visited <= 1000, depth <= 30 else { return nil }
            if tree.string(child, kAXSubroleAttribute) == kAXSecureTextFieldSubrole || tree.flag(child, kAXHiddenAttribute) == true { continue }
            if tree.string(child, kAXRoleAttribute) == kAXStaticTextRole,
               let value = tree.text(child), !value.isEmpty { pieces.append(value) }
            else { stack += tree.children(child).reversed().map { ($0, depth + 1) } }
        }
        if !pieces.isEmpty { return pieces.joined(separator: "\n") }
        return tree.text(node) // nil is unknown, a real empty AXValue is empty
    }

    static func contains(_ expected: String, in actual: String) -> Bool {
        func normalized(_ s: String) -> String {
            s.precomposedStringWithCanonicalMapping.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        let wanted = normalized(expected)
        return !wanted.isEmpty && normalized(actual).contains(wanted)
    }
}

struct AXInputTree: InputTree {
    func string(_ node: AXUIElement, _ attribute: String) -> String { AX.string(node, attribute) }
    func flag(_ node: AXUIElement, _ attribute: String) -> Bool? { AX.value(node, attribute) as? Bool }
    func element(_ node: AXUIElement, _ attribute: String) -> AXUIElement? { AX.element(node, attribute) }
    func children(_ node: AXUIElement) -> [AXUIElement] { AX.children(node) }
    func same(_ a: AXUIElement, _ b: AXUIElement) -> Bool { CFEqual(a, b) }
    func text(_ node: AXUIElement) -> String? { AX.value(node, kAXValueAttribute) as? String }
    func rangeText(_ node: AXUIElement) -> String? {
        guard let count = AX.value(node, kAXNumberOfCharactersAttribute) as? Int, count > 0, count <= 1_000_000 else { return nil }
        var range = CFRange(location: 0, length: count)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(node, kAXStringForRangeParameterizedAttribute as CFString, parameter, &result) == .success else { return nil }
        return result as? String
    }
}

struct InputField {
    let pid: pid_t
    let window: AXUIElement
    let element: AXUIElement

    static func current() -> InputField? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = AX.element(root, kAXFocusedWindowAttribute) ?? AX.element(root, kAXMainWindowAttribute) else { return nil }
        var focused = AX.element(root, kAXFocusedUIElementAttribute)
        if focused == nil, let systemFocus = AX.element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) {
            var pid: pid_t = 0
            if AXUIElementGetPid(systemFocus, &pid) == .success, pid == app.processIdentifier { focused = systemFocus }
        }
        guard let field = InputResolver.field(window: window, focused: focused, in: AXInputTree()) else { return nil }
        return InputField(pid: app.processIdentifier, window: window, element: field)
    }

    func read() -> String? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
        let root = AXUIElementCreateApplication(pid)
        guard let currentWindow = AX.element(root, kAXFocusedWindowAttribute) ?? AX.element(root, kAXMainWindowAttribute),
              CFEqual(window, currentWindow),
              let currentField = InputResolver.field(window: window, focused: AX.element(root, kAXFocusedUIElementAttribute), in: AXInputTree()),
              CFEqual(element, currentField) else { return nil }
        return InputResolver.read(element, in: AXInputTree())
    }
}
