# Kosha's Library — Android app

A book tracker with your 195 books built in, plus barcode scanning and ISBN lookup.

## Get the APK without installing anything (GitHub builds it for you)
1. Sign in at github.com (free account) → **+** → **New repository** → name it `kosha-library` → **Create repository**.
2. On the new repo page click **uploading an existing file**. Unzip `kosha_library_android.zip`, open the
   `kosha_library` folder, select **everything inside it** (including the `.github` folder) and drag it in → **Commit changes**.
3. Open the **Actions** tab. A "Build APK" run starts by itself and takes about 6–8 minutes.
4. When it shows a green tick, click the run → under **Artifacts** download **kosha-library-apk** → unzip → `app-release.apk`.
5. Send the APK to your phone (WhatsApp to yourself, Google Drive or email), tap it and allow installing apps from that source.

If the `.github` folder didn't upload (some browsers skip folders that start with a dot):
**Add file → Create new file**, type the name `.github/workflows/build-apk.yml`, paste the contents of that file
from the zip, and commit.

## Build it on your own computer (needs Flutter + Android SDK)
You need Flutter and Android Studio (or just the Android SDK) installed.

**Windows**
```powershell
cd kosha_library
powershell -ExecutionPolicy Bypass -File .\setup.ps1
flutter build apk --release
```
**macOS / Linux**: `bash setup.sh` then `flutter build apk --release`

The APK lands at `build/app/outputs/flutter-apk/app-release.apk`. Copy it to your phone and open it
(allow "install unknown apps" for your file manager), or plug the phone in and run `flutter run --release`.

## What's inside
- **Scan / add**: scan the barcode on the back cover, type an ISBN, or search by title.
  Lookups use Google Books, with Open Library as a fallback. No API key is needed.
  If you already own the book, the app tells you and opens it instead of adding a copy.
- **Shelf**: real covers (by ISBN), with a designed cover when there isn't one. Search, filter by status,
  genre or favourites, and sort.
- **Book page**: status, half-star ratings, favourite, page progress (+10/+25/+50), start and finish dates,
  format, genre, moods, review, favourite quote.
- **Stats**: 2026 goal ring, books finished per month, ratings, top genres and authors.
- **Backup / move data**: *Stats → Copy library as CSV* and *Import CSV*. These use the same format
  as the web tracker's "Copy my library as CSV", so you can carry ratings and reviews either way.

Your data is stored on the phone (SharedPreferences). Uninstalling the app deletes it, so copy a CSV backup first.

## Files
- `lib/main.dart`: app entry, theme
- `lib/models/book.dart`: Book model
- `lib/services/library_store.dart`: library state, saving, filters, CSV import/export
- `lib/services/book_lookup.dart`: Google Books and Open Library lookup
- `lib/screens/`: shelf, book detail, add/search, barcode scanner, stats
- `lib/widgets/`: covers and star ratings
- `assets/books.json`: your library from MyLibrary.xlsx
