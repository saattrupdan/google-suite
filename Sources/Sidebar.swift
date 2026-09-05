import AppKit

/// The icon-only rail on the left: Mail and Calendar, nothing else.
///
/// Deliberately not a source list with rows and labels, and deliberately not a
/// tab bar — two fixed destinations that you switch between without thinking.
final class Sidebar: NSVisualEffectView {
    struct Item {
        let source: Source
        let button: NSButton
        let badge: BadgeView
    }

    private(set) var items: [Item] = []
    var onSelect: ((String) -> Void)?

    private let stack = NSStackView()

    init(sources: [Source]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 56, height: 600))
        material = .sidebar
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 56),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
        ])

        for source in sources { addItem(source) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func addItem(_ source: Source) {
        let button = NSButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .texturedRounded
        button.setButtonType(.pushOnPushOff)
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: source.symbol, accessibilityDescription: source.label)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        button.target = self
        button.action = #selector(clicked(_:))
        button.identifier = NSUserInterfaceItemIdentifier(source.id)
        button.toolTip = source.label
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = 8

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let badge = BadgeView()
        container.addSubview(button)
        container.addSubview(badge)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 40),
            container.heightAnchor.constraint(equalToConstant: 34),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 28),
            badge.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 2),
            badge.topAnchor.constraint(equalTo: container.topAnchor, constant: -2),
        ])
        stack.addArrangedSubview(container)
        items.append(Item(source: source, button: button, badge: badge))
    }

    @objc private func clicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onSelect?(id)
    }

    func setSelected(id: String) {
        for item in items { item.button.state = item.source.id == id ? .on : .off }
    }

    /// A count of 0 hides the badge entirely.
    func setBadge(_ count: Int?, id: String) {
        guard let item = items.first(where: { $0.source.id == id }) else { return }
        item.badge.setCount(count)
    }

    func button(for id: String) -> NSButton? {
        items.first(where: { $0.source.id == id })?.button
    }
}

/// Red pill with an unread count, capped at 99+ like every other Mac app.
final class BadgeView: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        isEditable = false
        isBordered = false
        drawsBackground = false
        isSelectable = false
        font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        textColor = .white
        alignment = .center
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemRed.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.windowBackgroundColor.cgColor
        isHidden = true
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 14),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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
