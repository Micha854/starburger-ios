
import Foundation
import UIKit
import CoreLocation
import Capacitor
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit

@objc(NativeNavigationPlugin)
public class NativeNavigationPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "NativeNavigationPlugin"
    public let jsName = "NativeNavigation"

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise)
    ]

    private let locationManager = CLLocationManager()
    private var navigationProvider: MapboxNavigationProvider?

    @objc func start(_ call: CAPPluginCall) {
        guard let latitude = call.getDouble("latitude"),
              let longitude = call.getDouble("longitude"),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            call.reject("Ungültige Zielkoordinaten")
            return
        }

        DispatchQueue.main.async {
            guard let origin = self.locationManager.location?.coordinate else {
                self.locationManager.requestWhenInUseAuthorization()
                call.reject("GPS-Position nicht verfügbar. Standortfreigabe prüfen und erneut versuchen.")
                return
            }

            let destination = CLLocationCoordinate2D(
                latitude: latitude,
                longitude: longitude
            )

            let provider = MapboxNavigationProvider(coreConfig: .init())
            self.navigationProvider = provider

            let mapboxNavigation = provider.mapboxNavigation

            let options = NavigationRouteOptions(
                coordinates: [origin, destination]
            )

            let request = mapboxNavigation.routingProvider()
                .calculateRoutes(options: options)

            Task { @MainActor in
                switch await request.result {
                case .failure(let error):
                    self.navigationProvider = nil
                    call.reject("Routenberechnung fehlgeschlagen: \(error.localizedDescription)")

                case .success(let routes):
                    let navigationOptions = NavigationOptions(
                        mapboxNavigation: mapboxNavigation,
                        voiceController: provider.routeVoiceController,
                        eventsManager: provider.eventsManager()
                    )

                    let controller = NavigationViewController(
                        navigationRoutes: routes,
                        navigationOptions: navigationOptions
                    )

                    controller.modalPresentationStyle = .fullScreen

                    guard let viewController = self.bridge?.viewController else {
                        self.navigationProvider = nil
                        call.reject("Capacitor ViewController nicht verfügbar")
                        return
                    }

                    viewController.present(controller, animated: true)
                    call.resolve()
                }
            }
        }
    }
}
