import Foundation
import AVFoundation
import UIKit
import Capacitor

@objc(PoiAlertPlugin)
public class PoiAlertPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "PoiAlertPlugin"
    public let jsName = "PoiAlert"

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "flash", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise)
    ]

    private var warningTask: Task<Void, Never>?
    private var originalBrightness: CGFloat?
    private var audioPlayer: AVAudioPlayer?
    private var warningID = 0

    @objc func flash(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.startWarning()
            call.resolve()
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.stopWarning()
            call.resolve()
        }
    }

    @MainActor
    private func startWarning() {
        stopWarning()

        originalBrightness = UIScreen.main.brightness
        playWarningSound()
        let id = warningID

        warningTask = Task { @MainActor in
            for step in 0..<10 {
                if Task.isCancelled { return }

                UIScreen.main.brightness = step % 2 == 0 ? 1.0 : 0.15
                setTorch(step < 6 && step % 2 == 0)

                try? await Task.sleep(nanoseconds: 180_000_000)
            }

            if !Task.isCancelled && id == warningID {
                finishWarning()
                warningTask = nil
            }
        }
    }

    @MainActor
    private func stopWarning() {
        warningID += 1
        warningTask?.cancel()
        warningTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        finishWarning()
    }

    @MainActor
    private func finishWarning() {
        setTorch(false)

        if let brightness = originalBrightness {
            UIScreen.main.brightness = brightness
            originalBrightness = nil
        }
    }

    private func setTorch(_ enabled: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }

        do {
            try device.lockForConfiguration()

            if enabled {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }

            device.unlockForConfiguration()
        } catch {
            NSLog("PoiAlert: Torch error: \(error)")
        }
    }

    private func playWarningSound() {
        guard let url = Bundle.main.url(
            forResource: "poi-warning",
            withExtension: "wav"
        ) else {
            NSLog("PoiAlert: Warnton nicht gefunden")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )

            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

        } catch {
            NSLog("PoiAlert: Audiofehler: \(error)")
        }
    }

    public override func load() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopWarning()
            }
        }
    }
}
