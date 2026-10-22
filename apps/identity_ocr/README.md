# Algerian Identity OCR

A standalone Flutter app for reading text from Algerian national ID cards and
passports on the device. It is kept separate from the BenMahdia patient app:
this app has no backend, account flow, analytics, or persistence.

## Requirements

The checked-in dependency lock was resolved with Flutter 3.38.7 and Dart
3.10.7. The app uses:

| Package | Version | Purpose |
| --- | --- | --- |
| google_mlkit_text_recognition | 0.16.0 | On-device Latin script OCR |
| image_picker | 1.2.3 | Camera intent and photo library selection |
| image_cropper | 12.2.1 | Manual crop and rotation |
| image | 4.7.0 | Orientation-aware image quality heuristics |
| path_provider | 2.1.5 | App temporary directory for short-lived working copies |

The ML Kit Flutter plugin supports Android and iOS. Its documented minimums
are Android API 21 and iOS 15.5; the selected image_picker release raises the
effective Android minimum to API 24. This project sets Android minSdk to 24,
compiles with SDK 36 or the Flutter SDK's newer compile SDK, and sets iOS to
15.5. iOS builds require macOS, Xcode 15.3 or newer, and CocoaPods. The current
Windows workspace can analyze/test Dart and build Android, but cannot build an
iOS app.

The Google ML Kit plugin is a Flutter wrapper around native Google ML Kit APIs.
It does **not** ship a standalone .tflite file. No OCR model was trained,
downloaded, or copied into this project. The selected Latin recognizer runs
on-device. ML Kit does not recognize Arabic script, so Arabic text printed on
some cards will not be read by this OCR engine; the interface says this before
scanning. The app UI itself is available in French and Arabic.

## Run

From this directory, run:

    flutter pub get
    flutter run

The user chooses a document type, takes a photo or chooses one from the
gallery, reviews/crops/rotates it, then starts OCR. The extracted fields are
editable. Copying is disabled until the user confirms that they reviewed the
fields.

## Checks

    flutter analyze
    flutter test
    flutter build apk --debug

The tests use synthetic MRZ and text fixtures only. They validate parser
behavior, ICAO TD3 check digits, ambiguous dates, invalid and partial input,
conservative ID labels, and the privacy-safe diagnostic interface. They do not
measure OCR accuracy on real documents.

## Parsing behavior and limitations

- Passport support is limited to the common two-line, 44-character TD3 MRZ.
  The parser checks document-number, birth-date, expiry-date, and composite
  check digits. OCR corrections are restricted to numeric MRZ positions and
  are reported as warnings.
- Numeric dates printed on the national ID are read day/month/year (for
  example 05/03/1990 is 5 March 1990); two-digit years stay unresolved.
- The MRZ is searched for as a pair of 44-character lines, so the printed
  "PASSEPORT" header above it is ignored. Label cues must end at a separator
  or space ("NOM" does not match "NOMBRE"), and a value is never taken from a
  line that starts another field label.
- ICAO MRZ dates contain a two-digit year. Since the format does not establish
  a century by itself, those dates remain unresolved and the original MRZ
  values are shown for manual correction.
- The national ID parser reads only uniquely matched, explicitly labeled
  fields. It does not infer fields from their order or from unlabeled numbers.
  Its generic French/Arabic label cues have not been validated against genuine
  Algerian card samples or different card generations. Such templates need
  lawful test samples and validation before production use.
- ML Kit text confidence is not consistent across both supported native
  platforms through this plugin, so the app shows review/validation states
  rather than inventing a numeric confidence score.
- Quality checks use uncalibrated heuristics for resolution, brightness,
  glare, and blur. There is no automatic card-boundary detector or perspective
  correction; cropping and rotation are manual.
- OCR and check digits do not establish document authenticity or identity
  ownership. No genuine sample accuracy claim is made.

## Privacy and retention

Images are read locally. The app has no HTTP client, backend URL, analytics, or
crash-reporting dependency, and the Android manifest does not request Internet
access. OCR text and parsed fields stay in memory until the result screen is
closed. The app does not save results. It deletes its working copies, crop
outputs, and picker-generated files in temporary directories when scanning
ends, the user retakes, or the capture screen closes; cleanup is best effort if
the operating system has already removed a cache file. Gallery originals are
not modified or deleted. Diagnostic messages contain only fixed operational
event names and never accept document data, raw OCR text, or image paths.

The app never uploads card images, MRZ data, document numbers, or extracted
fields. Copy/export happens only after an explicit user confirmation.
