import Foundation

/// Facts about the app shared by the app, the CLI, and tests.
public enum Metronome {
    public static let bundleIdentifier = "com.jamesclark32.metronome"

    /// The release version from Metronome.app's Info.plist, which the release workflow sets
    /// from the tag. The CLI lives in Metronome.app/Contents/Helpers, so it reads the plist
    /// one level up, following a Homebrew symlink first. `dev` outside a bundle.
    public static let version: String = {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        let plist = Bundle.main.executableURL?.resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Info.plist")
        if let plist, let info = NSDictionary(contentsOf: plist),
           let version = info["CFBundleShortVersionString"] as? String {
            return version
        }
        return "dev"
    }()
}
