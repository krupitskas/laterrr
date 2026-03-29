# Laterrr

Laterrr is a SwiftUI iPhone and iPad app for quickly remembering cafes and restaurants from a photo.

The first cut in this repo is built around:

- A live back-camera capture experience on launch
- OCR with Vision to pull storefront text from the image
- Nearby venue lookup with MapKit
- Local deterministic ranking that prioritizes OCR sign matches and nearby results
- SwiftData persistence with CloudKit-ready configuration
- A configurable Apple Maps or Google Maps export/opening flow

## Open The Project

```bash
xcodegen generate
open Laterrr.xcodeproj
```

## Setup Notes

- The app targets iOS 26 and keeps the capture-to-match flow local: Vision OCR plus deterministic ranking over nearby map results.
- The SwiftData container is configured for CloudKit automatically. To get real iCloud sync on your own Apple ID, set your signing team in Xcode and keep the iCloud capability enabled.
- Apple Maps and Google Maps public APIs support search, place IDs, and deep links well. This starter app therefore saves a first-party iCloud list inside Laterrr and exports or opens places in the chosen map provider instead of attempting unsupported direct writes to native saved lists.

## Project Shape

- `Laterrr/App`: app bootstrapping and root navigation
- `Laterrr/Features/Capture`: live capture flow and result review
- `Laterrr/Features/Places`: saved list and place detail
- `Laterrr/Features/Settings`: provider and capture preferences
- `Laterrr/Services`: camera, location, OCR, map search, ranking, export
- `Laterrr/Models`: SwiftData model and ranking structs
