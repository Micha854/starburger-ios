import UIKit
import Capacitor

class ViewController: CAPBridgeViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // WebView bis an die Bildschirmränder anzeigen
        webView?.scrollView.contentInsetAdjustmentBehavior = .never
    }

    override open func capacitorDidLoad() {
        super.capacitorDidLoad()
        bridge?.registerPluginInstance(PoiAlertPlugin())
    }
}
