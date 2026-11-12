import Foundation

/// Finds a usable Java runtime on the machine.
///
/// Minecraft requires a minimum Java version that depends on the game version:
/// Java 8 up to 1.16, Java 17 from 1.17 and Java 21 from 1.20.5. Picking the wrong
/// runtime makes the game fail with `UnsupportedClassVersionError`, so the lookup
/// takes the game version into account.
final class JavaLocator {
    static let shared = JavaLocator()

    /// A Java installation found on the machine.
    struct Runtime {
        let java: URL
        let javaHome: URL
        let majorVersion: Int
        let fullVersion: String
    }

    private var cache: [String: URL] = [:]

    // MARK: - Requirements

    /// The minimum Java version required by a Minecraft version.
    static func requiredJavaVersion(for minecraftVersion: String) -> Int {
        let parts = minecraftVersion
            .split(separator: ".")
            .compactMap { Int($0) }

        guard let major = parts.first else { return 8 }
        let minor = parts.count > 1 ? parts[1] : 0
        let patch = parts.count > 2 ? parts[2] : 0

        if major == 1 {
            if minor >= 20 && patch >= 5 { return 21 }   // 1.20.5 and newer
            if minor >= 17 { return 17 }                 // 1.17 to 1.20.4
            return 8                                      // 1.16 and older
        }
        // The new year based scheme (26.3, 26.2, …) needs Java 21 as well.
        if major >= 25 { return 21 }
        return 17
    }

    // MARK: - Lookup

    /// Returns the path of a Java executable that satisfies the requirement.
    ///
    /// The runtime configured by the user always wins; otherwise the closest
    /// installed runtime that is new enough is used.
    func locate(minimumMajor: Int = 17) -> URL? {
        let key = String(minimumMajor)
        if let cached = cache[key] { return cached }

        // A runtime chosen in the settings always takes precedence.
        let configured = UserDefaults.standard.string(forKey: "gameOnLauncherJavaPath") ?? ""
        if !configured.isEmpty, FileManager.default.isExecutableFile(atPath: configured) {
            cache[key] = URL(fileURLWithPath: configured)
            return cache[key]
        }

        let runtimes = installedRuntimes()
        let suitable = runtimes
            .filter { $0.majorVersion >= minimumMajor }
            .sorted { $0.majorVersion < $1.majorVersion }

        if let best = suitable.first ?? runtimes.sorted(by: { $0.majorVersion > $1.majorVersion }).first {
            cache[key] = best.java
            return best.java
        }

        // Last resort: whatever is on the PATH.
        for candidate in ["/usr/bin/java", "/usr/local/bin/java", "/opt/homebrew/bin/java"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                cache[key] = URL(fileURLWithPath: candidate)
                return cache[key]
            }
        }
        return nil
    }

    /// The runtime used when no specific requirement is known.
    func locate() -> URL? {
        locate(minimumMajor: 17)
    }

    /// Clears the cached results, for example after the user changes the setting.
    func invalidate() {
        cache.removeAll()
    }

    /// Every Java runtime installed on the machine.
    func installedRuntimes() -> [Runtime] {
        var found: [Runtime] = []

        // `java_home -V` lists every installed runtime.
        let home = Process()
        home.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        home.arguments = ["-V"]
        let pipe = Pipe()
        let errors = Pipe()
        home.standardOutput = pipe
        home.standardError = errors
        if (try? home.run()) != nil {
            home.waitUntilExit()
            // `java_home -V` prints the list of runtimes on stderr.
            let standard = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let failure = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // The list always goes to stderr; stdout only holds the default path.
            let output = failure.isEmpty ? standard : failure
            for line in output.split(separator: "\n") {
                // "    25.0.4 (x86_64) "Oracle Corporation" - Java SE 25.0.4 /path/to/Home"
                guard let range = line.range(of: #"/\S+/Contents/Home"#, options: .regularExpression) else { continue }
                let homePath = String(line[range]).trimmingCharacters(in: .whitespaces)
                let version = String(line[line.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let components = version.split(separator: ".").compactMap { Int($0) }
                guard let major = components.first else { continue }
                let java = URL(fileURLWithPath: homePath).appendingPathComponent("bin/java")
                guard FileManager.default.isExecutableFile(atPath: java.path) else { continue }
                found.append(Runtime(
                    java: java,
                    javaHome: URL(fileURLWithPath: homePath),
                    majorVersion: major,
                    fullVersion: components.map(String.init).joined(separator: ".")
                ))
            }
        }

        // Fall back to scanning the standard macOS location.
        let virtualMachines = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Java/JavaVirtualMachines", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: virtualMachines, includingPropertiesForKeys: nil) {
            for entry in entries {
                let javaHome = entry.appendingPathComponent("Contents/Home")
                let java = javaHome.appendingPathComponent("bin/java")
                guard FileManager.default.isExecutableFile(atPath: java.path) else { continue }
                guard !found.contains(where: { $0.javaHome == javaHome }) else { continue }
                let version = readVersion(at: java) ?? "17"
                let major = Int(version.split(separator: ".").first.map(String.init) ?? "17") ?? 17
                found.append(Runtime(java: java, javaHome: javaHome, majorVersion: major, fullVersion: version))
            }
        }

        return found.sorted { $0.majorVersion < $1.majorVersion }
    }

    /// The Java version reported by a runtime.
    func readVersion(at java: URL) -> String? {
        let process = Process()
        process.executableURL = java
        process.arguments = ["-version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let range = output.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) else { return nil }
        return String(output[range])
    }

    /// The version of the runtime that would be used for a Minecraft version.
    func version(minimumMajor: Int = 17) -> String? {
        guard let java = locate(minimumMajor: minimumMajor) else { return nil }
        return readVersion(at: java)
    }
}
