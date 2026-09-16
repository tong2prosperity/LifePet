import PiboCore
import PiboCoreFFI

/// Core's shared UTF-8 text hash (the one HarmonyOS feeds into
/// `pibo_companion_select_prompt`), so both platforms turn the same seed text
/// into the same selection opportunity.
enum PiboCoreSpeechHash {
    static func text(_ text: String) -> UInt64 {
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            pibo_speech_hash_text(buffer.baseAddress, buffer.count)
        }
    }
}
