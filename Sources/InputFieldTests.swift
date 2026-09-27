import Foundation
import ApplicationServices

/// Offline regression fixtures: no app activation, clipboard, keys or model calls.
enum InputFieldTests {
    struct Node {
        var role: String = kAXGroupRole
        var value: String? = nil
        var range: String? = nil
        var children: [Int] = []
        var secure = false
        var hidden = false
        var focused = false
    }
    struct Tree: InputTree {
        var nodes: [Int: Node]
        func string(_ n: Int, _ a: String) -> String {
            if a == kAXRoleAttribute { return nodes[n]?.role ?? "" }
            if a == kAXSubroleAttribute, nodes[n]?.secure == true { return kAXSecureTextFieldSubrole }
            return ""
        }
        func flag(_ n: Int, _ a: String) -> Bool? {
            if a == kAXHiddenAttribute { return nodes[n]?.hidden }
            if a == kAXFocusedAttribute { return nodes[n]?.focused }
            return nil
        }
        func element(_ n: Int, _ a: String) -> Int? {
            a == kAXParentAttribute ? nodes.first(where: { $0.value.children.contains(n) })?.key : nil
        }
        func children(_ n: Int) -> [Int] { nodes[n]?.children ?? [] }
        func same(_ a: Int, _ b: Int) -> Bool { a == b }
        func text(_ n: Int) -> String? { nodes[n]?.value }
        func rangeText(_ n: Int) -> String? { nodes[n]?.range }
    }
    static func run() {
        let message = "[Jev] Check the entire insertion, including the final paragraph."
        var tree = Tree(nodes: [
            0: Node(role: kAXWindowRole, children: [1, 2]),
            1: Node(role: kAXStaticTextRole, value: message), // same words in history are not evidence
            2: Node(role: kAXTextAreaRole, value: "", children: [3]),
            3: Node(children: [4]),
            4: Node(role: kAXStaticTextRole, value: message)
        ])
        precondition(InputResolver.field(window: 0, focused: nil, in: tree) == 2)
        precondition(InputResolver.field(window: 0, focused: 4, in: tree) == 2)
        precondition(InputResolver.read(2, in: tree) == message)
        tree.nodes[2]?.children = []
        precondition(InputResolver.read(2, in: tree) == "") // history must not fill an empty editor
        tree.nodes[2]?.value = nil
        precondition(InputResolver.read(2, in: tree) == nil) // unknown must not mean sent
        tree.nodes[2]?.range = message
        precondition(InputResolver.read(2, in: tree) == message)
        tree.nodes[0]?.children.append(5)
        tree.nodes[5] = Node(role: kAXTextFieldRole, value: "search")
        precondition(InputResolver.field(window: 0, focused: nil, in: tree) == nil)
        precondition(InputResolver.field(window: 0, focused: 2, in: tree) == 2)
        tree.nodes[2]?.focused = true
        precondition(InputResolver.field(window: 0, focused: nil, in: tree) == 2)
        tree.nodes[2]?.secure = true
        precondition(InputResolver.field(window: 0, focused: 2, in: tree) == nil)
        precondition(InputResolver.read(2, in: tree) == nil)
        tree.nodes[2]?.secure = false; tree.nodes[2]?.hidden = true
        precondition(InputResolver.field(window: 0, focused: nil, in: tree) == 5)
        precondition(InputResolver.contains("First paragraph\nSecond café", in: "First paragraph\u{00a0}Second cafe\u{0301}"))
        precondition(!InputResolver.contains(message, in: String(message.prefix(30))))
        precondition(!InputResolver.contains("  ", in: message))
        print("PASS: missing/child focus, rich editor text, ambiguous fields, hidden/secure fields, unreadable vs empty, full paste confirmation.")
    }
}
