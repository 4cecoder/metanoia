import Foundation

struct BibleHubScraper {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "Metanoia/1.0 (iOS Bible App)",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        ]
        return URLSession(configuration: config)
    }()
    
    // MARK: - Text Scraper
    
    static func fetchTextVerses(book: String, chapter: Int) async throws -> [Verse] {
        let slug = bookToSlug(book)
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
        
        return try parseTextVerses(from: html, book: book, chapter: chapter)
    }
    
    static func parseTextVerses(from html: String, book: String, chapter: Int) throws -> [Verse] {
        var verses: [Verse] = []
        
        // BibleHub text pages have tables with class "text"
        guard let tableRange = html.range(of: #"<table[^>]*class="text"[^>]*>"# , options: .regularExpression) else {
            throw ScraperError.parsingError("Could not find text table")
        }
        
        let tableHTML = String(html[tableRange.lowerBound...])
        
        // Extract rows - each row is a verse
        let rowPattern = #"<tr[^>]*>.*?</tr>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: .dotMatchesLineSeparators) else {
            throw ScraperError.parsingError("Invalid regex")
        }
        
        let nsTable = NSRange(tableHTML.startIndex..., in: tableHTML)
        let rows = rowRegex.matches(in: tableHTML, range: nsTable)
        
        var currentVerse = 0
        
        for row in rows {
            guard let rowRange = Range(row.range, in: tableHTML) else { continue }
            let rowHTML = String(tableHTML[rowRange])
            
            // Extract verse number
            if let numMatch = rowHTML.range(of: #"data-verse="(\d+)"#, options: .regularExpression) {
                let numStr = String(rowHTML[numMatch])
                    .replacingOccurrences(of: #"data-verse=""#, with: "")
                    .replacingOccurrences(of: "\"", with: "")
                if let num = Int(numStr) {
                    currentVerse = num
                }
            } else if let numMatch = rowHTML.range(of: #"class="vr">(\d+)"#, options: .regularExpression) {
                let numStr = String(rowHTML[numMatch])
                    .replacingOccurrences(of: #"class="vr">"#, with: "")
                if let num = Int(numStr) {
                    currentVerse = num
                }
            }
            
            guard currentVerse > 0 else { continue }
            
            // Extract text content from cells
            var verseText = ""
            let cellPattern = #"<td[^>]*>(.*?)</td>"#
            if let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: .dotMatchesLineSeparators) {
                let nsRow = NSRange(rowHTML.startIndex..., in: rowHTML)
                let cells = cellRegex.matches(in: rowHTML, range: nsRow)
                
                for cell in cells {
                    guard let cellRange = Range(cell.range(at: 1), in: rowHTML) else { continue }
                    let cellContent = String(rowHTML[cellRange])
                    let cleaned = BibleGatewayScraper.cleanHTML(cellContent)
                    if !cleaned.isEmpty && !verseText.contains(cleaned) {
                        if !verseText.isEmpty {
                            verseText += " "
                        }
                        verseText += cleaned
                    }
                }
            }
            
            if !verseText.isEmpty {
                let verse = Verse(
                    book: book,
                    chapter: chapter,
                    verse: currentVerse,
                    text: verseText,
                    version: "KJV"
                )
                verses.append(verse)
            }
        }
        
        return verses
    }
    
    // MARK: - Interlinear Scraper
    
    static func fetchInterlinear(book: String, chapter: Int) async throws -> [InterlinearWord] {
        let slug = bookToSlug(book)
        let urlString = "https://biblehub.com/interlinear/\(slug)/\(chapter).htm"
        
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
        
        return try parseInterlinear(from: html, book: book, chapter: chapter)
    }
    
    static func parseInterlinear(from html: String, book: String, chapter: Int) throws -> [InterlinearWord] {
        var words: [InterlinearWord] = []
        
        // BibleHub interlinear pages have tables with class "interlinear"
        guard html.contains("interlinear") else {
            throw ScraperError.parsingError("Not an interlinear page")
        }
        
        // Extract Greek/Hebrew words with Strong's numbers
        let wordPattern = #"<a[^>]*href="[^"]*?/(greek|hebrew)/(\d+)[^"]*"[^>]*>([^<]+)</a>"#
        guard let wordRegex = try? NSRegularExpression(pattern: wordPattern, options: .caseInsensitive) else {
            throw ScraperError.parsingError("Invalid word regex")
        }
        
        let nsHTML = NSRange(html.startIndex..., in: html)
        let matches = wordRegex.matches(in: html, range: nsHTML)
        
        var currentVerse = 0
        
        for match in matches {
            guard let typeRange = Range(match.range(at: 1), in: html),
                  let strongsRange = Range(match.range(at: 2), in: html),
                  let wordRange = Range(match.range(at: 3), in: html) else { continue }
            
            let langStr = String(html[typeRange])
            let strongsNum = String(html[strongsRange])
            let originalWord = String(html[wordRange])
            
            let language: OriginalLanguage = langStr == "greek" ? .greek : .hebrew
            let strongsNumber = langStr == "greek" ? "G\(strongsNum)" : "H\(strongsNum)"
            
            // Try to find the English translation near this word
            let translation = extractTranslationNearWord(originalWord, in: html, at: match.range)
            
            let word = InterlinearWord(
                book: book,
                chapter: chapter,
                verse: currentVerse,
                wordIndex: words.count,
                originalWord: originalWord,
                transliteration: originalWord,
                englishTranslation: translation,
                strongsNumber: strongsNumber,
                language: language
            )
            words.append(word)
        }
        
        return words
    }
    
    private static func extractTranslationNearWord(_ word: String, in html: String, at range: NSRange) -> String {
        // Look for translation in nearby content
        let searchLength = 500
        let start = max(0, range.location - searchLength)
        let end = min(html.count, range.location + range.length + searchLength)
        
        guard let searchRange = Range(NSRange(location: start, length: end - start), in: html) else {
            return ""
        }
        
        let searchArea = String(html[searchRange])
        
        // Look for common translation patterns
        let patterns = [
            #"class="tr">([^<]+)<"#,
            #"title="([^"]+)""#,
            #"alt="([^"]+)""#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: searchArea, range: NSRange(searchArea.startIndex..., in: searchArea)),
               let matchRange = Range(match.range(at: 1), in: searchArea) {
                let translation = String(searchArea[matchRange])
                if !translation.isEmpty && translation != word {
                    return translation
                }
            }
        }
        
        return ""
    }
    
    // MARK: - Lexicon Scraper
    
    static func fetchLexicon(strongs: String) async throws -> LexiconEntry {
        let cleanStrongs = strongs.replacingOccurrences(of: #"^(G|H)"#, with: "", options: .regularExpression)
        let prefix = strongs.hasPrefix("G") ? "greek" : "hebrew"
        let urlString = "https://biblehub.com/\(prefix)/\(cleanStrongs).htm"
        
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
        
        return try parseLexicon(from: html, strongs: strongs)
    }
    
    static func parseLexicon(from html: String, strongs: String) throws -> LexiconEntry {
        let language: OriginalLanguage = strongs.hasPrefix("G") ? .greek : .hebrew
        
        // Extract original word
        let originalWord = extractFromHTML(html, pattern: #"class="eng"[^>]*>([^<]+)<"#) ?? ""
        
        // Extract transliteration
        let transliteration = extractFromHTML(html, pattern: #"class="translit"[^>]*>([^<]+)<"#) ?? ""
        
        // Extract pronunciation
        let pronunciation = extractFromHTML(html, pattern: #"class="pron"[^>]*>([^<]+)<"#) ?? ""
        
        // Extract Strong's number
        let strongsNum = extractFromHTML(html, pattern: #"class="strongs"[^>]*>([^<]+)<"#) ?? strongs
        
        // Extract definition/parsing
        let definition = extractFromHTML(html, pattern: #"class="definition"[^>]*>([^<]+)<"#) ?? ""
        
        // Extract all meanings
        var meanings: [String] = []
        let meaningPattern = #"<li[^>]*>([^<]+)</li>"#
        if let regex = try? NSRegularExpression(pattern: meaningPattern) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let meaning = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !meaning.isEmpty && meaning.count > 2 {
                        meanings.append(meaning)
                    }
                }
            }
        }
        
        // Extract parsing info
        let parsing = extractParsing(from: html)
        
        return LexiconEntry(
            strongsNumber: strongsNum,
            originalWord: originalWord,
            transliteration: transliteration,
            pronunciation: pronunciation,
            language: language,
            definition: definition,
            meanings: Array(meanings.prefix(10)),
            partOfSpeech: parsing.partOfSpeech,
            tense: parsing.tense,
            voice: parsing.voice,
            mood: parsing.mood,
            case_: parsing.case_,
            number: parsing.number,
            gender: parsing.gender,
            root: parsing.root
        )
    }
    
    private static func extractFromHTML(_ html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return BibleGatewayScraper.cleanHTML(String(html[range]))
    }
    
    private static func extractParsing(from html: String) -> ParsingInfo {
        var info = ParsingInfo()
        
        let parsingPattern = #"<span[^>]*class="[^"]*parsing[^"]*"[^>]*>([^<]+)</span>"#
        if let regex = try? NSRegularExpression(pattern: parsingPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                guard let range = Range(match.range(at: 1), in: html) else { continue }
                let value = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                if value.contains("noun") || value.contains("verb") || value.contains("adj") {
                    info.partOfSpeech = value
                } else if value.contains("present") || value.contains("aorist") || value.contains("imperfect") {
                    info.tense = value
                } else if value.contains("active") || value.contains("passive") || value.contains("middle") {
                    info.voice = value
                } else if value.contains("indicative") || value.contains("subjunctive") || value.contains("imperative") {
                    info.mood = value
                } else if value.contains("nominative") || value.contains("genitive") || value.contains("accusative") {
                    info.case_ = value
                } else if value.contains("singular") || value.contains("plural") {
                    info.number = value
                } else if value.contains("masculine") || value.contains("feminine") || value.contains("neuter") {
                    info.gender = value
                }
            }
        }
        
        // Extract root if available
        let rootPattern = #"class="root"[^>]*>([^<]+)<"#
        if let regex = try? NSRegularExpression(pattern: rootPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            info.root = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return info
    }
    
    // MARK: - Helpers
    
    private static func bookToSlug(_ book: String) -> String {
        let slugMap: [String: String] = [
            "genesis": "genesis", "exodus": "exodus", "leviticus": "leviticus",
            "numbers": "numbers", "deuteronomy": "deuteronomy", "joshua": "joshua",
            "judges": "judges", "ruth": "ruth", "1 samuel": "1samuel",
            "2 samuel": "2samuel", "1 kings": "1kings", "2 kings": "2kings",
            "1 chronicles": "1chronicles", "2 chronicles": "2chronicles",
            "ezra": "ezra", "nehemiah": "nehemiah", "esther": "esther",
            "job": "job", "psalms": "psalms", "psalm": "psalms",
            "proverbs": "proverbs", "ecclesiastes": "ecclesiastes",
            "song of solomon": "songs", "isaiah": "isaiah", "jeremiah": "jeremiah",
            "lamentations": "lamentations", "ezekiel": "ezekiel", "daniel": "daniel",
            "hosea": "hosea", "joel": "joel", "amos": "amos",
            "obadiah": "obadiah", "jonah": "jonah", "micah": "micah",
            "nahum": "nahum", "habakkuk": "habakkuk", "zephaniah": "zephaniah",
            "haggai": "haggai", "zechariah": "zechariah", "malachi": "malachi",
            "matthew": "matthew", "mark": "mark", "luke": "luke",
            "john": "john", "acts": "acts", "romans": "romans",
            "1 corinthians": "1corinthians", "2 corinthians": "2corinthians",
            "galatians": "galatians", "ephesians": "ephesians",
            "philippians": "philippians", "colossians": "colossians",
            "1 thessalonians": "1thessalonians", "2 thessalonians": "2thessalonians",
            "1 timothy": "1timothy", "2 timothy": "2timothy",
            "titus": "titus", "philemon": "philemon", "hebrews": "hebrews",
            "james": "james", "1 peter": "1peter", "2 peter": "2peter",
            "1 john": "1john", "2 john": "2john", "3 john": "3john",
            "jude": "jude", "revelation": "revelation"
        ]
        
        let lower = book.lowercased()
        return slugMap[lower] ?? lower.replacingOccurrences(of: " ", with: "")
    }
}

private struct ParsingInfo {
    var partOfSpeech: String = ""
    var tense: String = ""
    var voice: String = ""
    var mood: String = ""
    var case_: String = ""
    var number: String = ""
    var gender: String = ""
    var root: String = ""
}
