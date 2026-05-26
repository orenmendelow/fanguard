import Cocoa
import Foundation
import UserNotifications

// MARK: - XPC Writer (MFC helper)

private let smcWriteQueue = DispatchQueue(label: "com.local.fanguard.smcwrite")

func smcWrite(_ key: String, _ value: String) {
    smcWriteQueue.async {
        let svc = "com.crystalidea.macsfancontrol.smcwrite"
        let c = xpc_connection_create_mach_service(svc, nil, UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED))
        xpc_connection_set_event_handler(c) { _ in }; xpc_connection_resume(c)
        let o = xpc_dictionary_create(nil, nil, 0); xpc_dictionary_set_string(o, "command", "open")
        let _ = xpc_connection_send_message_with_reply_sync(c, o)
        let w = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(w, "command", "write")
        xpc_dictionary_set_string(w, "key", key)
        xpc_dictionary_set_string(w, "value", value)
        let _ = xpc_connection_send_message_with_reply_sync(c, w)
        let cl = xpc_dictionary_create(nil, nil, 0); xpc_dictionary_set_string(cl, "command", "close")
        let _ = xpc_connection_send_message_with_reply_sync(c, cl)
        xpc_connection_cancel(c)
    }
}

func floatHex(_ v: Float) -> String {
    var f = v; var b = [UInt8](repeating: 0, count: 4); memcpy(&b, &f, 4)
    return b.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Thermal State

func thermalLabel() -> (String, NSColor) {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return ("OK", .systemGreen)
    case .fair:    return ("Fair", .systemYellow)
    case .serious: return ("Hot", .systemOrange)
    case .critical: return ("Crit", .systemRed)
    @unknown default: return ("--", .secondaryLabelColor)
    }
}

// MARK: - Fan Mode

enum FanMode: Int { case auto = 0; case manual = 1; case off = 2 }

// MARK: - Per-Fan Control View

class FanView: NSView {
    let fanIndex: Int
    let nameLabel: NSTextField
    let rpmLabel: NSTextField
    let dot: NSView
    let seg: NSSegmentedControl
    let slider: NSSlider
    let sliderLabel: NSTextField
    var sliderRow: NSView!

    var mode: FanMode = .auto
    var manualRPM: Float = 2500
    var onChanged: (() -> Void)?

    var heightWithSlider: NSLayoutConstraint!
    var heightWithoutSlider: NSLayoutConstraint!

    init(name: String, index: Int, defaultMode: FanMode) {
        fanIndex = index
        mode = defaultMode

        dot = NSView(); dot.wantsLayer = true; dot.layer?.cornerRadius = 4
        nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        rpmLabel = NSTextField(labelWithString: "--")
        rpmLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        rpmLabel.alignment = .right

        seg = NSSegmentedControl(labels: ["Auto", "Manual", "Off"], trackingMode: .selectOne, target: nil, action: nil)
        seg.controlSize = .small
        seg.font = .systemFont(ofSize: 11)
        seg.selectedSegment = defaultMode.rawValue

        slider = NSSlider(value: 2500, minValue: 0, maxValue: 6800, target: nil, action: nil)
        slider.controlSize = .small
        sliderLabel = NSTextField(labelWithString: "2500")
        sliderLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        sliderLabel.alignment = .right

        super.init(frame: .zero)

        seg.target = self; seg.action = #selector(segChanged)
        slider.target = self; slider.action = #selector(sliderChanged)

        sliderRow = NSView()
        sliderRow.addSubview(slider)
        sliderRow.addSubview(sliderLabel)
        slider.translatesAutoresizingMaskIntoConstraints = false
        sliderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: sliderRow.leadingAnchor),
            slider.centerYAnchor.constraint(equalTo: sliderRow.centerYAnchor),
            slider.trailingAnchor.constraint(equalTo: sliderLabel.leadingAnchor, constant: -8),
            sliderLabel.trailingAnchor.constraint(equalTo: sliderRow.trailingAnchor),
            sliderLabel.centerYAnchor.constraint(equalTo: sliderRow.centerYAnchor),
            sliderLabel.widthAnchor.constraint(equalToConstant: 40),
            sliderRow.heightAnchor.constraint(equalToConstant: 20),
        ])

        for v: NSView in [dot, nameLabel, rpmLabel, seg, sliderRow!] {
            addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false
        }
        translatesAutoresizingMaskIntoConstraints = false

        heightWithSlider = heightAnchor.constraint(equalToConstant: 78)
        heightWithoutSlider = heightAnchor.constraint(equalToConstant: 56)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 280),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
            rpmLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rpmLabel.centerYAnchor.constraint(equalTo: dot.centerYAnchor),
            seg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
            seg.topAnchor.constraint(equalTo: dot.bottomAnchor, constant: 8),
            sliderRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
            sliderRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            sliderRow.topAnchor.constraint(equalTo: seg.bottomAnchor, constant: 6),
        ])

        updateSliderVisibility()
        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateSliderVisibility() {
        let show = mode == .manual
        sliderRow.isHidden = !show
        heightWithSlider.isActive = show
        heightWithoutSlider.isActive = !show
    }

    func updateDisplay() {
        let val: String
        let color: NSColor
        switch mode {
        case .off:
            val = "OFF"; color = .systemGray
        case .manual:
            val = "\(Int(manualRPM)) RPM"; color = .systemBlue
        case .auto:
            val = "Auto"; color = .systemGreen
        }
        rpmLabel.stringValue = val
        dot.layer?.backgroundColor = color.cgColor
    }

    @objc func segChanged() {
        mode = FanMode(rawValue: seg.selectedSegment) ?? .auto
        if mode == .manual {
            manualRPM = 2500
            slider.floatValue = manualRPM
            sliderLabel.stringValue = "\(Int(manualRPM))"
        }
        updateSliderVisibility()
        applyMode()
        updateDisplay()
        onChanged?()
        if let menu = enclosingMenuItem?.menu { menu.update() }
    }

    @objc func sliderChanged() {
        manualRPM = Float(slider.intValue)
        sliderLabel.stringValue = "\(Int(manualRPM))"
        applyMode()
        updateDisplay()
    }

    func applyMode() {
        switch mode {
        case .auto:
            smcWrite("F\(fanIndex)Md", "00")
        case .manual:
            smcWrite("F\(fanIndex)Md", "01")
            smcWrite("F\(fanIndex)Tg", floatHex(manualRPM))
        case .off:
            smcWrite("F\(fanIndex)Md", "01")
            smcWrite("F\(fanIndex)Tg", "00000000")
        }
    }
}

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var lastNotif: Date = .distantPast

    var fans: [FanView] = []
    var thermalLabel_: NSTextField!
    var thermalDot: NSView!
    var warningItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            let img = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            img?.isTemplate = true
            b.image = img
            b.imagePosition = .imageLeading
            b.title = " OK"
        }
        buildMenu()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        for fan in fans where fan.mode != .auto { fan.applyMode() }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func buildMenu() {
        menu = NSMenu()
        menu.minimumWidth = 280
        menu.autoenablesItems = false

        let left = FanView(name: "Left (dead)", index: 0, defaultMode: .off)
        let right = FanView(name: "Right", index: 1, defaultMode: .auto)
        left.onChanged = { [weak self] in self?.rebuildLayout() }
        right.onChanged = { [weak self] in self?.rebuildLayout() }
        fans = [left, right]

        for fan in fans {
            let item = NSMenuItem(); item.view = fan; menu.addItem(item)
        }

        let warnView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        warnView.wantsLayer = true
        warnView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor
        let warnIcon = NSImageView(frame: .zero)
        warnIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        warnIcon.contentTintColor = .systemRed
        let warnLabel = NSTextField(labelWithString: "No cooling — both fans off")
        warnLabel.font = .systemFont(ofSize: 11, weight: .medium)
        warnLabel.textColor = .systemRed
        for v: NSView in [warnIcon, warnLabel] {
            warnView.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            warnIcon.leadingAnchor.constraint(equalTo: warnView.leadingAnchor, constant: 20),
            warnIcon.centerYAnchor.constraint(equalTo: warnView.centerYAnchor),
            warnIcon.widthAnchor.constraint(equalToConstant: 16),
            warnLabel.leadingAnchor.constraint(equalTo: warnIcon.trailingAnchor, constant: 6),
            warnLabel.centerYAnchor.constraint(equalTo: warnView.centerYAnchor),
        ])
        warningItem = NSMenuItem()
        warningItem.view = warnView
        warningItem.isHidden = true
        menu.addItem(warningItem)

        menu.addItem(NSMenuItem.separator())

        // Thermal state row
        let tv = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        thermalDot = NSView(); thermalDot.wantsLayer = true; thermalDot.layer?.cornerRadius = 4
        let tn = NSTextField(labelWithString: "Thermal"); tn.font = .systemFont(ofSize: 12); tn.textColor = .secondaryLabelColor
        thermalLabel_ = NSTextField(labelWithString: "OK"); thermalLabel_.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        for v: NSView in [thermalDot, tn, thermalLabel_] {
            tv.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            thermalDot.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 20),
            thermalDot.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
            thermalDot.widthAnchor.constraint(equalToConstant: 8), thermalDot.heightAnchor.constraint(equalToConstant: 8),
            tn.leadingAnchor.constraint(equalTo: thermalDot.trailingAnchor, constant: 6),
            tn.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
            thermalLabel_.leadingAnchor.constraint(equalTo: tn.trailingAnchor, constant: 6),
            thermalLabel_.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
        ])
        let ti = NSMenuItem(); ti.view = tv; menu.addItem(ti)

        menu.addItem(NSMenuItem.separator())
        let q = NSMenuItem(title: "Quit FanGuard", action: #selector(quit), keyEquivalent: "q"); q.target = self
        menu.addItem(q)

        statusItem.menu = menu
    }

    func rebuildLayout() {
        for item in menu.items {
            if let fan = item.view as? FanView {
                let h = fan.mode == .manual ? 78.0 : 56.0
                fan.frame = NSRect(x: 0, y: 0, width: 280, height: h)
                fan.heightWithSlider.isActive = fan.mode == .manual
                fan.heightWithoutSlider.isActive = fan.mode != .manual
            }
        }
        menu.update()
    }

    func poll() {
        // Re-apply overrides every tick to survive thermalmonitord resets
        for fan in fans where fan.mode != .auto { fan.applyMode() }

        let allOff = fans.allSatisfy { $0.mode == .off }
        let (label, color) = thermalLabel()

        if let b = statusItem.button {
            let c: NSColor = allOff ? .systemRed : color == .systemRed ? .systemRed : .labelColor
            let icon = allOff ? "exclamationmark.triangle.fill" : "fan.fill"
            let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            img?.isTemplate = true
            b.image = img
            b.imagePosition = .imageLeading
            b.attributedTitle = NSAttributedString(string: " \(label)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: c])
        }

        warningItem.isHidden = !allOff
        thermalLabel_.stringValue = label
        thermalDot.layer?.backgroundColor = color.cgColor

        if allOff && Date().timeIntervalSince(lastNotif) > 60 {
            lastNotif = Date()
            let c = UNMutableNotificationContent(); c.title = "FanGuard"
            c.body = "Both fans disabled — no cooling active"; c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    @objc func quit() {
        for f in fans where f.mode == .manual { smcWrite("F\(f.fanIndex)Md", "00") }
        NSApplication.shared.terminate(nil)
    }
}

@main
struct FanGuardApp {
    static var appDelegate: AppDelegate?
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        app.run()
    }
}
