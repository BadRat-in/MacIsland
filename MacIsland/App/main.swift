//
//  main.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import AppKit

// DEBUG: redirect stderr to a log file early so NSLog output from the
// app (whose GUI bootstrap requires `open`-style launch — direct
// terminal exec exits before NSApplicationMain settles) is captured
// somewhere the developer can read after the fact. Append mode so
// successive launches don't wipe history; unbuffered so lines hit
// disk in real time as the user plays / pauses / skips tracks.
// Remove or gate behind a build flag before release.
do {
    let logPath = "/tmp/macisland-debug.log"
    let banner = "\n========== \(Date()) — MacIsland session start (pid \(getpid())) ==========\n"
    freopen(logPath, "a", stderr)
    setbuf(stderr, nil)
    fputs(banner, stderr)
}

let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = availableDirectories[0]
    .appendingPathComponent("MacIsland")
let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(bundleIdentifier)
try? FileManager.default.removeItem(at: temporaryDirectory)
try? FileManager.default.createDirectory(
    at: documentsDirectory,
    withIntermediateDirectories: true,
    attributes: nil
)
try? FileManager.default.createDirectory(
    at: temporaryDirectory,
    withIntermediateDirectories: true,
    attributes: nil
)

let pidFile = documentsDirectory.appendingPathComponent("ProcessIdentifier")

do {
    let prevIdentifier = try String(contentsOf: pidFile, encoding: .utf8)
    if let prev = Int(prevIdentifier) {
        if let app = NSRunningApplication(processIdentifier: pid_t(prev)) {
            app.terminate()
        }
    }
} catch {}
try? FileManager.default.removeItem(at: pidFile)

do {
    let pid = String(NSRunningApplication.current.processIdentifier)
    try pid.write(to: pidFile, atomically: true, encoding: .utf8)
} catch {
    NSAlert.popError(error)
    exit(1)
}

_ = TrayDrop.shared
TrayDrop.shared.cleanExpiredFiles()

private let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
