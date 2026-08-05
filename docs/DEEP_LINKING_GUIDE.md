# Metanoia Deep Linking - Developer Documentation

## Quick Start

**Link Format:** `/bible/<book>/<chapter>[/<verse>]`

**Example Links:**
- `metanoia://bible/John/3/16` (Custom scheme)
- `https://metanoia.bytecats.codes/bible/John/3/16` (HTTPS App Link)

## Supported Link Types

### 1. Custom Scheme (Immediate)
```
metanoia://bible/<book>/<chapter>[/<verse>]
```
- ✅ Works immediately, no verification needed
- ✅ Opens Metanoia directly
- ⚠️ May show app picker in some browsers

### 2. HTTPS App Link (Verified)
```
https://metanoia.bytecats.codes/bible/<book>/<chapter>[/<verse>]
```
- ✅ Auto-opens Metanoia (no picker)
- ✅ Web-friendly (works in browsers)
- ✅ Fallback to web if app not installed
- ⚠️ Requires App Link verification (configured)

## Integration Examples

### Android (Kotlin)
```kotlin
// Open specific verse
val intent = Intent(Intent.ACTION_VIEW, 
    Uri.parse("https://metanoia.bytecats.codes/bible/John/3/16"))
startActivity(intent)

// Open chapter (no specific verse)
val intent = Intent(Intent.ACTION_VIEW,
    Uri.parse("metanoia://bible/Genesis/1"))
startActivity(intent)
```

### Android (Java)
```java
Intent intent = new Intent(Intent.ACTION_VIEW, 
    Uri.parse("https://metanoia.bytecats.codes/bible/Romans/8/28"));
startActivity(intent);
```

### Web/HTML
```html
<!-- Direct verse link -->
<a href="https://metanoia.bytecats.codes/bible/John/3/16">
    Read John 3:16 in Metanoia
</a>

<!-- Chapter link -->
<a href="https://metanoia.bytecats.codes/bible/Genesis/1">
    Open Genesis Chapter 1
</a>

<!-- Custom scheme link -->
<a href="metanoia://bible/SongofSolomon/2/1">
    Song of Solomon 2:1
</a>
```

### JavaScript/Web Apps
```javascript
// Open in same window
window.open('https://metanoia.bytecats.codes/bible/John/3/16', '_self');

// Open in new tab
window.open('https://metanoia.bytecats.codes/bible/Genesis/1', '_blank');

// Dynamic link construction
function openVerse(book, chapter, verse) {
    const url = `https://metanoia.bytecats.codes/bible/${book}/${chapter}/${verse}`;
    window.open(url, '_self');
}
```

### React Native
```javascript
import { Linking } from 'react-native';

// Open verse
Linking.openURL('https://metanoia.bytecats.codes/bible/John/3/16');

// Open chapter
Linking.openURL('metanoia://bible/Genesis/1');
```

### Flutter
```dart
import 'package:url_launcher/url_launcher.dart';

// Open verse
await launch('https://metanoia.bytecats.codes/bible/John/3/16');

// Open chapter
await launch('metanoia://bible/Genesis/1');
```

## Book Name Format

### Canonical Names (Case-Insensitive)
Use exact book names from the Bible:
- `John`, `Genesis`, `Romans`, `Psalms`
- `1Samuel`, `2Corinthians`, `3John`
- `SongofSolomon`, `Revelation`

### Abbreviations
Common abbreviations are supported:
- `jn` → John
- `gen` → Genesis  
- `rom` → Romans
- `psa` → Psalms
- `1sam` → 1Samuel
- `2cor` → 2Corinthians

**Note:** Abbreviations currently cover 66-book Protestant canon only.

## Testing Links

### ADB (Android Debug Bridge)
```bash
# Test custom scheme
adb shell am start -W -a android.intent.action.VIEW \
  -d "metanoia://bible/John/3/16" com.bytecats.metanoia

# Test HTTPS link
adb shell am start -W -a android.intent.action.VIEW \
  -d "https://metanoia.bytecats.codes/bible/Romans/8/28" com.bytecats.metanoia
```

### Live Testing
Try these links now (requires Metanoia app installed):
- [John 3:16](https://metanoia.bytecats.codes/bible/John/3/16)
- [Genesis 1](https://metanoia.bytecats.codes/bible/Genesis/1)
- [Romans 8:28](https://metanoia.bytecats.codes/bible/Romans/8/28)
- [Psalm 23](https://metanoia.bytecats.codes/bible/Psalms/23)

## Link Validation

### What Gets Validated
- ✅ Book name exists (canonical or abbreviation)
- ✅ Chapter number is valid for the book
- ✅ Verse number is positive (if provided)
- ✅ Chapter/verse are numeric

### Error Handling
- ❌ Invalid book → Link ignored silently
- ❌ Out-of-range chapter → Link ignored silently  
- ❌ Non-numeric chapter/verse → Link ignored silently
- ❌ Missing chapter → Link ignored silently

## Technical Implementation

### Android Side
- **Parser:** `com.bytecats.metanoia.bible.DeepLink`
- **Tests:** 22 unit tests in `DeepLinkTest.kt`
- **Intent Filters:** Both custom scheme and App Links configured
- **Verification:** Android App Links verified via `assetlinks.json`

### Deep Link Flow
1. User taps link in another app/browser
2. Android resolves to Metanoia app (via intent filter)
3. `MainActivity` receives intent with URI
4. `DeepLink.parse()` resolves book/chapter/verse
5. App navigates directly to Bible screen with passage
6. `BibleManager.fetchChapter()` loads the content

### Single Task Mode
The app uses `android:launchMode="singleTask"` so:
- Link while app running → Uses existing instance
- Link while app closed → Starts new instance  
- No duplicate app instances created

## Common Use Cases

### Bible Study Apps
```kotlin
// Cross-reference feature in your Bible app
fun showCrossReference(reference: String) {
    val url = "https://metanoia.bytecats.codes/bible/${reference}"
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
    startActivity(intent)
}
```

### Sermon Notes Apps
```javascript
// Add scripture references to sermon notes
function addScriptureReference(book, chapter, verse) {
    const link = `https://metanoia.bytecats.codes/bible/${book}/${chapter}/${verse}`;
    return `[${book} ${chapter}:${verse}](${link})`;
}
```

### Prayer/Devotion Apps
```java
// Daily verse with deep link to Metanoia
Intent intent = new Intent(Intent.ACTION_VIEW,
    Uri.parse("https://metanoia.bytecats.codes/bible/" + 
              todayVerse.getBook() + "/" + 
              todayVerse.getChapter() + "/" +
              todayVerse.getVerse()));
startActivity(intent);
```

### Social Media/Sharing
```html
<!-- Share verse with deep link -->
<a href="https://metanoia.bytecats.codes/bible/John/3/16">
    📖 Read John 3:16 in Metanoia
</a>
```

## Current Limitations

### Known Limitations
- **Android Only:** iOS deep linking not yet supported
- **Translation Specific:** Links open user's currently selected translation
- **Protestant Canon:** Abbreviations only for 66 books
- **No Search/Query:** No search parameter support yet

### Planned Features
- iOS deep linking support
- Translation-specific links (e.g., `/bible/John/3/16?translation=ESV`)
- Range links (e.g., `/bible/John/3/16-21`)
- Strong's number integration
- Cross-reference linking

## Troubleshooting

### Link Not Opening Metanoia
1. **Check App Installation:** Ensure Metanoia is installed
2. **Verify Link Format:** Must be `/bible/<book>/<chapter>[/<verse>]`
3. **Book Name:** Use canonical names or known abbreviations
4. **ADB Testing:** Test with ADB to see Android's intent resolution

### App Picker Still Shows (HTTPS Links)
1. **Verification Pending:** First-time verification takes time
2. **Clear Data:** Clear app data and try again
3. **Fallback:** Use custom scheme (`metanoia://`) as backup

### Link Ignored Silently
1. **Invalid Book:** Check book name spelling/format
2. **Out of Range:** Verify chapter exists in the book
3. **Malformed:** Ensure proper `/bible/` prefix structure

## API Reference

### Link Format
```
{scheme}://{host}/bible/{book}/{chapter}[/{verse}]
```

### Components
- **scheme:** `metanoia` or `https`/`http`
- **host:** `bible` (custom) or any domain (HTTPS)
- **book:** Canonical name or abbreviation
- **chapter:** 1-N (must exist in book)
- **verse:** Optional, 1-N (must exist in chapter)

### Validation Rules
- Book name: Case-insensitive, must resolve
- Chapter: Must be integer, 1 ≤ chapter ≤ book.chapter_count
- Verse: Optional, must be integer if present, verse ≥ 1

## Support & Resources

### Documentation
- **Implementation Notes:** See `docs/ANDROID_DEEP_LINKS.md`
- **Source Code:** `mobile/app/src/main/java/com/bytecats/metanoia/bible/DeepLink.kt`
- **Tests:** `mobile/app/src/test/java/com/bytecats/metanoia/bible/DeepLinkTest.kt`

### Community
- **GitHub Issues:** Report bugs and feature requests
- **Developer Portal:** https://metanoia.bytecats.codes
- **Source Code:** https://github.com/4cecoder/metanoia

### Testing
- **Live Examples:** Available on developer portal
- **ADB Commands:** Provided for local testing
- **Unit Tests:** 22 tests covering all link formats

---

**Last Updated:** 2024-08-05  
**Version:** 1.0.0  
**Status:** ✅ Production Ready