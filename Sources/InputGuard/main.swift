import AppKit
import Foundation

if CommandLine.arguments.contains("--probe") {
    let sources = InputSourceController()
    let audio = AudioInputMonitor()
    print("enabled sources:")
    for s in sources.enabledSources() {
        print("  \(s.id)  [\(s.name)]")
    }
    print("fallback: \(sources.firstNonDoubaoEnabledID() ?? "nil")")
    print("probing for 8s (100ms)...")
    let end = Date().addingTimeInterval(8)
    var last = ""
    while Date() < end {
        let line = "source=\(sources.currentID())  doubaoAudio=\(String(describing: audio.doubaoIsUsingAudioInput()))"
        if line != last {
            print(line)
            last = line
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
