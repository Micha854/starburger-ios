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
