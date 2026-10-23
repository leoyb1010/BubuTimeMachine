// Bubu lesson narrator: renders one line with the best installed Apple voice
// (Siri natural / Premium / Enhanced) at the voice's native sample rate, no gain.
// usage: swift tts_helper.swift <preferred-ids,comma> <lang zh-CN|en-US> <rate> <pitch> <text-file> <out.caf>
// Prints the chosen voice identifier. Exit 3 = no high-quality voice installed.
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count == 7, let rate = Float(args[3]), let pitch = Float(args[4]),
      let text = try? String(contentsOfFile: args[5], encoding: .utf8), !text.isEmpty else { exit(2) }

let voices = AVSpeechSynthesisVoice.speechVoices()
let preferred = args[1].split(separator: ",").compactMap { id in voices.first { $0.identifier == String(id) } }
let language = args[2]
let fallback = voices.filter { $0.language == language && $0.quality != .default }
    .sorted { $0.quality.rawValue > $1.quality.rawValue }
guard let voice = preferred.first ?? fallback.first else { exit(3) }

let utterance = AVSpeechUtterance(string: text)
utterance.voice = voice
utterance.rate = rate
utterance.pitchMultiplier = pitch
utterance.volume = 1.0

let synthesizer = AVSpeechSynthesizer()
var file: AVAudioFile?
var frames: AVAudioFrameCount = 0
var finished = false
synthesizer.write(utterance) { buffer in
    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
    if pcm.frameLength == 0 { finished = true; return }
    if file == nil {
        file = try? AVAudioFile(forWriting: URL(fileURLWithPath: args[6]), settings: pcm.format.settings,
                                commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
    }
    try? file?.write(from: pcm)
    frames += pcm.frameLength
}
let deadline = Date().addingTimeInterval(40)
while !finished && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
file = nil
guard finished, frames > 0 else { exit(1) }
print(voice.identifier)
