import Foundation
import Network

/// Bonjour で見つかったサーバー情報。
struct DiscoveredServer: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    var display: String {
        "\(host):\(port)"
    }
}

/// `_remotehaptics._tcp` を NWBrowser で探索し、ホスト/ポートを解決する。
final class BonjourDiscovery {
    static let serviceType = "_remotehaptics._tcp"

    var onServers: (([DiscoveredServer]) -> Void)?

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]
    private var servers: [String: DiscoveredServer] = [:]

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.browser?.cancel()
                self?.browser = nil
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleResults(results)
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        for conn in resolvers.values {
            conn.cancel()
        }
        resolvers = [:]
        servers = [:]
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        let current = Set(servers.keys)
        var seen = Set<String>()
        for result in results {
            let name = result.endpoint.endpointName ?? result.endpoint.debugDescription
            seen.insert(name)
            if !servers.keys.contains(name) {
                resolve(name: name, endpoint: result.endpoint)
            }
        }
        let removed = current.subtracting(seen)
        for name in removed {
            servers.removeValue(forKey: name)
            resolvers.removeValue(forKey: name)?.cancel()
        }
        if !removed.isEmpty {
            notify()
        }
    }

    private func resolve(name: String, endpoint: NWEndpoint) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        resolvers[name] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let endpoint = conn.currentPath?.remoteEndpoint ?? conn.endpoint
                if let (host, port) = endpoint.hostPort {
                    let server = DiscoveredServer(
                        id: name,
                        name: name,
                        host: hostString(host),
                        port: port.rawValue
                    )
                    self?.servers[name] = server
                    self?.notify()
                }
                conn.cancel()
                self?.resolvers[name] = nil
            case .failed, .cancelled:
                conn.cancel()
                self?.resolvers[name] = nil
            default:
                break
            }
        }
        conn.start(queue: .main)
    }

    private func notify() {
        onServers?(servers.values.sorted { $0.name < $1.name })
    }
}

private extension NWEndpoint {
    var hostPort: (host: NWEndpoint.Host, port: NWEndpoint.Port)? {
        if case .hostPort(let host, let port) = self {
            return (host, port)
        }
        return nil
    }

    var endpointName: String? {
        switch self {
        case .service(let name, _, _, _):
            return name
        case .hostPort(let host, _):
            return hostString(host)
        case .url(let url):
            return url.host
        case .unix(let path):
            return path
        @unknown default:
            return nil
        }
    }
}

private func hostString(_ host: NWEndpoint.Host) -> String {
    switch host {
    case .ipv4(let address): return "\(address)"
    case .ipv6(let address): return "\(address)"
    case .name(let name, _): return name
    @unknown default: return "\(host)"
    }
}
