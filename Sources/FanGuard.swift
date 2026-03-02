import Cocoa
import IOKit
import Foundation
import UserNotifications

// MARK: - SMC Interface

let SMC_CMD_READ_BYTES: UInt8 = 5
let SMC_CMD_WRITE_BYTES: UInt8 = 6
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

func fourCharCode(_ str: String) -> UInt32 {
    var result: UInt32 = 0
    for char in str.utf8 { result = (result << 8) | UInt32(char) }
    return result
}

class SMCReader {
    private var conn: io_connect_t = 0
    private var isOpen = false

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMCKeysEndpoint"))
        guard service != 0 else { return nil }
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        guard result == kIOReturnSuccess else { return nil }
        isOpen = true
    }

    deinit {
        if isOpen { IOServiceClose(conn) }
    }

    func readKey(_ key: String) -> (bytes: [UInt8], size: UInt32, type: UInt32)? {
        var inp = SMCKeyData(); var out = SMCKeyData()
        inp.key = fourCharCode(key); inp.data8 = SMC_CMD_READ_KEYINFO
        var outSize = MemoryLayout<SMCKeyData>.size
        var r = IOConnectCallStructMethod(conn, 2, &inp, MemoryLayout<SMCKeyData>.size, &out, &outSize)
        guard r == kIOReturnSuccess else { return nil }
        let ds = out.keyInfo.dataSize; let dt = out.keyInfo.dataType
        inp.keyInfo.dataSize = ds; inp.data8 = SMC_CMD_READ_BYTES
        r = IOConnectCallStructMethod(conn, 2, &inp, MemoryLayout<SMCKeyData>.size, &out, &outSize)
        guard r == kIOReturnSuccess else { return nil }
        var bytes: [UInt8] = []
        withUnsafeBytes(of: &out.bytes) { ptr in for i in 0..<Int(ds) { bytes.append(ptr[i]) } }
        return (bytes, ds, dt)
    }

    func readFloat(_ key: String) -> Float? {
        guard let r = readKey(key), r.bytes.count >= 4 else { return nil }
        var value: Float = 0
        let b = r.bytes
        memcpy(&value, b, 4)
        return value
    }

    func readUInt8(_ key: String) -> UInt8? {
        guard let r = readKey(key), !r.bytes.isEmpty else { return nil }
        return r.bytes[0]
    }
}

// MARK: - Fan Data

struct FanState {
    var fan0Actual: Float = 0
    var fan0Target: Float = 0
    var fan0Mode: UInt8 = 0
    var fan1Actual: Float = 0
    var fan1Target: Float = 0
    var fan1Mode: UInt8 = 0
    var cpuTemp: Float = 0
    var gpuTemp: Float = 0

    var fan0Status: String {
        if fan0Mode == 1 && fan0Target == 0 { return "DISABLED" }
        if fan0Actual == 0 && fan0Target > 0 { return "FAULT" }
        return "\(Int(fan0Actual)) RPM"
    }

    var fan1Status: String {
        if fan1Actual == 0 && fan1Target > 100 { return "FAULT" }
        if fan1Target == 0 { return "Idle" }
        return "\(Int(fan1Actual)) RPM"
    }

    var fan1Healthy: Bool {
        // Healthy if: target is low/zero (system doesn't need cooling) OR fan is spinning
        if fan1Target < 100 { return true }
        return fan1Actual > 0
    }

    var overheating: Bool {
        return cpuTemp > 100
    }

    var menuBarText: String {
        let tempStr = cpuTemp > 0 ? "\(Int(cpuTemp))°" : "--°"
        let f1Str: String
        if fan1Actual > 0 {
            f1Str = "\(Int(fan1Actual))"
        } else if fan1Target < 100 {
            f1Str = "idle"
        } else {
            f1Str = "ERR"
        }
        return "\(tempStr) R:\(f1Str)"
    }
}

// MARK: - XPC Writer (for fan0-killer functionality)

func xpcWriteKey(_ key: String, _ value: String) -> Bool {
    let service = "com.crystalidea.macsfancontrol.smcwrite"
    let conn = xpc_connection_create_mach_service(service, nil, UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED))
    xpc_connection_set_event_handler(conn) { _ in }
    xpc_connection_resume(conn)

    let openMsg = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_string(openMsg, "command", "open")
    let _ = xpc_connection_send_message_with_reply_sync(conn, openMsg)

    let writeMsg = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_string(writeMsg, "command", "write")
    xpc_dictionary_set_string(writeMsg, "key", key)
    xpc_dictionary_set_string(writeMsg, "value", value)
    let reply = xpc_connection_send_message_with_reply_sync(conn, writeMsg)

    var ok = false
    if xpc_get_type(reply) == XPC_TYPE_DICTIONARY as xpc_type_t {
        let desc = String(cString: xpc_copy_description(reply))
        ok = desc.contains("OK")
    }

    let closeMsg = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_string(closeMsg, "command", "close")
    let _ = xpc_connection_send_message_with_reply_sync(conn, closeMsg)
    xpc_connection_cancel(conn)
    return ok
}

func forceFan0Off() {
    let _ = xpcWriteKey("F0Md", "01")
    let _ = xpcWriteKey("F0Tg", "00000000")
}

func restoreFan0Auto() {
    let _ = xpcWriteKey("F0Md", "00")
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var smc: SMCReader?
    var state = FanState()
    var fan0KillerEnabled = true
    var lastNotificationTime: Date = .distantPast

    // Menu items we update
    var fan0Item: NSMenuItem!
    var fan1Item: NSMenuItem!
    var cpuTempItem: NSMenuItem!
    var gpuTempItem: NSMenuItem!
    var statusItem2: NSMenuItem!
    var toggleItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        smc = SMCReader()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menu = NSMenu()

        let headerItem = NSMenuItem(title: "FanGuard — M2 Pro Fan Monitor", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let headerAttr = NSMutableAttributedString(string: "FanGuard", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 13),
        ])
        headerItem.attributedTitle = headerAttr
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        fan0Item = NSMenuItem(title: "Left Fan:  --", action: nil, keyEquivalent: "")
        fan0Item.isEnabled = false
        menu.addItem(fan0Item)

        fan1Item = NSMenuItem(title: "Right Fan: --", action: nil, keyEquivalent: "")
        fan1Item.isEnabled = false
        menu.addItem(fan1Item)

        menu.addItem(NSMenuItem.separator())

        cpuTempItem = NSMenuItem(title: "CPU Temp: --", action: nil, keyEquivalent: "")
        cpuTempItem.isEnabled = false
        menu.addItem(cpuTempItem)

        gpuTempItem = NSMenuItem(title: "GPU Temp: --", action: nil, keyEquivalent: "")
        gpuTempItem.isEnabled = false
        menu.addItem(gpuTempItem)

        menu.addItem(NSMenuItem.separator())

        statusItem2 = NSMenuItem(title: "Status: --", action: nil, keyEquivalent: "")
        statusItem2.isEnabled = false
        menu.addItem(statusItem2)

        menu.addItem(NSMenuItem.separator())

        toggleItem = NSMenuItem(title: "Left Fan Killer: ON", action: #selector(toggleFan0Killer), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit FanGuard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Initial read
        updateFanState()

        // Update every 3 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateFanState()
        }
    }

    func updateFanState() {
        guard let smc = smc else {
            // Try to reconnect
            self.smc = SMCReader()
            return
        }

        state.fan0Actual = smc.readFloat("F0Ac") ?? 0
        state.fan0Target = smc.readFloat("F0Tg") ?? 0
        state.fan0Mode = smc.readUInt8("F0Md") ?? 0
        state.fan1Actual = smc.readFloat("F1Ac") ?? 0
        state.fan1Target = smc.readFloat("F1Tg") ?? 0
        state.fan1Mode = smc.readUInt8("F1Md") ?? 0

        // Try multiple temperature keys — Apple Silicon uses various keys
        let tempKeys = ["Tp09", "Tp0T", "Tp01", "TC0P", "TC0p", "Tp05"]
        for key in tempKeys {
            if let t = smc.readFloat(key), t > 10 && t < 130 {
                state.cpuTemp = t
                break
            }
        }

        let gpuTempKeys = ["Tg0f", "Tg0T", "TG0P", "Tg05"]
        for key in gpuTempKeys {
            if let t = smc.readFloat(key), t > 10 && t < 130 {
                state.gpuTemp = t
                break
            }
        }

        // Re-force fan 0 off if enabled
        if fan0KillerEnabled {
            forceFan0Off()
        }

        // Update menu bar
        DispatchQueue.main.async { [self] in
            if let button = statusItem.button {
                let text = state.menuBarText
                let attrs: [NSAttributedString.Key: Any]
                if state.overheating || !state.fan1Healthy {
                    attrs = [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                        .foregroundColor: NSColor.systemRed
                    ]
                } else if state.cpuTemp > 90 {
                    attrs = [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: NSColor.systemOrange
                    ]
                } else {
                    attrs = [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    ]
                }
                button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
            }

            // Update menu items
            let f0StatusStr = state.fan0Status
            fan0Item.title = "Left Fan:   \(f0StatusStr)"
            if f0StatusStr == "DISABLED" {
                fan0Item.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            }

            fan1Item.title = "Right Fan:  \(state.fan1Status)"
            if state.fan1Healthy {
                fan1Item.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
                fan1Item.image?.isTemplate = false
            } else {
                fan1Item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            }

            cpuTempItem.title = "CPU Temp:   \(state.cpuTemp > 0 ? "\(Int(state.cpuTemp))°C" : "N/A")"
            gpuTempItem.title = "GPU Temp:   \(state.gpuTemp > 0 ? "\(Int(state.gpuTemp))°C" : "N/A")"

            // Status line
            if state.overheating {
                statusItem2.title = "Status: OVERHEATING"
            } else if !state.fan1Healthy {
                statusItem2.title = "Status: RIGHT FAN FAULT"
            } else if state.cpuTemp > 90 {
                statusItem2.title = "Status: Hot — throttling likely"
            } else if state.cpuTemp > 75 {
                statusItem2.title = "Status: Warm — OK"
            } else {
                statusItem2.title = "Status: Cool"
            }

            toggleItem.title = "Left Fan Killer: \(fan0KillerEnabled ? "ON" : "OFF")"
        }

        // Send notification for critical states
        if (!state.fan1Healthy || state.overheating) && Date().timeIntervalSince(lastNotificationTime) > 60 {
            lastNotificationTime = Date()
            let content = UNMutableNotificationContent()
            content.title = "FanGuard Alert"
            if !state.fan1Healthy {
                content.body = "Right fan is not spinning! Target: \(Int(state.fan1Target)) RPM, Actual: \(Int(state.fan1Actual)) RPM"
            } else {
                content.body = "CPU temperature critical: \(Int(state.cpuTemp))°C"
            }
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    @objc func toggleFan0Killer() {
        fan0KillerEnabled.toggle()
        if !fan0KillerEnabled {
            restoreFan0Auto()
        }
        toggleItem.title = "Left Fan Killer: \(fan0KillerEnabled ? "ON" : "OFF")"
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
