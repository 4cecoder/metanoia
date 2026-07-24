# Android deep links — linking to a specific Bible verse

Metanoia's Android app can be opened directly to a specific book/chapter/verse
from another app, a website, or a plain text message. This covers both
supported link forms, how to construct one, current limitations, and how to
test locally.

## The two supported forms

Both use the same path shape: `/bible/<book>/<chapter>[/<verse>]`.

1. **Custom scheme** — works today, for everyone, with zero setup:
   ```
   metanoia://bible/<book>/<chapter>[/<verse>]
   ```
2. **Android App Link (HTTPS)** — the "proper" form users can tap from a
   normal web link without an app-picker prompt, *once verification is set
   up* (see [Verification status](#verification-status-action-needed) below
   — **not done yet**):
   ```
   https://metanoia.bytecats.codes/bible/<book>/<chapter>[/<verse>]
   ```

`<verse>` is optional — omit it to land on the chapter with no specific verse
scrolled-to.

## Examples

| Link | Opens |
|---|---|
| `metanoia://bible/John/3/16` | John 3:16 |
| `metanoia://bible/Genesis/1` | Genesis 1 (no specific verse) |
| `metanoia://bible/1Samuel/17/45` | 1 Samuel 17:45 |
| `metanoia://bible/SongofSolomon/2/1` | Song of Solomon 2:1 |
| `metanoia://bible/jn/3/16` | John 3:16 (abbreviation form) |
| `https://metanoia.bytecats.codes/bible/Romans/8/28` | Romans 8:28 |

### Book name format

`<book>` accepts either:
- A **canonical book name**, case-insensitive, exactly as declared in
  `mobile/app/src/main/java/com/bytecats/metanoia/models/BibleConstants.kt`'s
  `BOOKS` list — no spaces, numeric prefixes attached directly (`1Samuel`,
  `2Corinthians`, `3John`, `SongofSolomon`).
- A **common abbreviation**, per that same file's `BIBLE_ABBREVIATIONS` map
  (`jn` → John, `1sam` → 1Samuel, `gen` → Genesis, etc.) — case-insensitive.
  This map currently only covers the 66-book Protestant canon; the
  deuterocanonical/Ethiopian-canon books (Tobit, Enoch, Jubilees,
  SirateTsion, etc.) must be linked by their exact canonical name until that
  map is extended.

An unresolvable book, an out-of-range chapter, or a non-numeric
chapter/verse all fail silently (the link is simply ignored) rather than
crashing — see `mobile/app/src/main/java/com/bytecats/metanoia/bible/DeepLink.kt`.

## Constructing a link from another app

```kotlin
val intent = Intent(Intent.ACTION_VIEW, Uri.parse("metanoia://bible/John/3/16"))
startActivity(intent)
```

Or from a web page / anywhere a plain hyperlink works (once App Links
verification is set up — the custom scheme form above works from a
`<a href="metanoia://...">` link too, though some browsers prompt "Open in
Metanoia?" for custom schemes rather than navigating directly, which is
exactly the friction real Android App Links exist to remove):

```html
<a href="https://metanoia.bytecats.codes/bible/John/3/16">Read John 3:16</a>
```

## Verification status — action needed

The manifest (`mobile/app/src/main/AndroidManifest.xml`) already declares the
HTTPS intent-filter with `android:autoVerify="true"`, but **Android App
Links verification is not actually live yet**. For Android to open Metanoia
directly (instead of showing an app-picker/browser fallback) for
`https://metanoia.bytecats.codes/...` links, that exact domain must serve a
real Digital Asset Links file at:

```
https://metanoia.bytecats.codes/.well-known/assetlinks.json
```

with content declaring this app's package name and signing certificate
fingerprint, e.g.:

```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.bytecats.metanoia",
    "sha256_cert_fingerprints": ["<SHA256 fingerprint of the signing cert>"]
  }
}]
```

This is a genuine, separate infrastructure decision — it needs an actual
DNS/hosting setup under `bytecats.codes` (or whatever domain is chosen),
not something to silently stand up. **Until that file exists and is
reachable, the `https://` form will not auto-open the app** — only the
`metanoia://` custom-scheme form works unconditionally today. This mirrors
the same "flag it, don't silently build the infrastructure" approach this
project already took for Flatpak's `flatpak update` support (see
`docs/PACKAGING.md`).

### Computing the fingerprint

For the checked-in debug keystore (`mobile/debug.keystore` — see
`docs/PACKAGING.md`'s "Homebrew formula" / release-signing history for why
this repo pins a fixed debug keystore rather than relying on Android's
auto-generated per-machine one):

```bash
keytool -list -v -keystore mobile/debug.keystore -storepass android -alias androiddebugkey \
  | grep 'SHA256:'
```

Use that exact value (colons and all, or reformatted per Google's Statement
List tooling — see the [official App Links docs](https://developer.android.com/training/app-links/verify-android-applinks))
in `assetlinks.json`. A production/Play-signed release build would need its
own separate fingerprint from whatever keystore actually signs that build.

## Testing locally

With a device/emulator connected and a debug build installed:

```bash
adb shell am start -W -a android.intent.action.VIEW \
  -d "metanoia://bible/John/3/16" com.bytecats.metanoia
```

The `-W` flag prints the launch result, including whether the intent
actually resolved to Metanoia. For the HTTPS form (before verification is
set up), the same command works to test the parsing/navigation logic even
though real-world tapping a browser link won't yet auto-open the app:

```bash
adb shell am start -W -a android.intent.action.VIEW \
  -d "https://metanoia.bytecats.codes/bible/Romans/8/28" com.bytecats.metanoia
```

## Implementation notes

- `com.bytecats.metanoia.bible.DeepLink` — pure parsing logic
  (`parseParts`, taking plain strings, not `android.net.Uri`, so it's
  directly unit-testable on the JVM without Robolectric — this codebase
  deliberately avoids Robolectric elsewhere too) plus a thin `parse(Uri)`
  wrapper for real use. 22 tests in
  `mobile/app/src/test/java/com/bytecats/metanoia/DeepLinkTest.kt`.
- `MainActivity` holds the incoming `Uri` as Activity-level Compose state
  (`pendingDeepLinkUri`), set from both `onCreate`'s initial intent and
  `onNewIntent` (the activity is `launchMode="singleTask"` specifically so
  a link tapped while the app is already running redelivers via
  `onNewIntent` instead of spawning a duplicate task). A `LaunchedEffect`
  reacts to that state, resolves it via `DeepLink.parse`, stores the result
  on `MainViewModel.pendingDeepLink`, and navigates to the `"bible"` route.
- `BibleScreen` consumes `MainViewModel.pendingDeepLink` in a
  `LaunchedEffect`, jumping straight to the "read" step (bypassing the
  book/chapter pickers, the same way tapping a search result already does)
  and clearing the pending state immediately after — so navigating back out
  of Bible and returning normally doesn't replay the same jump. Uses
  `BibleManager.fetchChapter` (local cache, then gateway/scrape) rather than
  the local-only `getChapter` the existing chapter-picker uses, since a
  shared link is likely to point at a chapter the recipient hasn't opened
  (and so doesn't have cached) before.

## What was NOT verified

No Android emulator/device was available in the environment this was built
in (`adb devices` returned empty) — the parsing logic has full unit test
coverage and the app builds successfully with both intent-filters compiled
into the manifest (confirmed via `aapt2 dump xmltree`), but the actual
end-to-end "tap a link, land on the right verse" flow has not been run on a
real device. That's the real remaining test.
