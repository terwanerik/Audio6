import Foundation
import TA6USB

enum Channel: String, CaseIterable, Identifiable {
    case A, B
    var id: String { rawValue }
    var index: UInt16 { self == .A ? 3 : 5 }
}

enum Setting {
    case input, thru
    var request: UInt8 { self == .input ? 2 : 1 }
}

/// If Phono/Line turn out reversed on your unit, swap the two raw values.
enum InputSource: UInt8, CaseIterable, Identifiable {
    case line = 0
    case phono = 1
    var id: UInt8 { rawValue }
    var label: String { self == .line ? "Line" : "Phono" }
}

struct ChannelState: Equatable {
    var input: UInt8 = 0
    var thru: UInt8 = 0
}

/// Raw protocol. Blocking calls - only use from the model's serial queue.
enum USB {
    static let startupOffset: UInt16 = 0x100
    static let storeStartupRequest: UInt8 = 0x10

    static func read(_ s: Setting, _ c: Channel, startup: Bool) -> UInt8? {
        var v: UInt8 = 0
        let index = c.index + (startup ? startupOffset : 0)
        return ta6_read(s.request, index, &v) == 0 ? v : nil
    }

    @discardableResult
    static func write(_ s: Setting, _ c: Channel, _ value: UInt8, startup: Bool) -> Bool {
        let index = c.index + (startup ? startupOffset : 0)
        guard ta6_write(s.request, UInt16(value), index) == 0 else { return false }
        if startup { return ta6_write(storeStartupRequest, 0, 0) == 0 }
        return true
    }

    static func readAll(startup: Bool) -> [Channel: ChannelState]? {
        var out: [Channel: ChannelState] = [:]
        for c in Channel.allCases {
            guard let i = read(.input, c, startup: startup),
                  let t = read(.thru, c, startup: startup) else { return nil }
            out[c] = ChannelState(input: i, thru: t)
        }
        return out
    }
}

struct USBDevice: Identifiable, Hashable {
    let vid: UInt16
    let pid: UInt16
    let name: String
    var id: String { Self.makeID(vid, pid) }
    var label: String { "\(name) (\(id))" }
    static func makeID(_ vid: UInt16, _ pid: UInt16) -> String { String(format: "%04x:%04x", vid, pid) }

    static func list() -> [USBDevice] {
        var buf = [ta6_device_info](repeating: ta6_device_info(), count: 64)
        let n = Int(ta6_list(&buf, 64))
        return buf.prefix(max(n, 0)).map { info in
            var copy = info
            let name = withUnsafePointer(to: &copy.name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
            }
            return USBDevice(vid: info.vid, pid: info.pid, name: name.isEmpty ? "Unknown" : name)
        }
        .filter { $0.vid != 0 }
    }
}

final class DeviceModel: ObservableObject {
    static let autoID = "auto"

    @Published var connected = false
    @Published var live: [Channel: ChannelState] = [:]
    @Published var startup: [Channel: ChannelState] = [:]
    @Published var devices: [USBDevice] = []
    @Published var lastError: Int32 = 0
    @Published var selectedID: String = UserDefaults.standard.string(forKey: "device") ?? DeviceModel.autoID

    private let queue = DispatchQueue(label: "ta6.usb")
    private var timer: Timer?

    init() {
        applyTarget(selectedID)
        refresh()
        // Poll so changes made elsewhere (or a replug) show up
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func state(_ c: Channel, isStartup: Bool) -> ChannelState {
        (isStartup ? startup : live)[c] ?? ChannelState()
    }

    func refresh() {
        queue.async {
            let l = USB.readAll(startup: false)
            let s = USB.readAll(startup: true)
            let err = ta6_last_error()
            let devs = USBDevice.list()
            DispatchQueue.main.async {
                self.connected = l != nil
                self.lastError = err
                self.devices = devs
                if let l { self.live = l }
                if let s { self.startup = s }
            }
        }
    }

    /// Pick a device from the list (or "auto" = any Native Instruments device).
    func select(_ id: String) {
        selectedID = id
        UserDefaults.standard.set(id, forKey: "device")
        applyTarget(id)
        refresh()
    }

    private func applyTarget(_ id: String) {
        var vid: UInt16 = 0x17CC, pid: UInt16 = 0
        let parts = id.split(separator: ":")
        if parts.count == 2, let v = UInt16(parts[0], radix: 16), let p = UInt16(parts[1], radix: 16) {
            vid = v
            pid = p
        }
        queue.async { ta6_set_target(vid, pid) }
    }

    func set(_ setting: Setting, _ channel: Channel, _ value: UInt8, isStartup: Bool) {
        // Update the UI immediately, then write and read back
        var st = state(channel, isStartup: isStartup)
        switch setting {
        case .input: st.input = value
        case .thru: st.thru = value
        }
        if isStartup { startup[channel] = st } else { live[channel] = st }

        queue.async { USB.write(setting, channel, value, startup: isStartup) }
        refresh()
    }

    func copyLiveToStartup() {
        let snapshot = live
        queue.async {
            for (c, s) in snapshot {
                USB.write(.input, c, s.input, startup: true)
                USB.write(.thru, c, s.thru, startup: true)
            }
        }
        refresh()
    }
}
