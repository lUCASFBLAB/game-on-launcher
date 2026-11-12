import Foundation
import AVFoundation
import AppKit

/// Plays a background music track in a loop.
@MainActor
final class MusicPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var trackName = "Nenhuma faixa"
    @Published var volume: Double = 0.4

    private var player: AVAudioPlayer?
    private var fileURL: URL?

    /// Folder where imported tracks are stored.
    private var folder: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let result = base.appendingPathComponent("GameOnLauncher/Music", isDirectory: true)
        FileHelper.ensureDirectory(result)
        return result
    }

    /// Imports a track and starts playing it.
    func importTrack(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let destination = folder.appendingPathComponent("track-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)")
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            fileURL = destination
            trackName = destination.deletingPathExtension().lastPathComponent
            configure()
            play()
        } catch {
            trackName = "Não foi possível importar a faixa"
        }
    }

    /// Restores a track that was saved earlier.
    func restore(path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        fileURL = url
        trackName = url.deletingPathExtension().lastPathComponent
        configure()
    }

    /// The saved path of the current track.
    var savedPath: String { fileURL?.path ?? "" }

    /// Starts or resumes playback.
    func play() {
        guard let player else { return }
        if !player.isPlaying {
            player.play()
            isPlaying = true
        }
    }

    /// Pauses playback.
    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Toggles playback.
    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Stops playback and releases the file.
    func stop() {
        player?.stop()
        isPlaying = false
    }

    /// Removes the current track.
    func clear() {
        stop()
        if let fileURL { FileHelper.remove(fileURL) }
        fileURL = nil
        player = nil
        trackName = "Nenhuma faixa"
    }

    private func configure() {
        guard let fileURL else { return }
        do {
            let audio = try AVAudioPlayer(contentsOf: fileURL)
            audio.numberOfLoops = -1
            audio.volume = Float(volume)
            audio.prepareToPlay()
            player = audio
        } catch {
            player = nil
            trackName = "Formato de áudio não suportado"
        }
    }

    /// Keeps the volume in sync with the player.
    func setVolume(_ value: Double) {
        volume = value
        player?.volume = Float(value)
    }
}
