
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

    private func startWarning() {
        stopWarning()

        originalBrightness = UIScreen.main.brightness

        warningTask = Task { @MainActor in
            // 3 Taschenlampenblitze und 5 Displayblitze
            for step in 0..<10 {
                if Task.isCancelled { break }

                let displayOn = step % 2 == 0
                UIScreen.main.brightness = displayOn ? 1.0 : 0.15

                // 3 Blitzimpulse in den ersten 6 Schritten
                if step < 6 {
                    setTorch(step % 2 == 0)
                } else {
                    setTorch(false)
                }

                try? await Task.sleep(for: .milliseconds(180))
            }

            finishWarning()
        }
    }

    private func stopWarning() {
        warningTask?.cancel()
        warningTask = nil
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
}
