import Foundation
import Capacitor

@objc(NativeNavigationPlugin)
public class NativeNavigationPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "NativeNavigationPlugin"
    public let jsName = "NativeNavigation"

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise)
    ]

    @objc func start(_ call: CAPPluginCall) {
        guard let latitude = call.getDouble("latitude"),
              let longitude = call.getDouble("longitude"),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            call.reject("Ungültige Zielkoordinaten")
            return
        }

        call.reject("Native Navigation ist noch nicht initialisiert")
    }
}