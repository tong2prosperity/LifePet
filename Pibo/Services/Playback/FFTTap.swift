import Foundation
import AVFAudio

@MainActor
final class FFTTap {
    typealias BinsHandler = @Sendable ([Float]) -> Void

    private weak var node: AVAudioNode?
    private var handler: BinsHandler?

    func install(on node: AVAudioNode, onBins: @escaping BinsHandler) {
        self.node = node
        self.handler = onBins
        // TODO: installTap + vDSP FFT. Call `onBins` with magnitude bins on each buffer.
    }

    func remove() {
        node?.removeTap(onBus: 0)
        node = nil
        handler = nil
    }
}
