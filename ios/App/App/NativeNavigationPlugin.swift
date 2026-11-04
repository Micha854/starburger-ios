
import Foundation
import UIKit
import CoreLocation
import Capacitor
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit

@objc(NativeNavigationPlugin)
public class NativeNavigationPlugin: CAPPlugin, CAPBridgedPlugin, NavigationViewControllerDelegate {

    public let identifier = "NativeNavigationPlugin"
    public let jsName = "NativeNavigation"

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise)
    ]

    private let locationManager = CLLocationManager()
    private var navigationProvider: MapboxNavigationProvider?
    private weak var activeNavigationController: NavigationViewController?
    private var settingsButton: UIButton?


    @objc func start(_ call: CAPPluginCall) {
        guard let latitude = call.getDouble("latitude"),
              let longitude = call.getDouble("longitude"),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            call.reject("Ungültige Zielkoordinaten")
            return
        }

        DispatchQueue.main.async {
            guard self.navigationProvider == nil, self.activeNavigationController == nil else {
                call.reject("Navigation ist bereits aktiv")
                return
            }

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

            options.locale = Locale(identifier: "de-DE")

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
                        eventsManager: provider.eventsManager(),
                        styles: [StandardDayStyle(), StandardNightStyle()]
                    )

                    let controller = NavigationViewController(
                        navigationRoutes: routes,
                        navigationOptions: navigationOptions
                    )

                    controller.modalPresentationStyle = .fullScreen
                    controller.delegate = self
                    controller.showsReportFeedback = false
                    controller.usesNightStyleInDarkMode = true
                    self.activeNavigationController = controller
                    switch UserDefaults.standard.string(forKey: "sb_nav_theme") {
                    case "day": controller.overrideUserInterfaceStyle = .light
                    case "night": controller.overrideUserInterfaceStyle = .dark
                    default: controller.overrideUserInterfaceStyle = .unspecified
                    }
                    self.addSettingsButton(to: controller)

                    guard let viewController = self.bridge?.viewController else {
                        self.activeNavigationController = nil
                        self.settingsButton = nil
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

    public func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
        Task { @MainActor in
            navigationViewController.dismiss(animated: true) { [weak self] in
                self?.settingsButton = nil
                self?.activeNavigationController = nil
                self?.navigationProvider = nil
            }
        }
    }

    private func addSettingsButton(to controller: NavigationViewController) {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 26
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Navigationseinstellungen"
        button.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        controller.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 110),
            button.widthAnchor.constraint(equalToConstant: 52),
            button.heightAnchor.constraint(equalToConstant: 52)
        ])
        settingsButton = button
    }

    @objc private func showSettings() {
        guard let controller = activeNavigationController else { return }
        let sheet = UIAlertController(title: "Navigationseinstellungen", message: "Kartenansicht und Navigation", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Tagmodus", style: .default) { _ in
            controller.overrideUserInterfaceStyle = .light
            UserDefaults.standard.set("day", forKey: "sb_nav_theme")
        })
        sheet.addAction(UIAlertAction(title: "Nachtmodus", style: .default) { _ in
            controller.overrideUserInterfaceStyle = .dark
            UserDefaults.standard.set("night", forKey: "sb_nav_theme")
        })
        sheet.addAction(UIAlertAction(title: "Automatisch", style: .default) { _ in
            controller.overrideUserInterfaceStyle = .unspecified
            UserDefaults.standard.set("auto", forKey: "sb_nav_theme")
        })
        sheet.addAction(UIAlertAction(title: "Sprache: Deutsch", style: .default) { _ in
            self.showSettingsInfo("Sprache", "Die Routenberechnung verwendet Deutsch (de-DE). Für die vollständige Übersetzung der Mapbox-Oberfläche muss auch die iOS-App-Lokalisierung Deutsch enthalten.")
        })
        sheet.addAction(UIAlertAction(title: "Sprachausgabe", style: .default) { _ in
            self.showSettingsInfo("Sprachausgabe", "Die Sprachausgabe lässt sich über das Lautsprechersymbol in der Navigation ein- oder ausschalten.")
        })
        sheet.addAction(UIAlertAction(title: "Kartenansicht", style: .default) { _ in
            self.showSettingsInfo("Kartenansicht", "Die Kartenkamera lässt sich während der Navigation über die vorhandenen Mapbox-Kartenschaltflächen steuern.")
        })
        sheet.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = settingsButton
            popover.sourceRect = settingsButton?.bounds ?? .zero
        }
        controller.present(sheet, animated: true)
    }

    private func showSettingsInfo(_ title: String, _ message: String) {
        guard let controller = activeNavigationController else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }

}
