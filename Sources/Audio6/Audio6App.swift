import AppKit
import Combine
import SwiftUI

extension Color {
    static let tint = Color(hex: 0xFF5F00)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

@main
struct Audio6App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The UI lives in a status item + popover (see AppDelegate); no windows here.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DeviceModel()
    private var statusItem: NSStatusItem!
    private var panel: MenuPanel!
    private var iconSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only, no Dock icon

        // macOS can restore/auto-show the (empty) Settings scene's window at
        // launch. We never want any window - only our own popover - so close
        // whatever the Settings scene happened to create. Skip the status
        // bar's own window: closing it leaves the button in an off-screen
        // window, and NSPopover then silently refuses to show.
        DispatchQueue.main.async {
            NSApp.windows
                .filter { !String(describing: type(of: $0)).contains("StatusBar") }
                .forEach { $0.close() }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        iconSubscription = model.$connected
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateIcon(connected: $0) }

        panel = MenuPanel(content: ContentView().environmentObject(model))
        panel.onClose = { [weak self] in self?.panelDidClose() }
    }

    private func updateIcon(connected: Bool) {
        let image = NSImage(systemSymbolName: connected ? "hifispeaker.arrow.forward.fill" : "hifispeaker.arrow.forward",
                            accessibilityDescription: "Audio6")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func togglePanel() {
        if panel.isVisible { panel.close() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        model.refresh()
        panel.show(below: button)
        button.highlight(true)
    }

    private func panelDidClose() {
        statusItem.button?.highlight(false)
    }
}

/// Status-item popover: system vibrant material, drop shadow, and a
/// chevron pointing back at the menu bar icon - all handled natively by
/// NSPopover, which also takes care of animating size changes (e.g. when
/// switching between the Live and Startup tabs) without clipping.
final class MenuPanel: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let hostingView: NSView
    var onClose: (() -> Void)?

    var isVisible: Bool { popover.isShown }

    init<V: View>(content: V) {
        // .fixedSize() makes SwiftUI report its true ideal size instead of
        // an ambiguous/zero size before the popover's window exists - without
        // it the popover can show at (0, 0), i.e. invisible, on first open.
        let hosting = NSHostingController(rootView: content.fixedSize())
        hosting.sizingOptions = [.preferredContentSize]
        hostingView = hosting.view
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting
        popover.delegate = self
    }

    func show(below button: NSStatusBarButton) {
        popover.contentSize = hostingView.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        onClose?()
    }
}

enum Page: String, CaseIterable, Identifiable {
    case live = "Live"
    case startup = "Startup"
    var id: Self { self }
}

struct ContentView: View {
    @EnvironmentObject var model: DeviceModel
    @State private var page: Page = .live

    private var errorText: String {
        switch model.lastError {
        case -2: return "No matching USB device found. Pick it from the list below."
        case -3: return "Could not open the USB device (plug-in failed)."
        case -4: return "Could not open the USB device (interface query failed)."
        case 0: return ""
        default: return String(format: "USB error 0x%08x", UInt32(bitPattern: model.lastError))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.connected {
                ForEach(Channel.allCases) { ch in
                    ChannelRow(channel: ch, isStartup: page == .startup)
                }
                if page == .startup {
                    Text("Stored on the interface and applied when it powers on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Copy live settings to startup") { model.copyLiveToStartup() }
                }
            } else {
                Label("Traktor Audio 6 not connected", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()
            HStack {
                Picker("Device", selection: Binding(
                    get: { model.selectedID },
                    set: { model.select($0) }
                )) {
                    Text("Auto (Native Instruments)").tag(DeviceModel.autoID)
                    ForEach(model.devices) { Text($0.label).tag($0.id) }
                    // keep a saved selection visible while it is unplugged
                    if model.selectedID != DeviceModel.autoID,
                       !model.devices.contains(where: { $0.id == model.selectedID }) {
                        Text("\(model.selectedID) (not found)").tag(model.selectedID)
                    }
                }
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan")
            }
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
        .tint(.tint)
        .onAppear { model.refresh() }
    }
}

struct ChannelRow: View {
    @EnvironmentObject var model: DeviceModel
    let channel: Channel
    let isStartup: Bool

    private var state: ChannelState { model.state(channel, isStartup: isStartup) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Input", selection: Binding(
                    get: { InputSource(rawValue: state.input) ?? .line },
                    set: { model.set(.input, channel, $0.rawValue, isStartup: isStartup) }
                )) {
                    ForEach(InputSource.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Thru", isOn: Binding(
                    get: { state.thru != 0 },
                    set: { model.set(.thru, channel, $0 ? 1 : 0, isStartup: isStartup) }
                ))
                .toggleStyle(.switch)
            }
            .padding(4)
        } label: {
            Text("Channel \(channel.rawValue)").font(.headline)
        }
    }
}
