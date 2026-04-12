import SwiftUI
import WidgetKit

@main
struct EdgeControlWidgetBundle: WidgetBundle {
    var body: some Widget {
        SystemGaugeWidget()
        TemperatureWidget()
        DiskIOWidget()
        NetworkWidget()
        WiFiWidget()
        CICDWidget()
        PluginDesktopWidget()
    }
}
