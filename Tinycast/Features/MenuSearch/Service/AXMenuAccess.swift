// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
@preconcurrency import ApplicationServices

/// Every menu-bar `AXUIElement` read in the feature: no actor state, so the walk runs off-main.
enum AXMenuAccess {
    /// A hung target must not stall the summon; per element, matching the window sweep.
    static let sweepTimeout: Float = 0.2
    /// One budget for the whole walk; a huge bar truncates rather than delays the list.
    static let walkBudget: Duration = .seconds(1)

    static func application(for pid: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, sweepTimeout)
        return application
    }

    static func readTopLevel(
        in application: AXUIElement, deadline: ContinuousClock.Instant
    ) -> [MenuTreeNode] {
        guard let bar = element(application, kAXMenuBarAttribute) else { return [] }
        return readNodes(children(of: bar), deadline: deadline)
    }

    /// The live element behind a snapshot row, matched by path; nil when the menu moved on.
    static func resolveLeaf(
        in application: AXUIElement, path: [String], title: String
    ) -> AXUIElement? {
        guard let bar = element(application, kAXMenuBarAttribute) else { return nil }
        return resolve(candidates: children(of: bar), trail: [], path: path, title: title)
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// A resolved leaf is still worth pressing: enabled, visible, and pressable right now.
    static func isActionable(_ element: AXUIElement) -> Bool {
        guard bool(element, kAXEnabledAttribute) != false,
            bool(element, kAXHiddenAttribute) != true
        else { return false }
        return canPress(element)
    }

    // MARK: - Reading

    private static func readNodes(
        _ candidates: [AXUIElement], deadline: ContinuousClock.Instant
    ) -> [MenuTreeNode] {
        var nodes: [MenuTreeNode] = []
        nodes.reserveCapacity(candidates.count)
        for child in candidates {
            guard ContinuousClock.now < deadline else { return nodes }
            AXUIElementSetMessagingTimeout(child, sweepTimeout)
            let nested = children(of: child)
            let title = string(child, kAXTitleAttribute) ?? ""
            guard !nested.isEmpty else {
                nodes.append(readLeaf(child, title: title))
                continue
            }
            nodes.append(MenuTreeNode(title: title, children: readNodes(nested, deadline: deadline)))
        }
        return nodes
    }

    private static func readLeaf(_ element: AXUIElement, title: String) -> MenuTreeNode {
        let details = batch(element)
        return MenuTreeNode(
            title: title,
            isEnabled: details.enabled ?? true,
            isHidden: details.hidden ?? false,
            canPress: canPress(element),
            shortcut: .commandEquivalent(
                character: details.character ?? "", modifiers: details.modifiers ?? 0),
            children: [])
    }

    /// One round trip for the leaf's value reads, falling back to single reads as a unit.
    private static func batch(
        _ element: AXUIElement
    ) -> (
        enabled: Bool?, hidden: Bool?, character: String?, modifiers: Int?
    ) {
        let names =
            [
                kAXEnabledAttribute, kAXHiddenAttribute, kAXMenuItemCmdCharAttribute,
                kAXMenuItemCmdModifiersAttribute
            ] as CFArray
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &values) == .success,
            let values = values as? [Any], values.count == 4
        else {
            return (
                bool(element, kAXEnabledAttribute), bool(element, kAXHiddenAttribute),
                string(element, kAXMenuItemCmdCharAttribute),
                (attribute(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue
            )
        }
        return (
            values[0] as? Bool, values[1] as? Bool, values[2] as? String,
            (values[3] as? NSNumber)?.intValue
        )
    }

    private static func canPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        return AXUIElementCopyActionNames(element, &actions) == .success
            && (actions as? [String])?.contains(kAXPressAction) == true
    }

    // MARK: - Resolving

    /// Mirrors the snapshot walk level for level, so a displayed row always resolves.
    private static func resolve(
        candidates: [AXUIElement], trail: [String], path: [String], title: String
    ) -> AXUIElement? {
        for child in candidates {
            let childTitle = string(child, kAXTitleAttribute) ?? ""
            let nested = children(of: child)
            guard !nested.isEmpty else {
                if trail == path, childTitle == title { return child }
                continue
            }
            var subtrail = trail
            if !childTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                subtrail.append(childTitle)
            }
            guard subtrail.count <= path.count,
                Array(path.prefix(subtrail.count)) == subtrail,
                let found = resolve(
                    candidates: nested, trail: subtrail, path: path, title: title)
            else { continue }
            return found
        }
        return nil
    }

    // MARK: - Primitives

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = self.attribute(element, attribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Type checked by CFGetTypeID above; `as?` on a CF type is a compile error.
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        self.attribute(element, attribute) as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        self.attribute(element, attribute) as? Bool
    }

    private static func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }
}
