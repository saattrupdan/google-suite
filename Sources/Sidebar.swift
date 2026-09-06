import AppKit

/// The icon-only rail on the left: Mail and Calendar, nothing else.
///
/// Deliberately not a source list with rows and labels, and deliberately not a
/// tab bar — two fixed destinations that you switch between without thinking.
///
/// Laid out with frames, like the rest of the window: inserting constraints
/// after the window is on screen makes AppKit re-derive the window frame from
/// the content view's fitting size, and nothing here has an intrinsic size.
final class Sidebar: NSVisualEffectView {
    struct Item {
        let source: Source
        let button: NSButton
        let badge: BadgeView
        let container: NSView
    }

    private(set) var items: [Item] = []
    var onSelect: ((String) -> Void)?

    /// Room for the traffic lights, which sit on top of the rail now that the
    /// window has no title bar.
    static let topInset: CGFloat = 34
    static let itemSize = NSSize(width: 40, height: 34)
    static let spacing: CGFloat = 6
    static let width: CGFloat = 56

    init(sources: [Source]) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 600))
        material = .sidebar
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        translatesAutoresizingMaskIntoConstraints = false
        for source in sources { addItem(source) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func addItem(_ source: Source) {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = false

        let button = NSButton(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: source.symbol, accessibilityDescription: source.label)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        button.contentTintColor = Self.tint(forSelected: false)
        button.target = self
        button.action = #selector(clicked(_:))
        button.identifier = NSUserInterfaceItemIdentifier(source.id)
        button.toolTip = source.label
        button.focusRingType = .none
        container.addSubview(button)

        let badge = BadgeView(frame: .zero)
        container.addSubview(badge)
        addSubview(container)
        items.append(Item(source: source, button: button, badge: badge, container: container))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let x = (bounds.width - Self.itemSize.width) / 2
        // Top-down: the first item sits below the window buttons.
        var y = bounds.height - Self.topInset - Self.itemSize.height
        for item in items {
            item.container.frame = NSRect(x: x, y: y, width: Self.itemSize.width, height: Self.itemSize.height)
            item.button.frame = item.container.bounds
            layout(badge: item.badge, in: item.container)
            y -= Self.itemSize.height + Self.spacing
        }
    }

    /// The badge sits inside the container's corner — a badge hanging over the
    /// edge is what got clipped against the rail.
    private func layout(badge: BadgeView, in container: NSView) {
        guard !badge.isHidden else { return }
        let width = badge.intrinsicWidth
        badge.frame = NSRect(x: container.bounds.maxX - width - 1,
                             y: container.bounds.maxY - badge.height - 1,
                             width: width, height: badge.height)
    }

    @objc private func clicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onSelect?(id)
    }

    /// Blue means "this is what you are looking at": the selected icon takes the
    /// accent colour and sits on a faint accent pill; everything else recedes.
    static func tint(forSelected: Bool) -> NSColor {
        forSelected ? .controlAccentColor : .secondaryLabelColor
    }

    func setSelected(id: String) {
        for item in items { style(item, selected: item.source.id == id) }
    }

    /// Split view shows both surfaces at once, so both icons are "shown".
    func setShown(ids: Set<String>) {
        for item in items { style(item, selected: ids.contains(item.source.id)) }
    }

    private func style(_ item: Item, selected: Bool) {
        item.button.state = selected ? .on : .off
        item.button.contentTintColor = Self.tint(forSelected: selected)
        item.container.layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
        item.button.toolTip = selected ? "\(item.source.label) (shown)" : item.source.label
    }

    func setBadge(_ count: Int?, id: String) {
        guard let item = items.first(where: { $0.source.id == id }) else { return }
        item.badge.setCount(count)
        needsLayout = true
    }
}

/// The unread count on the icon's corner.
final class BadgeView: NSTextField {
    var height: CGFloat { 15 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isBordered = false
        drawsBackground = false
        isSelectable = false
        font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        textColor = .white
        alignment = .center
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.cornerRadius = height / 2
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.windowBackgroundColor.cgColor
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Wide enough for the text plus breathing room, so the digits are never
    /// clipped by the pill's edge.
    var intrinsicWidth: CGFloat {
        let text = stringValue.isEmpty ? "8" : stringValue
        let textWidth = (text as NSString).size(withAttributes: [.font: font as Any]).width
        return max(18, (textWidth as CGFloat).rounded(.up) + 10)
    }

    func setCount(_ count: Int?) {
        guard let count, count > 0 else {
            isHidden = true
            setAccessibilityLabel(nil)
            return
        }
        stringValue = count > 99 ? "99+" : "\(count)"
        isHidden = false
        setAccessibilityLabel("\(count) unread")
    }
}
