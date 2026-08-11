import Foundation

actor ScraperService {
    static let shared = ScraperService()
    
    private var lastRequestTime: [String: Date] = [:]
    private let rateLimitInterval: TimeInterval = 1.0
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = [
            "User-Agent": "Metanoia/1.0 (iOS Bible App)",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ]
        self.session = URLSession(configuration: config)
    }
    
    func fetchChapter(book: String, chapter: Int, version: String = "NKJV") async throws -> [Verse] {
        let scrapers: [(name: String, fetcher: () async throws -> [Verse])] = [
            ("BibleGateway", { [weak self] in
                guard let self else { throw ScraperError.serviceUnavailable }
                return try await self.fetchFromBibleGateway(book: book, chapter: chapter, version: version)
            }),
            ("BibleHub", { [weak self] in
                guard let self else { throw ScraperError.serviceUnavailable }
                return try await self.fetchFromBibleHub(book: book, chapter: chapter, version: version)
            })
        ]
        
        var lastError: Error?
        
        for scraper in scrapers {
            do {
                let verses = try await rateLimitedRequest(to: scraper.name) {
                    try await scraper.fetcher()
                }
                if !verses.isEmpty {
                    return verses
                }
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError ?? ScraperError.noResults
    }
    
    func fetchInterlinear(book: String, chapter: Int) async throws -> [InterlinearWord] {
        try await rateLimitedRequest(to: "BibleHubInterlinear") {
            try await BibleHubScraper.fetchInterlinear(book: book, chapter: chapter)
        }
    }
    
    func fetchLexicon(strongs: String) async throws -> LexiconEntry {
        try await rateLimitedRequest(to: "BibleHubLexicon") {
            try await BibleHubScraper.fetchLexicon(strongs: strongs)
        }
    }
    
    private func fetchFromBibleGateway(book: String, chapter: Int, version: String) async throws -> [Verse] {
        let encoded = "\(book)+\(chapter)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "\(book)+\(chapter)"
        let urlString = "https://www.biblegateway.com/passage/?search=\(encoded)&version=\(version)&interface=print"
        
        guard let url = URL(string: urlString) else {
            throw ScraperError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ScraperError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ScraperError.encodingError
        }
        
        return try BibleGatewayScraper.parseVerses(from: html, book: book, chapter: chapter)
    }
    
    private func fetchFromBibleHub(book: String, chapter: Int, version: String) async throws -> [Verse] {
        let slug = book.lowercased().replacingOccurrences(of: " ", with: "")
        let urlString = "https://biblehub.com/text/\(slug)/\(chapter).htm"
        
        guard let url = URL(string: urlString) else {
            throw ScraperError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ScraperError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ScraperError.encodingError
        }
        
        return try BibleHubScraper.parseTextVerses(from: html, book: book, chapter: chapter)
    }
    
    private func rateLimitedRequest<T>(
        to domain: String,
        operation: () async throws -> T
    ) async throws -> T {
        if let lastTime = lastRequestTime[domain] {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < rateLimitInterval {
                let delay = rateLimitInterval - elapsed
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        var lastError: Error?
        let maxRetries = 3
        
        for attempt in 0..<maxRetries {
            do {
                let result = try await operation()
                lastRequestTime[domain] = Date()
                return result
            } catch {
                lastError = error
                
                if attempt < maxRetries - 1 {
                    let backoff = pow(2.0, Double(attempt)) * 1.0
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? ScraperError.unknown
    }
}

enum ScraperError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case encodingError
    case parsingError(String)
    case noResults
    case serviceUnavailable
    case rateLimited
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code): return "HTTP error \(code)"
        case .encodingError: return "Failed to decode response"
        case .parsingError(let detail): return "Parse error: \(detail)"
        case .noResults: return "No results found"
        case .serviceUnavailable: return "Service unavailable"
        case .rateLimited: return "Rate limited"
        case .unknown: return "Unknown error"
        }
    }
}
