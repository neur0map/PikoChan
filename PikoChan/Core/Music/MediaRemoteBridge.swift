import AppKit

// MARK: - MediaRemote Private Framework Bridge
//
// Loads MediaRemote.framework at runtime via dlopen/dlsym.
// This gives us Now Playing info from ANY app (Spotify, Apple Music, browser, etc.)

enum MRCommand: UInt32 {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

struct MediaRemoteBridge {

    static let shared = MediaRemoteBridge()

    private let handle: UnsafeMutableRawPointer?

    // Function pointers resolved once at init — use C-bridged types only.
    private let _registerForNotifications: (@convention(c) (DispatchQueue) -> Void)?
    private let _unregisterForNotifications: (@convention(c) () -> Void)?
    private let _getNowPlayingInfo: (@convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void)?
    private let _getNowPlayingAppIsPlaying: (@convention(c) (DispatchQueue, @escaping (DarwinBoolean) -> Void) -> Void)?
    private let _sendCommand: (@convention(c) (UInt32, CFDictionary?) -> DarwinBoolean)?

    // Notification names (loaded as string constants from the framework).
    let nowPlayingInfoDidChange: Notification.Name?
    let nowPlayingAppDidChange: Notification.Name?
    let nowPlayingAppIsPlayingDidChange: Notification.Name?

    var isAvailable: Bool { handle != nil }

    private init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        handle = dlopen(path, RTLD_NOW)

        guard let h = handle else {
            _registerForNotifications = nil
            _unregisterForNotifications = nil
            _getNowPlayingInfo = nil
            _getNowPlayingAppIsPlaying = nil
            _sendCommand = nil
            nowPlayingInfoDidChange = nil
            nowPlayingAppDidChange = nil
            nowPlayingAppIsPlayingDidChange = nil
            return
        }

        _registerForNotifications = Self.resolve(h, "MRMediaRemoteRegisterForNowPlayingNotifications")
        _unregisterForNotifications = Self.resolve(h, "MRMediaRemoteUnregisterForNowPlayingNotifications")
        _getNowPlayingInfo = Self.resolve(h, "MRMediaRemoteGetNowPlayingInfo")
        _getNowPlayingAppIsPlaying = Self.resolve(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        _sendCommand = Self.resolve(h, "MRMediaRemoteSendCommand")

        nowPlayingInfoDidChange = Self.notificationName(h, "kMRMediaRemoteNowPlayingInfoDidChangeNotification")
        nowPlayingAppDidChange = Self.notificationName(h, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification")
        nowPlayingAppIsPlayingDidChange = Self.notificationName(h, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
    }

    // MARK: - Public API

    func registerForNotifications() {
        _registerForNotifications?(.main)
    }

    func unregisterForNotifications() {
        _unregisterForNotifications?()
    }

    func getNowPlayingInfo(completion: @escaping ([String: Any]) -> Void) {
        guard let fn = _getNowPlayingInfo else {
            completion([:])
            return
        }
        fn(.main) { cfDict in
            let dict = cfDict as NSDictionary as? [String: Any] ?? [:]
            completion(dict)
        }
    }

    func getIsPlaying(completion: @escaping (Bool) -> Void) {
        guard let fn = _getNowPlayingAppIsPlaying else {
            completion(false)
            return
        }
        fn(.main) { darwinBool in
            completion(darwinBool.boolValue)
        }
    }

    @discardableResult
    func sendCommand(_ command: MRCommand) -> Bool {
        _sendCommand?(command.rawValue, nil).boolValue ?? false
    }

    // MARK: - Info Keys

    /// Standard MediaRemote info dictionary keys.
    static let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    static let albumKey = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let artworkDataKey = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let artworkMIMETypeKey = "kMRMediaRemoteNowPlayingInfoArtworkMIMEType"
    static let durationKey = "kMRMediaRemoteNowPlayingInfoDuration"
    static let elapsedTimeKey = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    static let playbackRateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"

    // MARK: - Private Helpers

    private static func resolve<T>(_ handle: UnsafeMutableRawPointer, _ symbol: String) -> T? {
        guard let ptr = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    private static func notificationName(_ handle: UnsafeMutableRawPointer, _ symbol: String) -> Notification.Name? {
        guard let ptr = dlsym(handle, symbol) else { return nil }
        // The symbol is a global `NSString *` — dlsym returns a pointer to the variable.
        let strPtr = ptr.assumingMemoryBound(to: NSString?.self)
        guard let nsStr = strPtr.pointee else { return nil }
        return Notification.Name(nsStr as String)
    }
}
