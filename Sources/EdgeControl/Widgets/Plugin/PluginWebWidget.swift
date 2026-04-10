import SwiftUI
import WebKit

/// A DashboardWidget implementation that renders a plugin's HTML via WKWebView.
/// Receives system data via JS bridge and pushes updates periodically.
public final class PluginWebWidget: DashboardWidget {
    public let widgetId: String
    public let displayName: String
    public let description: String
    public let iconName: String
    public let category: WidgetCategory = .plugin
    public let supportedSizes: WidgetSizeRange
    public let defaultSize: WidgetSize
    public let configSchema: [ConfigSchemaEntry]
    public let defaultColors = WidgetColors(primary: .cyan)

    let pluginId: String
    let htmlFile: String
    let permissions: [PluginPermission]
    let refreshInterval: Double
    let bundlePath: URL

    public init(
        pluginId: String,
        widgetDef: PluginWidgetDef,
        permissions: [PluginPermission],
        bundlePath: URL
    ) {
        self.pluginId = pluginId
        self.widgetId = "\(pluginId).\(widgetDef.id)"
        self.displayName = widgetDef.name
        self.description = widgetDef.description ?? ""
        self.iconName = widgetDef.icon ?? "puzzlepiece.extension"
        self.supportedSizes = widgetDef.sizeRange
        self.defaultSize = widgetDef.widgetSize
        self.htmlFile = widgetDef.htmlFile
        self.permissions = permissions
        self.refreshInterval = widgetDef.refreshInterval ?? 2.0
        self.bundlePath = bundlePath

        // Convert plugin config schema to native config schema
        self.configSchema = (widgetDef.configSchema ?? []).map { field in
            let fieldType: ConfigFieldType
            switch field.type {
            case "boolean": fieldType = .toggle
            case "number": fieldType = .stepper
            case "color": fieldType = .colorPicker
            case "select": fieldType = .picker
            default: fieldType = .text
            }
            let defaultVal: ConfigValue
            switch field.defaultValue {
            case .bool(let v): defaultVal = .bool(v)
            case .number(let v): defaultVal = .double(v)
            case .string(let v): defaultVal = .string(v)
            }
            return ConfigSchemaEntry(key: field.key, label: field.label, type: fieldType, defaultValue: defaultVal)
        }
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        PluginWebWidgetView(widget: self, size: size, config: config)
    }
}

// MARK: - WebView Container

private struct PluginWebWidgetView: View {
    let widget: PluginWebWidget
    let size: WidgetSize
    let config: WidgetConfig
    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts

    var body: some View {
        PluginWebViewRepresentable(
            widget: widget,
            size: size,
            config: config,
            model: model
        )
        .widgetCard()
    }
}

// MARK: - NSViewRepresentable for WKWebView

private struct PluginWebViewRepresentable: NSViewRepresentable {
    let widget: PluginWebWidget
    let size: WidgetSize
    let config: WidgetConfig
    let model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(widget: widget, model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()

        // Inject the EdgeControl JS SDK before page loads
        let sdkScript = WKUserScript(
            source: Self.jsSdk(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(sdkScript)

        // Handle messages from plugin JS
        userContentController.add(context.coordinator, name: "edgecontrol")

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        // Load the plugin HTML — show error if missing
        let htmlURL = widget.bundlePath.appendingPathComponent(widget.htmlFile)
        if FileManager.default.fileExists(atPath: htmlURL.path) {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: widget.bundlePath)
        } else {
            let errorHTML = """
            <html><body style="background:#1a1a1a;color:#ff4444;font-family:-apple-system;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center;">
            <div><p style="font-size:14px;font-weight:700;">Plugin Error</p><p style="font-size:11px;color:#888;">Missing: \(widget.htmlFile)</p></div></body></html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }

        // Set navigation delegate for load error handling
        webView.navigationDelegate = context.coordinator

        // Start data push timer
        context.coordinator.startDataPush(config: self.config)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Push updated config when it changes
        context.coordinator.pushData(config: config)
    }

    // MARK: - JS SDK

    private static func jsSdk() -> String {
        """
        window.edgecontrol = {
            _listeners: {},
            _data: {},

            // Get current data snapshot
            get: function(key) {
                return key ? this._data[key] : this._data;
            },

            // Subscribe to data updates
            on: function(event, callback) {
                if (!this._listeners[event]) this._listeners[event] = [];
                this._listeners[event].push(callback);
            },

            // Unsubscribe
            off: function(event, callback) {
                if (!this._listeners[event]) return;
                this._listeners[event] = this._listeners[event].filter(function(cb) { return cb !== callback; });
            },

            // Internal: called by native bridge to push data
            _receive: function(data) {
                this._data = data;
                var listeners = this._listeners['update'] || [];
                for (var i = 0; i < listeners.length; i++) {
                    try { listeners[i](data); } catch(e) { console.error('EdgeControl plugin error:', e); }
                }
            },

            // Send message to native app
            send: function(action, payload) {
                window.webkit.messageHandlers.edgecontrol.postMessage({
                    action: action,
                    payload: payload || {}
                });
            },

            // Convenience accessors
            get theme() { return this._data.theme || {}; },
            get config() { return this._data.config || {}; },
            get system() { return this._data.system || {}; },
            get temperature() { return this._data.temperature || {}; },
            get network() { return this._data.network || {}; },
            get media() { return this._data.media || null; },
            get weather() { return this._data.weather || null; },
            get audio() { return this._data.audio || {}; },
            get bluetooth() { return this._data.bluetooth || {}; },
            get processes() { return this._data.processes || []; },
            get diskIO() { return this._data.diskIO || {}; }
        };

        // Notify plugin that SDK is ready
        document.addEventListener('DOMContentLoaded', function() {
            if (window.edgecontrol._listeners['ready']) {
                window.edgecontrol._listeners['ready'].forEach(function(cb) { cb(); });
            }
        });
        """
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let widget: PluginWebWidget
        let model: AppModel
        weak var webView: WKWebView?
        private var timer: Timer?
        private lazy var dataBridge = PluginDataBridge(model: model)

        init(widget: PluginWebWidget, model: AppModel) {
            self.widget = widget
            self.model = model
        }

        func cleanup() {
            timer?.invalidate()
            timer = nil
        }

        func startDataPush(config: WidgetConfig) {
            timer?.invalidate()
            // Initial push after short delay for page load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.pushData(config: config)
            }
            timer = Timer.scheduledTimer(withTimeInterval: widget.refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pushData(config: config)
                }
            }
        }

        func pushData(config: WidgetConfig) {
            let payload = dataBridge.buildDataPayload(
                permissions: widget.permissions,
                widgetConfig: config
            )
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let js = "window.edgecontrol._receive(\(jsonString));"
            webView?.evaluateJavaScript(js)
        }

        // Handle WebView load errors
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showError(in: webView, message: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showError(in: webView, message: error.localizedDescription)
        }

        private func showError(in webView: WKWebView, message: String) {
            let errorHTML = """
            <html><body style="background:#1a1a1a;color:#ff4444;font-family:-apple-system;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center;">
            <div><p style="font-size:14px;font-weight:700;">Plugin Error</p><p style="font-size:11px;color:#888;">\(message)</p></div></body></html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }

        // Handle messages from plugin JS
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            switch action {
            case "log":
                if let msg = body["payload"] as? [String: Any], let text = msg["text"] as? String {
                    print("[Plugin:\(widget.pluginId)] \(text)")
                }
            default:
                break
            }
        }
    }
}
