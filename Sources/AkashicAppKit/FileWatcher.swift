import Foundation

/// 目錄監看（DispatchSource）＋ debounce——CLI/MCP/git 在 App 外改動 store 時自動刷新。
public final class FileWatcher {
    let directories: [URL]
    let debounce: TimeInterval
    let onChange: () -> Void

    private var sources: [DispatchSourceFileSystemObject] = []
    private var descriptors: [Int32] = []
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "akashic.filewatcher")

    public init(directories: [URL], debounce: TimeInterval = 0.5,
                onChange: @escaping () -> Void) {
        self.directories = directories
        self.debounce = debounce
        self.onChange = onChange
    }

    public func start() throws {
        stop()
        for dir in directories {
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            descriptors.append(fd)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self] in
                self?.scheduleNotification()
            }
            source.resume()
            sources.append(source)
        }
    }

    public func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        descriptors.forEach { close($0) }
        descriptors.removeAll()
        pending?.cancel()
        pending = nil
    }

    /// debounce：密集變更（如 import wave）合併為一次通知。
    private func scheduleNotification() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit {
        stop()
    }
}
