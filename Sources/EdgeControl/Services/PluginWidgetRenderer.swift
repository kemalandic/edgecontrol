import AppKit
import WebKit
import os.log

/// Renders plugin HTML in headless WKWebViews and takes periodic snapshots
/// for macOS desktop widgets. Snapshots are saved to the App Group container.
@MainActor
public final class PluginWidgetRenderer {
    private let pluginManager: PluginManager
    private let model: AppModel
    private var renderers: [String: PluginSnapshotRenderer] = [:] // pluginId → renderer
    private var timer: Timer?
    private let logger = Logger(subsystem: "ai.pakslab.edgecontrol", category: "PluginWidgetRenderer")

    /// macOS widget sizes in points
    private static let widgetSizes: [String: CGSize] = [
        "small": CGSize(width: 170, height: 170),
        "medium": CGSize(width: 364, height: 170),
        "large": CGSize(width: 364, height: 376),
    ]

    public init(pluginManager: PluginManager, model: AppModel) {
        self.pluginManager = pluginManager
        self.model = model
    }

    public func start() {
        stop()
        setupRenderers()
        // Initial snapshot after delay — services need time to collect data, WebViews need to load
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            self.takeAllSnapshots()
        }
        // Periodic snapshots every 5 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.takeAllSnapshots()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        for renderer in renderers.values {
            renderer.tearDown()
        }
        renderers.removeAll()
    }

    /// Refresh renderers when plugins change (install/uninstall/toggle)
    public func refresh() {
        stop()
        start()
    }

    private func setupRenderers() {
        let desktopPlugins = pluginManager.plugins.filter { plugin in
            plugin.isEnabled && plugin.manifest.desktopWidget?.enabled == true
        }

        guard !desktopPlugins.isEmpty else {
            // No desktop widget plugins — clear manifest
            PluginWidgetManifest(plugins: []).write()
            return
        }

        for plugin in desktopPlugins {
            guard let config = plugin.manifest.desktopWidget else { continue }
            guard let firstWidget = plugin.manifest.widgets.first else { continue }

            let htmlURL = plugin.bundlePath.appendingPathComponent(firstWidget.htmlFile)
            guard FileManager.default.fileExists(atPath: htmlURL.path) else {
                logger.warning("Plugin \(plugin.id): HTML file not found at \(firstWidget.htmlFile)")
                continue
            }

            let sizes = Array(config.supportedFamilies)
            for size in sizes {
                guard let pixelSize = Self.widgetSizes[size] else { continue }
                let renderer = PluginSnapshotRenderer(
                    pluginId: plugin.id,
                    htmlURL: htmlURL,
                    bundlePath: plugin.bundlePath,
                    size: pixelSize,
                    sizeLabel: size,
                    model: model,
                    permissions: plugin.manifest.permissions
                )
                renderer.load()
                renderers["\(plugin.id)_\(size)"] = renderer
            }
        }

        // Write manifest for widget extension
        let infos = desktopPlugins.map { plugin in
            PluginWidgetInfo(
                id: plugin.id,
                name: plugin.manifest.name,
                icon: plugin.manifest.icon,
                sizes: Array(plugin.manifest.desktopWidget?.supportedFamilies ?? ["small", "medium"])
            )
        }
        PluginWidgetManifest(plugins: infos).write()
        logger.info("Plugin widget manifest written with \(infos.count) plugin(s)")
    }

    private func takeAllSnapshots() {
        let dataBridge = PluginDataBridge(model: model)

        for (key, renderer) in renderers {
            // Push latest data before taking snapshot
            let payload = dataBridge.buildDataPayload(
                permissions: renderer.permissions,
                widgetConfig: WidgetConfig(),
                themeSettings: ThemeSettings(),
                widgetId: renderer.pluginId
            )
            renderer.pushData(payload)
        }

        // Wait for WebViews to render updated data, then snapshot
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for (key, renderer) in self.renderers {
                renderer.takeSnapshot { [weak self] image in
                    guard let image else {
                        self?.logger.warning("Snapshot failed for \(key)")
                        return
                    }
                    self?.saveSnapshot(image: image, pluginId: renderer.pluginId, size: renderer.sizeLabel)
                }
            }
        }
    }

    private func saveSnapshot(image: NSImage, pluginId: String, size: String) {
        guard let url = PluginWidgetManifest.snapshotURL(pluginId: pluginId, size: size) else { return }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            logger.info("Snapshot saved: \(pluginId)_\(size).png")
        } catch {
            logger.error("Failed to save snapshot \(pluginId)_\(size): \(error.localizedDescription)")
        }
    }
}

// MARK: - Individual Plugin Snapshot Renderer

@MainActor
private final class PluginSnapshotRenderer {
    let pluginId: String
    let sizeLabel: String
    let permissions: [PluginPermission]
    private let htmlURL: URL
    private let bundlePath: URL
    private let size: CGSize
    private let model: AppModel
    private var webView: WKWebView?

    init(pluginId: String, htmlURL: URL, bundlePath: URL, size: CGSize, sizeLabel: String, model: AppModel, permissions: [PluginPermission]) {
        self.pluginId = pluginId
        self.htmlURL = htmlURL
        self.bundlePath = bundlePath
        self.size = size
        self.sizeLabel = sizeLabel
        self.model = model
        self.permissions = permissions
    }

    func load() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Inject minimal EdgeControl JS SDK for data reception
        let sdkScript = WKUserScript(
            source: """
            window.edgecontrol = {
                _listeners: {},
                _data: {},
                get: function(key) { return key ? this._data[key] : this._data; },
                on: function(event, cb) {
                    if (!this._listeners[event]) this._listeners[event] = [];
                    this._listeners[event].push(cb);
                },
                _emit: function(event, data) {
                    var ls = this._listeners[event] || [];
                    for (var i = 0; i < ls.length; i++) { try { ls[i](data); } catch(e) {} }
                },
                _receive: function(data) {
                    this._data = data;
                    this._emit('update', data);
                },
                _onResize: function(size) { this._emit('resize', size); },
                _onThemeChange: function(theme) { this._data.theme = theme; this._emit('themeChange', theme); },
                _onVisibilityChange: function(v) { this._emit('visibilityChange', v); },
                send: function() {},
                notify: function() {},
                openURL: function() {},
                copyToClipboard: function() {},
                storage: { get: function() { return Promise.resolve(null); }, set: function() { return Promise.resolve(); }, remove: function() { return Promise.resolve(); } }
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(sdkScript)

        // Inject minimal theme CSS
        let css = """
        :root {
            --ec-bg1: #141414; --ec-bg2: #1c1c1c;
            --ec-text1: #ffffff; --ec-text2: #b3b3b3; --ec-text3: #737373;
            --ec-border: #2e2e2e; --ec-accent: #00ccdd;
            color-scheme: dark;
        }
        body { margin: 0; padding: 8px; background: var(--ec-bg1); color: var(--ec-text1);
               font-family: -apple-system, BlinkMacSystemFont, sans-serif; overflow: hidden; }
        """
        let cssScript = WKUserScript(
            source: """
            const s = document.createElement('style');
            s.textContent = `\(css)`;
            document.documentElement.appendChild(s);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(cssScript)

        // Inject widget mode flag
        let modeScript = WKUserScript(
            source: "window.__EC_WIDGET_MODE__ = '\(sizeLabel)';",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(modeScript)

        let wv = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = navigationDelegate
        webView = wv

        // Load the plugin HTML
        wv.loadFileURL(htmlURL, allowingReadAccessTo: bundlePath)
    }

    /// Called when WebView finishes loading — emit ready event and push initial data
    func onPageLoaded() {
        guard let wv = webView else { return }

        // Set widget size info
        let sizeJS = """
        if(window.edgecontrol) {
            edgecontrol._widgetSize = {width: \(Int(size.width)), height: \(Int(size.height))};
            edgecontrol.getWidgetSize = function() { return this._widgetSize; };
            edgecontrol.config = {};
            edgecontrol._emit('ready', {});
        }
        """
        wv.evaluateJavaScript(sizeJS, completionHandler: nil)
    }

    private lazy var navigationDelegate = RendererNavigationDelegate(renderer: self)

    func pushData(_ payload: [String: Any]) {
        guard let wv = webView else { return }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        // Push data via the same JS bridge the dashboard plugin uses
        let js = "if(window.edgecontrol && window.edgecontrol._receive) { window.edgecontrol._receive(\(jsonString)); }"
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    func takeSnapshot(completion: @escaping (NSImage?) -> Void) {
        guard let wv = webView else {
            completion(nil)
            return
        }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        wv.takeSnapshot(with: config) { image, error in
            completion(image)
        }
    }

    func tearDown() {
        webView?.stopLoading()
        webView = nil
    }
}

// MARK: - Navigation Delegate for Headless Renderer

@MainActor
private final class RendererNavigationDelegate: NSObject, WKNavigationDelegate {
    weak var renderer: PluginSnapshotRenderer?

    init(renderer: PluginSnapshotRenderer) {
        self.renderer = renderer
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.renderer?.onPageLoaded()
        }
    }
}
