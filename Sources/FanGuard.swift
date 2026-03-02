import Cocoa
import IOKit
import Foundation
import UserNotifications

// MARK: - SMC

let SMC_CMD_READ_BYTES: UInt8 = 5
let SMC_CMD_READ_KEYINFO: UInt8 = 9

struct SMCKeyData {
    struct vers { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct pLimitData { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
    struct keyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
    var key: UInt32 = 0; var vers = vers(); var pLimitData = pLimitData(); var keyInfo = keyInfo()
    var padding: UInt16 = 0; var result: UInt8 = 0; var status: UInt8 = 0; var data8: UInt8 = 0; var data32: UInt32 = 0
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

func fourCC(_ s: String) -> UInt32 { var r: UInt32 = 0; for c in s.utf8 { r = (r << 8) | UInt32(c) }; return r }

class SMC {
    private var conn: io_connect_t = 0
    init?() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"))
        guard svc != 0 else { return nil }
        let r = IOServiceOpen(svc, mach_task_self_, 0, &conn); IOObjectRelease(svc)
        guard r == kIOReturnSuccess else { return nil }
    }
    deinit { IOServiceClose(conn) }
    func float(_ key: String) -> Float? {
        var inp = SMCKeyData(); var out = SMCKeyData()
        inp.key = fourCC(key); inp.data8 = SMC_CMD_READ_KEYINFO
        var sz = MemoryLayout<SMCKeyData>.size
        var r = IOConnectCallStructMethod(conn, 2, &inp, sz, &out, &sz)
        guard r == kIOReturnSuccess else { return nil }
        inp.keyInfo.dataSize = out.keyInfo.dataSize; inp.data8 = SMC_CMD_READ_BYTES
        r = IOConnectCallStructMethod(conn, 2, &inp, sz, &out, &sz)
        guard r == kIOReturnSuccess else { return nil }
        var v: Float = 0
        withUnsafeBytes(of: &out.bytes) { p in memcpy(&v, p.baseAddress!, 4) }
        return v
    }
    func uint8(_ key: String) -> UInt8? {
        var inp = SMCKeyData(); var out = SMCKeyData()
        inp.key = fourCC(key); inp.data8 = SMC_CMD_READ_KEYINFO
        var sz = MemoryLayout<SMCKeyData>.size
        var r = IOConnectCallStructMethod(conn, 2, &inp, sz, &out, &sz)
        guard r == kIOReturnSuccess else { return nil }
        inp.keyInfo.dataSize = out.keyInfo.dataSize; inp.data8 = SMC_CMD_READ_BYTES
        r = IOConnectCallStructMethod(conn, 2, &inp, sz, &out, &sz)
        guard r == kIOReturnSuccess else { return nil }
        var v: UInt8 = 0
        withUnsafeBytes(of: &out.bytes) { p in v = p[0] }
        return v
    }
}

// MARK: - XPC Writer

func smcWrite(_ key: String, _ value: String) {
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

func floatHex(_ v: Float) -> String {
    var f = v; var b = [UInt8](repeating: 0, count: 4); memcpy(&b, &f, 4)
    return b.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Fan Mode

enum FanMode: Int { case auto = 0; case manual = 1; case off = 2 }

// MARK: - Per-Fan Control View

class FanView: NSView {
    let fanIndex: Int
    let nameLabel: NSTextField
    let rpmLabel: NSTextField
    let dot: NSView
    let seg: NSSegmentedControl  // Auto | Manual | Off
    let slider: NSSlider
    let sliderLabel: NSTextField
    var sliderRow: NSView!

    var mode: FanMode = .auto
    var manualRPM: Float = 2500
    var lastActual: Float = 0
    var onChanged: (() -> Void)?

    // Constraints we toggle
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

        // Slider row container
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
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateSliderVisibility() {
        let show = mode == .manual
        sliderRow.isHidden = !show
        heightWithSlider.isActive = show
        heightWithoutSlider.isActive = !show
    }

    @objc func segChanged() {
        mode = FanMode(rawValue: seg.selectedSegment) ?? .auto
        if mode == .manual {
            // Initialize slider to current actual RPM, not stale target
            manualRPM = max(lastActual, 2317)
            slider.floatValue = manualRPM
            sliderLabel.stringValue = "\(Int(manualRPM))"
        }
        updateSliderVisibility()
        applyMode()
        // Only show immediate label on mode switch (not on every tick)
        if mode == .off {
            rpmLabel.stringValue = "OFF"
            dot.layer?.backgroundColor = NSColor.systemGray.cgColor
        }
        onChanged?()
        if let menu = enclosingMenuItem?.menu { menu.update() }
    }

    @objc func sliderChanged() {
        manualRPM = Float(slider.intValue)
        sliderLabel.stringValue = "\(Int(manualRPM))"
        applyMode()
        // Don't touch rpmLabel here — let the poll show actual RPM
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

    func refreshDisplay() {
        // Immediately update visuals from current state
        needsDisplay = true
    }

    func update(actual: Float) {
        lastActual = actual
        let val: String
        let color: NSColor
        switch mode {
        case .off:
            val = "OFF"; color = .systemGray
        case .manual:
            val = "\(Int(actual)) RPM"
            color = actual > 0 ? .systemBlue : .systemOrange
        case .auto:
            if actual > 0 {
                val = "\(Int(actual)) RPM"
                color = actual > 4000 ? .systemOrange : .systemGreen
            } else {
                val = "Idle"; color = .systemGray
            }
        }
        rpmLabel.stringValue = val
        dot.layer?.backgroundColor = color.cgColor
        seg.selectedSegment = mode.rawValue

        if mode == .manual && !slider.isHighlighted {
            slider.floatValue = manualRPM
            sliderLabel.stringValue = "\(Int(manualRPM))"
        }
        updateSliderVisibility()
    }
}

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var smc: SMC?
    var lastNotif: Date = .distantPast

    var fans: [FanView] = []
    var fanActual: [Float] = [0, 0]
    var cpuTemp: Float = 0; var gpuTemp: Float = 0
    var cpuLabel: NSTextField!; var gpuLabel: NSTextField!
    var cpuDot: NSView!; var gpuDot: NSView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        smc = SMC()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        poll()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common) // fires during menu tracking too
        timer = t
    }

    func buildMenu() {
        menu = NSMenu()
        menu.minimumWidth = 280
        menu.autoenablesItems = false

        // Fans
        let left = FanView(name: "Left", index: 0, defaultMode: .off)
        let right = FanView(name: "Right", index: 1, defaultMode: .auto)
        left.onChanged = { [weak self] in self?.rebuildLayout() }
        right.onChanged = { [weak self] in self?.rebuildLayout() }
        fans = [left, right]

        for fan in fans {
            let item = NSMenuItem(); item.view = fan; menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Temps — single row
        let tv = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        cpuDot = NSView(); cpuDot.wantsLayer = true; cpuDot.layer?.cornerRadius = 4
        let cn = NSTextField(labelWithString: "CPU"); cn.font = .systemFont(ofSize: 12); cn.textColor = .secondaryLabelColor
        cpuLabel = NSTextField(labelWithString: "--"); cpuLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        gpuDot = NSView(); gpuDot.wantsLayer = true; gpuDot.layer?.cornerRadius = 4
        let gn = NSTextField(labelWithString: "GPU"); gn.font = .systemFont(ofSize: 12); gn.textColor = .secondaryLabelColor
        gpuLabel = NSTextField(labelWithString: "--"); gpuLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        for v: NSView in [cpuDot, cn, cpuLabel, gpuDot, gn, gpuLabel] {
            tv.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            cpuDot.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 20),
            cpuDot.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
            cpuDot.widthAnchor.constraint(equalToConstant: 8), cpuDot.heightAnchor.constraint(equalToConstant: 8),
            cn.leadingAnchor.constraint(equalTo: cpuDot.trailingAnchor, constant: 6),
            cn.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
            cpuLabel.leadingAnchor.constraint(equalTo: cn.trailingAnchor, constant: 2),
            cpuLabel.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
            gpuDot.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 148),
            gpuDot.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
            gpuDot.widthAnchor.constraint(equalToConstant: 8), gpuDot.heightAnchor.constraint(equalToConstant: 8),
            gn.leadingAnchor.constraint(equalTo: gpuDot.trailingAnchor, constant: 6),
            gn.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
            gpuLabel.leadingAnchor.constraint(equalTo: gn.trailingAnchor, constant: 2),
            gpuLabel.centerYAnchor.constraint(equalTo: tv.centerYAnchor),
        ])
        let ti = NSMenuItem(); ti.view = tv; menu.addItem(ti)

        menu.addItem(NSMenuItem.separator())
        let q = NSMenuItem(title: "Quit FanGuard", action: #selector(quit), keyEquivalent: "q"); q.target = self
        menu.addItem(q)

        statusItem.menu = menu
    }

    func rebuildLayout() {
        // Force NSMenu to recalculate item heights after slider show/hide
        // by toggling visibility of the menu items
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
        guard let smc = smc else { self.smc = SMC(); return }
        for i in 0..<2 { fanActual[i] = smc.float("F\(i)Ac") ?? 0 }
        for k in ["Tp09","Tp0T","Tp01","TC0P","TC0p","Tp05"] { if let t = smc.float(k), t > 10, t < 130 { cpuTemp = t; break } }
        for k in ["Tg0f","Tg0T","TG0P","Tg05"] { if let t = smc.float(k), t > 10, t < 130 { gpuTemp = t; break } }

        // Re-apply overrides
        for fan in fans where fan.mode != .auto { fan.applyMode() }

        DispatchQueue.main.async { [self] in
            let allOff = fans.allSatisfy { $0.mode == .off }
            // Menu bar
            if let b = statusItem.button {
                let t = cpuTemp > 0 ? Int(cpuTemp) : 0
                let c: NSColor = allOff ? .systemRed : cpuTemp > 100 ? .systemRed : cpuTemp > 90 ? .systemOrange : .labelColor
                let icon = allOff ? "exclamationmark.triangle.fill" : "fan.fill"
                b.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
                b.imagePosition = .imageLeading
                b.attributedTitle = NSAttributedString(string: allOff ? " \(t)° NO FANS" : " \(t)°", attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: c])
            }
            // Fans
            for i in 0..<2 { fans[i].update(actual: fanActual[i]) }
            // Temps
            func tc(_ t: Float) -> NSColor { t > 100 ? .systemRed : t > 90 ? .systemOrange : t > 75 ? .systemYellow : .systemGreen }
            cpuLabel.stringValue = cpuTemp > 0 ? "\(Int(cpuTemp))°" : "--"
            cpuDot.layer?.backgroundColor = tc(cpuTemp).cgColor
            gpuLabel.stringValue = gpuTemp > 0 ? "\(Int(gpuTemp))°" : "--"
            gpuDot.layer?.backgroundColor = tc(gpuTemp).cgColor
        }

        // Alert: both fans disabled
        let allOff = fans.allSatisfy { $0.mode == .off }
        if allOff && Date().timeIntervalSince(lastNotif) > 60 {
            lastNotif = Date()
            let c = UNMutableNotificationContent(); c.title = "FanGuard"
            c.body = "Both fans disabled — no cooling active"; c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
        // Alert: right fan fault
        if !allOff, fans[1].mode != .off, fanActual[1] == 0, (smc.float("F1Tg") ?? 0) > 100,
           Date().timeIntervalSince(lastNotif) > 60 {
            lastNotif = Date()
            let c = UNMutableNotificationContent(); c.title = "FanGuard"
            c.body = "Right fan not spinning"; c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    @objc func quit() {
        for f in fans where f.mode == .manual { smcWrite("F\(f.fanIndex)Md", "00") }
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared; let d = AppDelegate(); app.delegate = d; app.run()
