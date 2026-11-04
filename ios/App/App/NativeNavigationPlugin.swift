
import Foundation
import UIKit
import CoreLocation
import Capacitor
import MapboxDirections
import MapboxNavigationCore
import MapboxNavigationUIKit
import MapboxMaps

@objc(NativeNavigationPlugin)
public class NativeNavigationPlugin: CAPPlugin, CAPBridgedPlugin, NavigationViewControllerDelegate {

    public let identifier = "NativeNavigationPlugin"
    public let jsName = "NativeNavigation"

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateMarkers", returnType: CAPPluginReturnPromise)
    ]

    private let locationManager = CLLocationManager()
    private var navigationProvider: MapboxNavigationProvider?
    private weak var activeNavigationController: NavigationViewController?
    private var settingsButton: UIButton?
    private var loadingOverlay: UIView?
    private var nativeMarkers: [[String: Any]] = []
    private var markerManager: PointAnnotationManager?

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

            self.showLoading(on: self.bridge?.viewController?.view)

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
                    self.hideLoading()
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
                    case "day":
                        controller.overrideUserInterfaceStyle = .light
                    case "night":
                        controller.overrideUserInterfaceStyle = .dark
                    default:
                        controller.overrideUserInterfaceStyle = .unspecified
                    }

                    self.addSettingsButton(to: controller)
                    self.localizeResumeButton(in: controller.view)

                    guard let viewController = self.bridge?.viewController else {
                        self.hideLoading()
                        self.activeNavigationController = nil
                        self.settingsButton = nil
                        self.navigationProvider = nil
                        call.reject("Capacitor ViewController nicht verfügbar")
                        return
                    }

                    viewController.present(controller, animated: true) {
                        self.localizeResumeButton(in: controller.view)
                        self.renderNativeMarkers()
                        self.hideLoading()
                        call.resolve()
                    }
                }
            }
        }
    }

    public func navigationViewControllerDidDismiss(
        _ navigationViewController: NavigationViewController,
        byCanceling canceled: Bool
    ) {
        Task { @MainActor in
            navigationViewController.dismiss(animated: true) { [weak self] in
                self?.markerManager = nil
                self?.hideLoading()
                self?.settingsButton = nil
                self?.activeNavigationController = nil
                self?.navigationProvider = nil
            }
        }
    }

    @objc func updateMarkers(_ call: CAPPluginCall) {
        guard let markers = call.getArray("markers") as? [[String: Any]] else {
            call.reject("Ungültige Markerdaten")
            return
        }

        DispatchQueue.main.async {
            self.nativeMarkers = markers
            self.renderNativeMarkers()
            call.resolve()
        }
    }

    private func renderNativeMarkers() {
        guard let controller = activeNavigationController else { return }

        let mapView = controller.navigationMapView.mapView

        if markerManager == nil {
            markerManager = mapView.annotations.makePointAnnotationManager()
        }

        var annotations: [PointAnnotation] = []

        for marker in nativeMarkers {
            guard let id = marker["id"] as? String,
                let lat = marker["latitude"] as? Double,
                let lng = marker["longitude"] as? Double,
                (-90...90).contains(lat),
                (-180...180).contains(lng) else {
                continue
            }

            let type = marker["type"] as? String ?? ""
            let title = marker["title"] as? String ?? ""

            var annotation = PointAnnotation(
                id: id,
                coordinate: CLLocationCoordinate2D(
                    latitude: lat,
                    longitude: lng
                )
            )

            annotation.image = .init(
                image: makeMarkerImage(type: type),
                name: "starburger-\(type)"
            )

            annotation.textField = title
            annotation.textSize = 11
            annotation.textOffset = [0, 1.8]
            annotation.textColor = StyleColor(.white)
            annotation.textHaloColor = StyleColor(.black)
            annotation.textHaloWidth = 1

            annotations.append(annotation)
        }

        markerManager?.annotations = annotations
    }

    private func makeMarkerImage(type: String) -> UIImage {
        let color: UIColor
        let symbol: String

        switch type {
        case "poi":
            color = .systemRed
            symbol = "camera.fill"

        case "fahrer":
            color = .systemGreen
            symbol = "car.fill"

        case "order":
            color = .systemOrange
            symbol = "bag.fill"

        case "starburger", "base":
            color = .systemBlue
            symbol = "house.fill"

        default:
            color = .systemGray
            symbol = "mappin"
        }

        let size = CGSize(width: 38, height: 38)

        return UIGraphicsImageRenderer(size: size).image { _ in {
            let rect = CGRect(origin: .zero, size: size)

            color.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()

            let config = UIImage.SymbolConfiguration(
                pointSize: 19,
                weight: .semibold
            )

            let image = UIImage(
                systemName: symbol,
                withConfiguration: config
            )?.withTintColor(.white, renderingMode: .alwaysOriginal)

            image?.draw(in: CGRect(x: 9, y: 9, width: 20, height: 20))
        }}
    }

    private func showLoading(on parent: UIView?) {
        guard let parent = parent else { return }

        let overlay = UIView(frame: parent.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.65)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()

        let label = UILabel()
        label.text = "Navigation wird geladen …"
        label.textColor = .white

        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)
        overlay.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])

        parent.addSubview(overlay)
        loadingOverlay = overlay
    }

    private func hideLoading() {
        loadingOverlay?.removeFromSuperview()
        loadingOverlay = nil
    }

    private func localizeResumeButton(in view: UIView) {
        for subview in view.subviews {
            if let button = subview as? UIButton,
               button.title(for: .normal) == "Resume" {
                button.setTitle("Zurück zur Route", for: .normal)
            }

            localizeResumeButton(in: subview)
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
            button.trailingAnchor.constraint(
                equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor,
                constant: -12
            ),
            button.topAnchor.constraint(
                equalTo: controller.view.safeAreaLayoutGuide.topAnchor,
                constant: 110
            ),
            button.widthAnchor.constraint(equalToConstant: 52),
            button.heightAnchor.constraint(equalToConstant: 52)
        ])

        settingsButton = button
    }

    @objc private func showSettings() {
        guard let controller = activeNavigationController else { return }

        let sheet = UIAlertController(
            title: "Navigationseinstellungen",
            message: "Kartenansicht und Navigation",
            preferredStyle: .actionSheet
        )

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
            self.showSettingsInfo(
                "Sprache",
                "Die Routenberechnung verwendet Deutsch (de-DE). Für die vollständige Übersetzung der Mapbox-Oberfläche muss auch die iOS-App-Lokalisierung Deutsch enthalten."
            )
        })

        sheet.addAction(UIAlertAction(title: "Sprachausgabe", style: .default) { _ in
            self.showSettingsInfo(
                "Sprachausgabe",
                "Die Sprachausgabe lässt sich über das Lautsprechersymbol in der Navigation ein- oder ausschalten."
            )
        })

        sheet.addAction(UIAlertAction(title: "Kartenansicht", style: .default) { _ in
            self.showSettingsInfo(
                "Kartenansicht",
                "Die Kartenkamera lässt sich während der Navigation über die vorhandenen Mapbox-Kartenschaltflächen steuern."
            )
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

        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }
}
