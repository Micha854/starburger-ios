
import UIKit
import Capacitor

class ViewController: CAPBridgeViewController {

    override open func capacitorDidLoad() {
        super.capacitorDidLoad()
        bridge?.registerPluginInstance(PoiAlertPlugin())
    }
}
