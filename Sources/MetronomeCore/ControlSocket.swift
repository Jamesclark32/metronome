import Darwin
import Foundation

/// The Unix domain socket the app listens on. Its directory is mode 0700 and the
/// socket 0600, and the server also checks each peer's user id, so only the
/// current user can connect.
public enum ControlSocket {
    /// `$METRONOME_SOCKET`, or `~/Library/Application Support/Metronome/control.sock`.
    public static var defaultPath: String {
        if let path = ProcessInfo.processInfo.environment["METRONOME_SOCKET"], !path.isEmpty { return path }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Metronome/control.sock").path
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = path.utf8CString.map { UInt8(bitPattern: $0) }
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw MetronomeError("Socket path is too long: \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    static func withSockaddr<T>(_ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    /// Reads up to the first newline or end of stream.
    static func readLine(_ fd: Int32, limit: Int = 1 << 20) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < limit {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
            if let newline = data.firstIndex(of: UInt8(ascii: "\n")) { return data[..<newline] }
        }
        return data
    }

    static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 && errno == EINTR { continue }
                if written <= 0 { return }
                offset += written
            }
        }
    }

    static func setTimeouts(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, size)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, size)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }
}

/// Serves one JSON request per connection: read a line, answer a line, close.
public final class ControlServer: @unchecked Sendable {
    public let path: String
    private let handler: @Sendable (Data) -> Data
    private var listener: Int32 = -1

    public init(path: String = ControlSocket.defaultPath, handler: @escaping @Sendable (Data) -> Data) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(directory, 0o700)
        // A socket left by a crashed or older instance; the newest app takes over.
        unlink(path)

        var addr = try ControlSocket.address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MetronomeError("socket() failed: \(String(cString: strerror(errno)))") }
        let oldMask = umask(0o177)  // create the socket as 0600 with no window where it is wider
        let bound = ControlSocket.withSockaddr(&addr) { bind(fd, $0, $1) }
        umask(oldMask)
        guard bound == 0, listen(fd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw MetronomeError("Can't listen on \(path): \(message)")
        }
        chmod(path, 0o600)
        listener = fd

        let thread = Thread { [self] in acceptLoop(fd) }
        thread.name = "Metronome control socket"
        thread.start()
    }

    private func acceptLoop(_ listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == ECONNABORTED { continue }
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [handler] in
                defer { close(client) }
                var uid: uid_t = 0
                var gid: gid_t = 0
                guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
                ControlSocket.setTimeouts(client, seconds: 5)
                let request = ControlSocket.readLine(client)
                ControlSocket.writeAll(client, handler(request) + Data("\n".utf8))
            }
        }
    }
}

public enum ControlClient {
    public static let notRunning = "Metronome is not running. Start it with: open -a Metronome"

    public static func send(_ request: ControlRequest, path: String = ControlSocket.defaultPath) throws -> ControlResponse {
        var addr = try ControlSocket.address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MetronomeError("socket() failed: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        ControlSocket.setTimeouts(fd, seconds: 10)
        guard ControlSocket.withSockaddr(&addr, { connect(fd, $0, $1) }) == 0 else {
            if [ENOENT, ECONNREFUSED].contains(errno) { throw MetronomeError(notRunning) }
            throw MetronomeError("Can't connect to \(path): \(String(cString: strerror(errno)))")
        }
        ControlSocket.writeAll(fd, try ControlJSON.encoder.encode(request) + Data("\n".utf8))
        let reply = ControlSocket.readLine(fd)
        guard !reply.isEmpty else { throw MetronomeError("Metronome closed the connection without answering.") }
        return try ControlJSON.decoder.decode(ControlResponse.self, from: reply)
    }
}
