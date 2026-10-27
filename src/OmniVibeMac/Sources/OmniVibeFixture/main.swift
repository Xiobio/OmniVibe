import AppKit
import Foundation

// A separate process with disposable windows. Desktop validation never manipulates the user's windows.
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        for index in 0..<2 {
            let window = NSWindow(
                contentRect: NSRect(x: 120 + index * 360, y: 180 + index * 90, width: 340, height: 260),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "OmniVibe Fixture \(index + 1)"
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 120, height: 100)
            let label = NSTextField(labelWithString: "OmniVibe · 隔离测试窗口 \(index + 1)\n验证完成后自动关闭")
            label.alignment = .center
            label.textColor = .labelColor
            label.font = .systemFont(ofSize: 17, weight: .medium)
            label.frame = NSRect(x: 20, y: 80, width: 300, height: 100)
            label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
            window.contentView?.addSubview(label)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        // A failed runner cannot leave fixture windows open indefinitely.
        Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { _ in NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = FixtureDelegate()
app.delegate = delegate
app.run()
