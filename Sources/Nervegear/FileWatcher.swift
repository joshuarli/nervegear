import Foundation

final class FileWatcher: @unchecked Sendable {
    private let urls: [URL]
    private let queue = DispatchQueue(label: "nervegear.file-watch", qos: .utility)
    private let source: DispatchSourceTimer
    private let onChange: () -> Void
    private var previousData: [URL: Data] = [:]
    private var previousFailures: [URL: String] = [:]

    init(urls: [URL], optionalURLs: [URL] = [], onChange: @escaping () -> Void) throws {
        self.urls = urls + optionalURLs
        self.onChange = onChange
        for url in urls {
            previousData[url] = try Data(contentsOf: url, options: .mappedIfSafe)
        }
        for url in optionalURLs {
            do {
                previousData[url] = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                previousFailures[url] = error.localizedDescription
            }
        }
        source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .milliseconds(450), repeating: .milliseconds(450), leeway: .milliseconds(120))
        source.setEventHandler { [weak self] in self?.poll() }
    }

    func start() {
        source.activate()
    }

    func forceReload() {
        queue.async { [weak self] in self?.onChange() }
    }

    private func poll() {
        var changed = false
        for url in urls {
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                if previousData[url] != data {
                    previousData[url] = data
                    changed = true
                }
                previousFailures.removeValue(forKey: url)
            } catch {
                previousData.removeValue(forKey: url)
                let message = error.localizedDescription
                if previousFailures[url] != message {
                    previousFailures[url] = message
                    changed = true
                }
            }
        }
        if changed { onChange() }
    }
}
