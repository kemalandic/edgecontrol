import SwiftUI
import WebKit
import UserNotifications
import OSLog

private let pluginLog = Logger(subsystem: "ai.pakslab.edgecontrol", category: "Plugin")

/// Writes plugin log entries to ~/Library/Application Support/EdgeControl/plugin.log
enum PluginFileLogger {
    private static let logURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("EdgeControl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("plugin.log")
    }()

    nonisolated(unsafe) static let dateFormatter = ISO8601DateFormatter()
    private static let maxLogSize = 5_242_880 // 5 MB

    static func log(_ pluginId: String, _ message: String) {
        // Rotate if log exceeds 5 MB
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? UInt64, size > maxLogSize {
            try? FileManager.default.removeItem(at: logURL)
        }
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(pluginId)] \(message)\n"
        pluginLog.info("[\(pluginId)] \(message)")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }

    static func clear() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }
}

/// A DashboardWidget implementation that renders a plugin's HTML via WKWebView.
/// Receives system data via JS bridge and pushes updates periodically.
/// v2: Bidirectional communication, lifecycle events, action handlers, crash recovery.
public final class PluginWebWidget: DashboardWidget {
    public let widgetId: String
    public let displayName: String
    public let description: String
    public let iconName: String
    public let category: WidgetCategory = .plugin
    public let requiredServices: Set<ServiceKey>
    public let supportedSizes: WidgetSizeRange
    public let defaultSize: WidgetSize
    public let configSchema: [ConfigSchemaEntry]
    public let defaultColors = WidgetColors(primary: .cyan)

    let pluginId: String
    let htmlFile: String
    let permissions: [PluginPermission]
    let refreshInterval: Double
    let bundlePath: URL
    let allowedDomains: [String]?

    public init(
        pluginId: String,
        widgetDef: PluginWidgetDef,
        permissions: [PluginPermission],
        bundlePath: URL,
        allowedDomains: [String]? = nil
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
        self.refreshInterval = max(1.0, widgetDef.refreshInterval ?? 2.0)
        self.bundlePath = bundlePath
        self.allowedDomains = allowedDomains

        // Resolve required services from plugin permissions
        var services = Set<ServiceKey>()
        for perm in permissions {
            switch perm {
            case .systemMetrics: services.insert(.metrics)
            case .temperature: services.insert(.smc)
            case .network: services.insert(.network); services.insert(.wifi)
            case .processes: services.insert(.process)
            case .media: services.insert(.nowPlaying)
            case .bluetooth: services.insert(.bluetooth)
            case .audio: services.insert(.audio)
            case .weather: services.insert(.weather)
            case .diskIO: services.insert(.diskIO)
            case .notifications, .openURL, .clipboard, .storage, .networkAccess: break
            }
        }
        self.requiredServices = services

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
            return ConfigSchemaEntry(key: field.key, label: field.label, type: fieldType, defaultValue: defaultVal, options: field.options)
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
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @Environment(\.themeSettings) private var ts

    var body: some View {
        PluginWebViewRepresentable(
            widget: widget,
            size: size,
            config: config,
            model: model,
            themeSettings: ts
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
    let themeSettings: ThemeSettings

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

        // Inject CSS theme variables at document start
        let cssScript = WKUserScript(
            source: Self.themeCSSInjection(ts: themeSettings, widgetId: widget.widgetId),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(cssScript)

        // Inject initial widget size + theme data so they're available at ready time
        let pixelW = size.width * Int(GridConstants.cellWidth)
        let pixelH = size.height * Int(GridConstants.cellHeight)

        let dataBridge = PluginDataBridge(model: model)
        let themeDict = dataBridge.liveThemeData(ts: themeSettings, widgetId: widget.widgetId)
        let themeJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: themeDict),
           let str = String(data: data, encoding: .utf8) {
            themeJSON = str
        } else {
            themeJSON = "{}"
        }

        let initScript = WKUserScript(
            source: """
            window.edgecontrol._widgetSize = {width:\(size.width),height:\(size.height),pixelWidth:\(pixelW),pixelHeight:\(pixelH)};
            window.edgecontrol._data.theme = \(themeJSON);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(initScript)

        // Handle messages from plugin JS
        userContentController.add(context.coordinator, name: "edgecontrol")

        let webConfig = WKWebViewConfiguration()
        webConfig.userContentController = userContentController
        let webView = NonFirstResponderWebView(frame: .zero, configuration: webConfig)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.currentSize = size

        // Set navigation delegate for load error handling + crash recovery
        webView.navigationDelegate = context.coordinator
        context.coordinator.isVisible = true

        // Network security sandbox — rules compiled before HTML loads to prevent race condition
        if needsNetworkRules() {
            compileAndLoadWithRules(
                webConfig: webConfig,
                webView: webView,
                coordinator: context.coordinator
            )
        } else {
            loadPluginHTML(into: webView)
            context.coordinator.startDataPush(config: self.config, themeSettings: themeSettings)
        }

        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.isVisible = false
        coordinator.pushVisibilityChange(visible: false)
        coordinator.cleanup()
        // Remove script message handler to break retain cycle (WKUserContentController retains handler strongly)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "edgecontrol")
        webView.configuration.userContentController.removeAllUserScripts()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        // Detect theme change BEFORE updating stored values
        let themeChanged = coordinator.lastThemeSettings != themeSettings

        // Keep coordinator's config/theme up to date so timer uses fresh values
        coordinator.currentConfig = config
        coordinator.lastThemeSettings = themeSettings

        // Push updated config/data
        coordinator.pushData(config: config, themeSettings: themeSettings)

        // Detect size change → push resize event
        if coordinator.currentSize != size {
            let oldSize = coordinator.currentSize
            coordinator.currentSize = size
            if oldSize != nil {
                coordinator.pushResize(size: size)
            }
        }

        // Push themeChange event + update CSS variables
        if themeChanged {
            coordinator.pushThemeChange(ts: themeSettings)
            let cssUpdate = Self.themeCSSUpdate(ts: themeSettings, widgetId: widget.widgetId)
            webView.evaluateJavaScript(cssUpdate)
        }
    }

    // MARK: - Network Security Sandbox

    /// Whether this plugin needs network content rules compiled before loading.
    private func needsNetworkRules() -> Bool {
        let hasNetworkPermission = widget.permissions.contains(.networkAccess)
        let domains = widget.allowedDomains ?? []
        // Need rules if: no permission (block all), or has permission with specific domains
        // Don't need rules if: has permission with no domain restrictions
        return !hasNetworkPermission || !domains.isEmpty
    }

    /// Build the JSON rule list string for WKContentRuleList.
    private func buildNetworkRulesJSON() -> String? {
        let hasNetworkPermission = widget.permissions.contains(.networkAccess)
        let domains = widget.allowedDomains ?? []

        if !hasNetworkPermission {
            // "raw" covers fetch/XMLHttpRequest in WebKit Content Rule Lists
            return """
            [{"trigger":{"url-filter":".*","resource-type":["raw"]},"action":{"type":"block"}}]
            """
        } else if !domains.isEmpty {
            var rules: [[String: Any]] = [
                [
                    "trigger": ["url-filter": ".*", "resource-type": ["raw"]],
                    "action": ["type": "block"]
                ]
            ]
            for domain in domains {
                let escaped = domain.replacingOccurrences(of: ".", with: "\\\\.")
                rules.append([
                    "trigger": ["url-filter": "https?://([a-z0-9-]+\\\\.)*\(escaped)"],
                    "action": ["type": "ignore-previous-rules"]
                ])
            }
            guard let data = try? JSONSerialization.data(withJSONObject: rules),
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }
        return nil
    }

    /// Compile network rules first, then load HTML — prevents race condition.
    private func compileAndLoadWithRules(
        webConfig: WKWebViewConfiguration,
        webView: WKWebView,
        coordinator: Coordinator
    ) {
        guard let rulesJSON = buildNetworkRulesJSON() else {
            loadPluginHTML(into: webView)
            coordinator.startDataPush(config: self.config, themeSettings: themeSettings)
            return
        }

        PluginFileLogger.log(widget.pluginId, "NETWORK RULES JSON: \(rulesJSON)")
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "ec-network-\(widget.pluginId)",
            encodedContentRuleList: rulesJSON
        ) { [weak coordinator, widget, config, themeSettings] ruleList, error in
            Task { @MainActor in
                if let ruleList {
                    webConfig.userContentController.add(ruleList)
                }
                if let error {
                    PluginFileLogger.log(widget.pluginId, "NETWORK RULES ERROR: \(error) — code: \((error as NSError).code)")
                }
                // Load HTML only after rules are applied
                self.loadPluginHTML(into: webView)
                coordinator?.startDataPush(config: config, themeSettings: themeSettings)
            }
        }
    }

    /// Load the plugin's HTML file into the WebView.
    private func loadPluginHTML(into webView: WKWebView) {
        let htmlURL = widget.bundlePath.appendingPathComponent(widget.htmlFile).standardizedFileURL
        let bundlePath = widget.bundlePath.standardizedFileURL.path
        // Verify HTML file is within the plugin bundle (prevent path traversal)
        guard htmlURL.path.hasPrefix(bundlePath),
              FileManager.default.fileExists(atPath: htmlURL.path) else {
            webView.loadHTMLString(Self.errorHTML("Invalid or missing widget file"), baseURL: nil)
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: widget.bundlePath)
    }

    // MARK: - Error HTML

    private static func errorHTML(_ message: String) -> String {
        let safe = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <html><body style="background:#1a1a1a;color:#ff4444;font-family:-apple-system;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center;">
        <div><p style="font-size:14px;font-weight:700;">Plugin Error</p><p style="font-size:11px;color:#888;">\(safe)</p></div></body></html>
        """
    }

    private static func crashHTML() -> String {
        """
        <html><body style="background:#1a1a1a;color:#ff8800;font-family:-apple-system;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center;">
        <div><p style="font-size:14px;font-weight:700;">Plugin Crashed</p><p style="font-size:11px;color:#888;">Re-enable from Settings to restart.</p></div></body></html>
        """
    }

    // MARK: - Theme CSS

    /// Generate CSS custom properties injection script (atDocumentStart).
    /// Injects immediately if <head> exists, otherwise waits for DOMContentLoaded.
    /// This ensures CSS variables are available before plugin's ready handler fires.
    private static func themeCSSInjection(ts: ThemeSettings, widgetId: String) -> String {
        let css = buildThemeCSSString(ts: ts, widgetId: widgetId)
        return """
        (function() {
            var style = document.createElement('style');
            style.id = 'ec-theme-vars';
            style.textContent = ':root { \(css) }';
            document.documentElement.appendChild(style);
        })();
        """
    }

    /// Generate JS to update existing CSS custom properties (called on theme change).
    private static func themeCSSUpdate(ts: ThemeSettings, widgetId: String) -> String {
        let css = buildThemeCSSString(ts: ts, widgetId: widgetId)
        return """
        (function() {
            var el = document.getElementById('ec-theme-vars');
            if (el) { el.textContent = ':root { \(css) }'; }
            else {
                var s = document.createElement('style');
                s.id = 'ec-theme-vars';
                s.textContent = ':root { \(css) }';
                document.head.appendChild(s);
            }
        })();
        """
    }

    private static func buildThemeCSSString(ts: ThemeSettings, widgetId: String) -> String {
        let preset = ts.resolvedPreset
        let accent = ts.accentColor

        // Resolve widget colors
        let wp = ts.widgetColorOverrides[widgetId]?.primary ?? WidgetColor(ThemeColor.cyan)
        let ws = ts.widgetColorOverrides[widgetId]?.secondary
        let wt = ts.widgetColorOverrides[widgetId]?.tertiary

        let fontCSS: String
        switch ts.fontFamily {
        case .monospaced: fontCSS = "\"SF Mono\", \"Menlo\", monospace"
        case .serif: fontCSS = "\"New York\", \"Georgia\", serif"
        default: fontCSS = "-apple-system, BlinkMacSystemFont, sans-serif"
        }

        return [
            "--ec-accent: \(PluginColorHelpers.hexString(accent))",
            "--ec-bg-1: \(PluginColorHelpers.colorToCSS(preset.backgroundColors.first ?? .black))",
            "--ec-bg-2: \(PluginColorHelpers.colorToCSS(preset.backgroundColors.dropFirst().first ?? .black))",
            "--ec-bg-3: \(PluginColorHelpers.colorToCSS(preset.backgroundColors.last ?? .black))",
            "--ec-card-bg: \(PluginColorHelpers.colorToCSS(preset.cardBackground))",
            "--ec-text-primary: \(PluginColorHelpers.colorToCSS(preset.textPrimary))",
            "--ec-text-secondary: \(PluginColorHelpers.colorToCSS(preset.textSecondary))",
            "--ec-text-tertiary: \(PluginColorHelpers.colorToCSS(preset.textTertiary))",
            "--ec-border: \(PluginColorHelpers.colorToCSS(preset.border))",
            "--ec-widget-primary: \(PluginColorHelpers.hexString(wp))",
            "--ec-widget-secondary: \(ws.map { PluginColorHelpers.hexString($0) } ?? "transparent")",
            "--ec-widget-tertiary: \(wt.map { PluginColorHelpers.hexString($0) } ?? "transparent")",
            "--ec-font-scale: \(ts.fontScale)",
            "--ec-font-family: \(fontCSS)",
            "--ec-font-title: \(ts.fontSizeTitle * ts.fontScale)px",
            "--ec-font-value: \(ts.fontSizeValue * ts.fontScale)px",
            "--ec-font-label: \(ts.fontSizeLabel * ts.fontScale)px",
            "--ec-font-caption: \(ts.fontSizeCaption * ts.fontScale)px",
            "--ec-font-body: \(ts.fontSizeBody * ts.fontScale)px",
            "--ec-font-micro: \(ts.fontSizeMicro * ts.fontScale)px",
            "--ec-corner-radius: \(ts.widgetCornerRadius)px",
            "--ec-widget-opacity: \(ts.widgetOpacity)",
            "--ec-widget-gap: \(ts.widgetGap)px",
        ].joined(separator: "; ")
    }

    // MARK: - JS SDK

    private static func jsSdk() -> String {
        """
        window.edgecontrol = {
            _listeners: {},
            _data: {},
            _callbacks: {},
            _nextCallbackId: 1,

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

            // Internal: emit event to listeners
            _emit: function(event, data) {
                var listeners = this._listeners[event] || [];
                for (var i = 0; i < listeners.length; i++) {
                    try { listeners[i](data); } catch(e) { console.error('EdgeControl plugin error:', e); }
                }
            },

            // Internal: called by native bridge to push data
            _receive: function(data) {
                this._data = data;
                this._emit('update', data);
            },

            // Send message to native app
            send: function(action, payload) {
                window.webkit.messageHandlers.edgecontrol.postMessage({
                    action: action,
                    payload: payload || {}
                });
            },

            // Async send — returns a Promise resolved by native callback (10s timeout)
            _sendAsync: function(action, payload) {
                var self = this;
                return new Promise(function(resolve, reject) {
                    var id = String(self._nextCallbackId++);
                    var timer = setTimeout(function() {
                        delete self._callbacks[id];
                        reject(new Error('Timeout: no response for ' + action));
                    }, 10000);
                    self._callbacks[id] = { resolve: resolve, reject: reject, timer: timer };
                    var msg = Object.assign({}, payload || {});
                    msg._callbackId = id;
                    self.send(action, msg);
                });
            },

            // Native calls this to resolve a pending Promise
            _callback: function(id, result, error) {
                var cb = this._callbacks[id];
                if (!cb) return;
                clearTimeout(cb.timer);
                delete this._callbacks[id];
                if (error) { cb.reject(new Error(error)); }
                else { cb.resolve(result); }
            },

            // Lifecycle event handlers (called from native)
            _onResize: function(size) { this._emit('resize', size); },
            _onThemeChange: function(theme) { this._data.theme = theme; this._emit('themeChange', theme); },
            _onVisibilityChange: function(visible) { this._emit('visibilityChange', visible); },

            // Native action methods
            notify: function(title, body) { this.send('notify', { title: title, body: body || '' }); },
            openURL: function(url) { this.send('openURL', { url: url }); },
            copyToClipboard: function(text) { this.send('clipboard', { text: text }); },
            getWidgetSize: function() { return this._widgetSize || { width: 0, height: 0, pixelWidth: 0, pixelHeight: 0 }; },

            // Persistent storage (initialized after object creation, see below)
            storage: null,

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

        // Bind storage methods to parent object (avoids bare global reference)
        (function(ec) {
            ec.storage = {
                get: function(key) { return ec._sendAsync('storageGet', { key: key }); },
                set: function(key, value) { return ec._sendAsync('storageSet', { key: key, value: value }); },
                remove: function(key) { return ec._sendAsync('storageRemove', { key: key }); }
            };
        })(window.edgecontrol);

        // Notify plugin that SDK is ready
        document.addEventListener('DOMContentLoaded', function() {
            edgecontrol._emit('ready');
        });
        """
    }

    // MARK: - Coordinator

    @MainActor
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let widget: PluginWebWidget
        let model: AppModel
        weak var webView: WKWebView?
        private var timer: Timer?
        private lazy var dataBridge = PluginDataBridge(model: model)
        var currentSize: WidgetSize?
        var lastThemeSettings: ThemeSettings?
        var currentConfig: WidgetConfig?
        var isVisible = true
        private var isCrashed = false

        init(widget: PluginWebWidget, model: AppModel) {
            self.widget = widget
            self.model = model
        }

        func cleanup() {
            timer?.invalidate()
            timer = nil
        }

        func startDataPush(config: WidgetConfig, themeSettings: ThemeSettings) {
            timer?.invalidate()
            lastThemeSettings = themeSettings
            currentConfig = config
            // Initial push after short delay for page load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.isCrashed else { return }
                self.pushCurrentData()
                // Push initial widget size
                if let size = self.currentSize {
                    self.pushWidgetSizeUpdate(size: size)
                }
            }
            let t = Timer.scheduledTimer(withTimeInterval: widget.refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isCrashed, self.isVisible else { return }
                    self.pushCurrentData()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }

        /// Push data using the latest config and theme (not stale captured values).
        private func pushCurrentData() {
            guard let config = currentConfig, let ts = lastThemeSettings else { return }
            pushData(config: config, themeSettings: ts)
        }

        func pushData(config: WidgetConfig, themeSettings: ThemeSettings) {
            guard !isCrashed else { return }
            let payload = dataBridge.buildDataPayload(
                permissions: widget.permissions,
                widgetConfig: config,
                themeSettings: themeSettings,
                widgetId: widget.widgetId
            )
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let js = "window.edgecontrol._receive(\(jsonString));"
            webView?.evaluateJavaScript(js)
        }

        // MARK: - Lifecycle Events

        func pushResize(size: WidgetSize) {
            guard !isCrashed else { return }
            let pixelW = size.width * Int(GridConstants.cellWidth)
            let pixelH = size.height * Int(GridConstants.cellHeight)
            let js = "window.edgecontrol._onResize({width:\(size.width),height:\(size.height),pixelWidth:\(pixelW),pixelHeight:\(pixelH)});"
            webView?.evaluateJavaScript(js)
        }

        func pushThemeChange(ts: ThemeSettings) {
            guard !isCrashed else { return }
            let themeDict = dataBridge.liveThemeData(ts: ts, widgetId: widget.widgetId)
            guard let jsonData = try? JSONSerialization.data(withJSONObject: themeDict),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            let js = "window.edgecontrol._onThemeChange(\(jsonString));"
            webView?.evaluateJavaScript(js)
        }

        func pushVisibilityChange(visible: Bool) {
            guard !isCrashed else { return }
            isVisible = visible
            let js = "window.edgecontrol._onVisibilityChange(\(visible));"
            webView?.evaluateJavaScript(js)
        }

        private func pushWidgetSizeUpdate(size: WidgetSize) {
            guard !isCrashed else { return }
            let pixelW = size.width * Int(GridConstants.cellWidth)
            let pixelH = size.height * Int(GridConstants.cellHeight)
            let js = "window.edgecontrol._widgetSize = {width:\(size.width),height:\(size.height),pixelWidth:\(pixelW),pixelHeight:\(pixelH)};"
            webView?.evaluateJavaScript(js)
        }

        // MARK: - Navigation Delegate

        /// Restrict navigation to file:// URLs within the plugin bundle only.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Allow file:// (plugin bundle) and about:blank (error HTML)
            if url.isFileURL || url.absoluteString == "about:blank" {
                decisionHandler(.allow)
            } else {
                PluginFileLogger.log(widget.pluginId, "NAV BLOCKED: \(url.absoluteString)")
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showError(in: webView, message: error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showError(in: webView, message: error.localizedDescription)
        }

        /// Crash recovery — mark as crashed, show error, stop timer.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            isCrashed = true
            timer?.invalidate()
            timer = nil
            PluginFileLogger.log(widget.pluginId, "CRASH: WebContent process terminated")
            webView.loadHTMLString(PluginWebViewRepresentable.crashHTML(), baseURL: nil)
        }

        private func showError(in webView: WKWebView, message: String) {
            webView.loadHTMLString(PluginWebViewRepresentable.errorHTML(message), baseURL: nil)
        }

        // MARK: - Message Handler (JS → Native)

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }
            let payload = body["payload"] as? [String: Any] ?? [:]
            let callbackId = payload["_callbackId"] as? String

            switch action {
            case "log":
                if let text = payload["text"] as? String {
                    PluginFileLogger.log(widget.pluginId, "JS: \(text)")
                }

            case "notify":
                guard hasPermission(.notifications) else {
                    PluginFileLogger.log(widget.pluginId, "ACTION DENIED: notify (no permission)")
                    return
                }
                PluginFileLogger.log(widget.pluginId, "ACTION: notify title=\(payload["title"] ?? "")")
                handleNotify(payload: payload)

            case "openURL":
                guard hasPermission(.openURL) else {
                    PluginFileLogger.log(widget.pluginId, "ACTION DENIED: openURL (no permission)")
                    return
                }
                PluginFileLogger.log(widget.pluginId, "ACTION: openURL url=\(payload["url"] ?? "")")
                handleOpenURL(payload: payload)

            case "clipboard":
                guard hasPermission(.clipboard) else {
                    PluginFileLogger.log(widget.pluginId, "ACTION DENIED: clipboard (no permission)")
                    return
                }
                PluginFileLogger.log(widget.pluginId, "ACTION: clipboard")
                handleClipboard(payload: payload)

            case "storageGet":
                guard hasPermission(.storage), let key = payload["key"] as? String else {
                    PluginFileLogger.log(widget.pluginId, "ACTION DENIED: storageGet (no permission or missing key)")
                    resolveCallback(callbackId, result: nil, error: "storage permission denied or missing key")
                    return
                }
                let value = PluginStorageService.shared.get(pluginId: widget.pluginId, key: key)
                PluginFileLogger.log(widget.pluginId, "STORAGE GET: key=\(key) found=\(value != nil)")
                resolveCallback(callbackId, result: value, error: nil)

            case "storageSet":
                guard hasPermission(.storage),
                      let key = payload["key"] as? String,
                      let value = payload["value"] else {
                    PluginFileLogger.log(widget.pluginId, "ACTION DENIED: storageSet (no permission or missing key/value)")
                    resolveCallback(callbackId, result: nil, error: "storage permission denied or missing key/value")
                    return
                }
                PluginFileLogger.log(widget.pluginId, "STORAGE SET: key=\(key)")
                PluginStorageService.shared.set(pluginId: widget.pluginId, key: key, value: value)
                resolveCallback(callbackId, result: true, error: nil)

            case "storageRemove":
                guard hasPermission(.storage), let key = payload["key"] as? String else {
                    PluginFileLogger.log(widget.pluginId, "ACTION DENIED: storageRemove (no permission or missing key)")
                    resolveCallback(callbackId, result: nil, error: "storage permission denied or missing key")
                    return
                }
                PluginFileLogger.log(widget.pluginId, "STORAGE REMOVE: key=\(key)")
                PluginStorageService.shared.remove(pluginId: widget.pluginId, key: key)
                resolveCallback(callbackId, result: true, error: nil)

            default:
                break
            }
        }

        // MARK: - Action Handlers

        private func hasPermission(_ permission: PluginPermission) -> Bool {
            widget.permissions.contains(permission)
        }

        private func handleNotify(payload: [String: Any]) {
            guard let title = payload["title"] as? String else { return }
            let body = payload["body"] as? String ?? ""
            let pluginId = widget.pluginId

            Task {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()

                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    break
                case .notDetermined:
                    let granted = try? await center.requestAuthorization(options: [.alert, .sound])
                    guard granted == true else { return }
                default:
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "\(pluginId).\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                try? await center.add(request)
            }
        }

        private func handleOpenURL(payload: [String: Any]) {
            guard let urlString = payload["url"] as? String,
                  let url = URL(string: urlString),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return }
            NSWorkspace.shared.open(url)
        }

        private func handleClipboard(payload: [String: Any]) {
            guard let text = payload["text"] as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private func resolveCallback(_ callbackId: String?, result: Any?, error: String?) {
            guard let callbackId, let webView else { return }
            // Sanitize callbackId — should only be numeric from SDK, reject anything else
            guard callbackId.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isLetter) }) else { return }

            let resultJSON: String
            if let result {
                // Bool must be checked before NSNumber (Bool bridges to NSNumber in ObjC)
                if let boolVal = result as? Bool {
                    resultJSON = boolVal ? "true" : "false"
                } else if let num = result as? NSNumber {
                    resultJSON = "\(num)"
                } else if let str = result as? String {
                    // Escape for JS string literal
                    let escaped = str
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\n", with: "\\n")
                        .replacingOccurrences(of: "\r", with: "\\r")
                        .replacingOccurrences(of: "\t", with: "\\t")
                    resultJSON = "\"\(escaped)\""
                } else if JSONSerialization.isValidJSONObject(result),
                          let data = try? JSONSerialization.data(withJSONObject: result),
                          let str = String(data: data, encoding: .utf8) {
                    resultJSON = str
                } else {
                    resultJSON = "null"
                }
            } else {
                resultJSON = "null"
            }

            let errorParam = error.map { "'\($0.replacingOccurrences(of: "'", with: "\\'"))'" } ?? "null"
            let js = "window.edgecontrol._callback('\(callbackId)', \(resultJSON), \(errorParam));"
            webView.evaluateJavaScript(js)
        }
    }
}

// MARK: - Non-First-Responder WebView

/// WKWebView subclass that refuses to become first responder.
/// Prevents plugin WebViews from stealing focus from the dashboard,
/// while still allowing clicks/interactions within the plugin's own bounds.
private class NonFirstResponderWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}
