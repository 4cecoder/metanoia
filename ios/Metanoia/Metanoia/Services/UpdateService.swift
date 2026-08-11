import Foundation

@Observable
class UpdateService {
    static let shared = UpdateService()
    
    var isChecking = false
    var latestRelease: GitHubRelease?
    var updateAvailable = false
    var lastChecked: Date?
    var errorMessage: String?
    
    private let repoOwner = "4cecoder"
    private let repoName = "metanoia"
    private let session: URLSession
    private let storageKey = "update_service"
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        loadLastChecked()
    }
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    func checkForUpdates(force: Bool = false) async {
        guard !isChecking else { return }
        
        // Don't check more than once per hour unless forced
        if !force, let lastChecked, 
           Date().timeIntervalSince(lastChecked) < 3600 {
            return
        }
        
        isChecking = true
        errorMessage = nil
        
        defer { isChecking = false }
        
        do {
            let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
            guard let url = URL(string: urlString) else {
                throw UpdateError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("Metanoia-iOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    throw UpdateError.noReleases
                }
                throw UpdateError.httpError(httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let release = try decoder.decode(GitHubRelease.self, from: data)
            
            latestRelease = release
            updateAvailable = isNewerVersion(release.tagName)
            lastChecked = Date()
            saveLastChecked()
            
        } catch let error as UpdateError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to check for updates: \(error.localizedDescription)"
        }
    }
    
    func openReleasePage() {
        let urlString = "https://github.com/\(repoOwner)/\(repoName)/releases/latest"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
    
    func openAppStore() {
        let appStoreURL = "https://apps.apple.com/app/id\(appId)"
        if let url = URL(string: appStoreURL) {
            UIApplication.shared.open(url)
        }
    }
    
    private var appId: String {
        Bundle.main.infoDictionary?["APP_STORE_ID"] as? String ?? "0"
    }
    
    private func isNewerVersion(_ releaseTag: String) -> Bool {
        let remoteVersion = releaseTag.replacingOccurrences(of: "v", with: "")
        let localVersion = currentVersion
        
        let remoteParts = remoteVersion.split(separator: ".").compactMap { Int($0) }
        let localParts = localVersion.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(remoteParts.count, localParts.count)
        
        for i in 0..<maxCount {
            let remote = i < remoteParts.count ? remoteParts[i] : 0
            let local = i < localParts.count ? localParts[i] : 0
            
            if remote > local {
                return true
            } else if remote < local {
                return false
            }
        }
        
        return false
    }
    
    func shouldShowUpdateBanner() -> Bool {
        guard updateAvailable, let release else { return false }
        
        let dismissedVersion = UserDefaults.standard.string(forKey: "\(storageKey)_dismissed")
        return dismissedVersion != release.tagName
    }
    
    func dismissUpdateBanner() {
        if let release {
            UserDefaults.standard.set(release.tagName, forKey: "\(storageKey)_dismissed")
        }
    }
    
    // MARK: - Persistence
    
    private func saveLastChecked() {
        if let date = lastChecked {
            UserDefaults.standard.set(date, forKey: "\(storageKey)_lastChecked")
        }
    }
    
    private func loadLastChecked() {
        lastChecked = UserDefaults.standard.object(forKey: "\(storageKey)_lastChecked") as? Date
    }
}

// MARK: - Models

struct GitHubRelease: Codable {
    let id: Int
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: Date?
    let htmlUrl: String
    let zipballUrl: String?
    let tarballUrl: String?
    let prerelease: Bool
    let draft: Bool
    let assets: [ReleaseAsset]
    
    var version: String {
        tagName.replacingOccurrences(of: "v", with: "")
    }
    
    var shortNotes: String? {
        guard let body else { return nil }
        // Get first paragraph of release notes
        let lines = body.components(separatedBy: "\n\n")
        return lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var releaseDate: Date? {
        publishedAt
    }
    
    var formattedDate: String {
        guard let publishedAt else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: publishedAt)
    }
}

struct ReleaseAsset: Codable {
    let id: Int
    let name: String
    let contentType: String
    let size: Int
    let downloadCount: Int
    let browserDownloadUrl: String
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noReleases
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .httpError(let code): return "HTTP error \(code)"
        case .noReleases: return "No releases found"
        case .decodingFailed: return "Failed to decode release data"
        }
    }
}
