import AppKit
import Darwin
import MetalKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    private let configuration: AppConfiguration
    private var window: NSWindow?
    private weak var worldView: WorldView?
    private var renderer: WorldRenderer?
    private var signalSources: [DispatchSourceSignal] = []
    private var didSaveSessionForSignal = false

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            if let readyURL = configuration.readyURL,
               FileManager.default.fileExists(atPath: readyURL.path) {
                try FileManager.default.removeItem(at: readyURL)
            }
            try createWindow()
        } catch {
            fputs("Nervegear startup failed: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !didSaveSessionForSignal { saveSession() }
        worldView?.stopControllerDiscovery()
    }

    private func createWindow() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.gpu("No Metal device is available on this Mac")
        }
        let view = WorldView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        view.framebufferOnly = !configuration.screenshotOnLaunch
        view.clearColor = MTLClearColor(red: 0.58, green: 0.76, blue: 0.88, alpha: 1)
        let renderer = try WorldRenderer(view: view, device: device, configuration: configuration)
        self.renderer = renderer

        self.worldView = view
        view.orbitCamera = { [weak renderer] x, y in renderer?.orbitCamera(horizontal: x, vertical: y) }
        view.zoomCamera = { [weak renderer] delta in renderer?.zoomCamera(delta: delta) }
        view.captureScreenshot = { [weak renderer] in renderer?.requestScreenshot() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1360, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nervegear"
        window.minSize = NSSize(width: 900, height: 620)
        window.delegate = self
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        installSignalHandler()
    }

    func windowDidResignKey(_ notification: Notification) {
        worldView?.resetKeyboardInput()
    }

    private func installSignalHandler() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.saveSession()
                self.didSaveSessionForSignal = true
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func saveSession() {
        do {
            try renderer?.saveSession()
        } catch {
            fputs("Nervegear session save failed during shutdown: \(error.localizedDescription)\n", stderr)
        }
    }
}

@main
@MainActor
enum Nervegear {
    static func main() {
        do {
            let configuration = try AppConfiguration.parse(
                arguments: CommandLine.arguments,
                workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            )
            let application = NSApplication.shared
            application.setActivationPolicy(.regular)
            let delegate = AppDelegate(configuration: configuration)
            application.delegate = delegate
            application.run()
        } catch {
            fputs("Nervegear: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
