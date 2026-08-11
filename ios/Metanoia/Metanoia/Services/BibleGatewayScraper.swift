import Foundation

struct BibleGatewayScraper {
    static func parseVerses(from html: String, book: String, chapter: Int) throws -> [Verse] {
        var verses: [Verse] = []
        
        // Extract the passage content from BibleGateway's print view
        guard let passageRange = html.range(of: "<div class=\"passage-text\">") else {
            throw ScraperError.parsingError("Could not find passage-text div")
        }
        
        let passageHTML = String(html[passageRange.upperBound...])
        
        // Extract version for reference
        let version = extractVersion(from: html) ?? "NKJV"
        
        // Parse verse numbers and text
        var currentVerseNumber = 0
        var currentVerseText = ""
        
        let lines = passageHTML.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            guard !trimmed.isEmpty else { continue }
            
            // Check for verse number markers
            if let verseNum = extractVerseNumber(from: trimmed) {
                // Save previous verse if exists
                if currentVerseNumber > 0 && !currentVerseText.isEmpty {
                    let cleanText = cleanHTML(currentVerseText)
                    if !cleanText.isEmpty {
                        let verse = Verse(
                            book: book,
                            chapter: chapter,
                            verse: currentVerseNumber,
                            text: cleanText,
                            version: version
                        )
                        verses.append(verse)
                    }
                }
                currentVerseNumber = verseNum
                currentVerseText = ""
            } else if currentVerseNumber > 0 {
                // Accumulate verse text
                let cleaned = cleanHTML(trimmed)
                if !cleaned.isEmpty {
                    if !currentVerseText.isEmpty {
                        currentVerseText += " "
                    }
                    currentVerseText += cleaned
                }
            }
            
            // Stop if we hit the end of passage content
            if trimmed.contains("</div>") && trimmed.contains("passage-display") {
                break
            }
        }
        
        // Don't forget the last verse
        if currentVerseNumber > 0 && !currentVerseText.isEmpty {
            let cleanText = cleanHTML(currentVerseText)
            if !cleanText.isEmpty {
                let verse = Verse(
                    book: book,
                    chapter: chapter,
                    verse: currentVerseNumber,
                    text: cleanText,
                    version: version
                )
                verses.append(verse)
            }
        }
        
        return verses
    }
    
    private static func extractVerseNumber(from text: String) -> Int? {
        // Look for <sup class="versevalue" data-type="vnumber">N</sup> or similar patterns
        let patterns = [
            #"data-type="vnumber">(\d+)<"#,
            #"class="versevalue">(\d+)<"#,
            #"sup>(\d+)</sup>"#,
            #"class="versenum">(\d+)"#,
            #"data-verse="(\d+)"#
        ]
        
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression),
               let match = text[range].range(of: #"(\d+)"#, options: .regularExpression) {
                let numStr = String(text[match])
                if let num = Int(numStr) {
                    return num
                }
            }
        }
        
        // Fallback: look for standalone numbers at start
        if let firstChar = text.first, firstChar.isNumber {
            var numStr = ""
            for char in text {
                if char.isNumber {
                    numStr.append(char)
                } else {
                    break
                }
            }
            if !numStr.isEmpty, let num = Int(numStr), num > 0 && num < 200 {
                return num
            }
        }
        
        return nil
    }
    
    private static func extractVersion(from html: String) -> String? {
        let pattern = #"class="version"[^>]*>([^<]+)<"#
        if let range = html.range(of: pattern, options: .regularExpression) {
            let match = String(html[range])
            if let innerRange = match.range(of: #">([^<]+)<"#, options: .regularExpression) {
                let version = String(match[innerRange])
                    .replacingOccurrences(of: ">", with: "")
                    .replacingOccurrences(of: "<", with: "")
                    .trimmingCharacters(in: .whitespaces)
                return version
            }
        }
        return nil
    }
    
    static func cleanHTML(_ text: String) -> String {
        var cleaned = text
        
        // Remove common HTML tags
        let removePatterns = [
            #"<sup[^>]*>.*?</sup>"#,
            #"<span[^>]*>.*?</span>"#,
            #"<div[^>]*>"#,
            #"</div>"#,
            #"<p[^>]*>"#,
            #"</p>"#,
            #"<br\s*/?>"#,
            #"<i>"#,
            #"</i>"#,
            #"<b>"#,
            #"</b>"#,
            #"<em>"#,
            #"</em>"#,
            #"<strong>"#,
            #"</strong>"#,
            #"<a[^>]*>"#,
            #"</a>"#,
            #"<font[^>]*>"#,
            #"</font>"#,
            #"<h\d[^>]*>"#,
            #"</h\d>"#,
            #"<hr[^>]*>"#,
            #"<img[^>]*>"#,
            #"<table[^>]*>.*?</table>"#,
        ]
        
        for pattern in removePatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        
        // Decode HTML entities
        cleaned = decodeHTMLEntities(cleaned)
        
        // Normalize whitespace
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&#8212;", "\u{2014}"),
            ("&#8211;", "\u{2013}"),
            ("&mdash;", "\u{2014}"),
            ("&ndash;", "\u{2013}"),
            ("&#8216;", "\u{2018}"),
            ("&#8217;", "\u{2019}"),
            ("&#8220;", "\u{201C}"),
            ("&#8221;", "\u{201D}"),
            ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"),
            ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}"),
            ("&nbsp;", " "),
            ("&#160;", " "),
            ("&#8230;", "\u{2026}"),
            ("&hellip;", "\u{2026}"),
        ]
        
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Handle numeric entities
        let numericPattern = #"&#(\d+);"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, range: nsRange).reversed()
            
            for match in matches {
                guard let range = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range, in: result) else { continue }
                
                let numStr = String(result[range])
                if let codePoint = UInt32(numStr),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        
        return result
    }
}
