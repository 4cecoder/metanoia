import AVFoundation

@Observable
class TTSService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    var isPlaying = false
    var isPaused = false
    var currentVerse: Verse?
    var currentText: String = ""
    
    private var speechCompleteHandler: (() -> Void)?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }
    
    func speak(
        _ text: String,
        voice: String = "com.apple.speech.synthesis.language.en-US",
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitch: Float = 1.0
    ) {
        stop()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1
        
        if let voiceObj = AVSpeechSynthesizerVoice(identifier: voice) {
            utterance.voice = voiceObj
        } else if let fallbackVoice = AVSpeechSynthesizerVoice(language: "en-US") {
            utterance.voice = fallbackVoice
        }
        
        currentText = text
        isPlaying = true
        isPaused = false
        synthesizer.speak(utterance)
    }
    
    func speakVerse(_ verse: Verse, voice: String = "com.apple.speech.synthesis.language.en-US", rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        currentVerse = verse
        let text = "\(verse.text)"
        speak(text, voice: voice, rate: rate)
    }
    
    func speakChapter(_ verses: [Verse], voice: String = "com.apple.speech.synthesis.language.en-US", rate: Float = AVSpeechUtteranceDefaultSpeechRate, onComplete: (() -> Void)? = nil) {
        guard !verses.isEmpty else {
            onComplete?()
            return
        }
        
        speechCompleteHandler = onComplete
        let fullText = verses.map { "\($0.reference) \($0.text)" }.joined(separator: "\n\n")
        currentVerse = verses.first
        speak(fullText, voice: voice, rate: rate)
    }
    
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlaying = false
        isPaused = false
        currentVerse = nil
        currentText = ""
    }
    
    func pause() {
        guard synthesizer.isSpeaking && !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }
    
    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
    }
    
    func togglePlayback(text: String, voice: String = "com.apple.speech.synthesis.language.en-US", rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        if isPaused {
            resume()
        } else if isPlaying {
            pause()
        } else {
            speak(text, voice: voice, rate: rate)
        }
    }
    
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }
}

extension TTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isPlaying = true
        isPaused = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isPlaying = false
        isPaused = false
        currentVerse = nil
        speechCompleteHandler?()
        speechCompleteHandler = nil
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        isPaused = true
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        isPaused = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Could track current word position here
    }
}
