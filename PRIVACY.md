# Privacy Policy for jackqr

**Last Updated: December 3, 2025**

## Overview

jackqr is committed to protecting your privacy. This privacy policy explains our data collection, usage, and storage practices.

## TL;DR - Our Privacy Promise

**We collect ZERO personal data. Everything runs on your device. Your documents, flashcards, and study materials never leave your phone.**

---

## Data Collection

### What We DO NOT Collect

- ❌ Personal information (name, email, phone number)
- ❌ Documents or PDFs you import
- ❌ Flashcards you create or study
- ❌ Your answers during review sessions
- ❌ Usage analytics or telemetry
- ❌ Device identifiers or advertising IDs
- ❌ Location data
- ❌ Crash reports (unless you explicitly share via iOS)
- ❌ Any data transmitted to external servers

### What We DO Collect

**Nothing.** jackqr collects zero data from users.

---

## How Your Data is Processed

### 100% On-Device Processing

All AI inference, document processing, OCR, and flashcard grading occur **entirely on your device**:

1. **Documents**: Processed locally using Apple's Vision framework for OCR
2. **Text Simplification**: Generated on-device using Gemma AI models via MediaPipe
3. **Flashcard Grading**: AI evaluation runs locally—your answers are never sent anywhere
4. **Study Progress**: Saved locally using SwiftData (Apple's local database framework)

### Network Usage

jackqr uses your internet connection **only** for:

1. **Initial Model Download**: First-time download of AI models (~500MB-1GB) from HuggingFace
   - Models are downloaded once and cached locally
   - No personal data is transmitted during download

2. **Optional Updates**: If you choose to download additional models

**After initial setup, the app works 100% offline.** You can enable Airplane Mode and the app will function normally.

---

## Data Storage

### Local Storage Only

All app data is stored locally on your device using:

- **SwiftData**: Apple's framework for local data persistence
- **File System**: Model files and documents cached in app's local directory
- **UserDefaults**: App settings and preferences

### What's Stored Locally

- AI model files (downloaded once, ~500MB-1GB)
- Your imported documents and extracted text
- Flashcard decks and cards you create
- Study progress and review history
- App settings and preferences

### Data Deletion

You have complete control over your data:

- **Delete Individual Items**: Delete any document or flashcard deck
- **Clear All Data**: Uninstalling the app removes ALL data permanently
- **Export**: Your data stays on your device—export flashcards via CSV/JSON if needed

---

## Third-Party Services

### AI Models

- **Provider**: Google (Gemma models via MediaPipe)
- **Usage**: Models run entirely on-device
- **Data Sharing**: Zero. Models process data locally without any network transmission

### Model Hosting

- **Provider**: HuggingFace (public model repository)
- **Usage**: One-time model download
- **Data Collected**: Standard server logs (IP address, download timestamp) - NOT collected by us

### Open Source Libraries

jackqr uses the following open-source libraries:

- **MediaPipe Tasks GenAI** (Google): On-device AI inference
- **ZIPFoundation**: Model file extraction

These libraries run locally and do not transmit data.

---

## Children's Privacy

jackqr does not collect any personal information from anyone, including children under 13. The app is safe for all ages.

---

## Data Security

### On-Device Security

Your data is protected by:

- **iOS Sandbox**: App data is isolated from other apps
- **File System Encryption**: iOS encrypts all app data at rest
- **No Cloud Sync**: Data never leaves your device
- **No Authentication**: No accounts, passwords, or login credentials required

---

## Your Rights

Since we collect zero personal data, there is no data to:

- Request access to
- Request deletion of
- Request portability of
- Opt out of

All your data is already under your complete control on your device.

---

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be posted:

- On our GitHub repository
- On the App Store (via app updates)

Continued use of the app after changes constitutes acceptance of the updated policy.

---

## Open Source Transparency

jackqr is open-source. You can verify our privacy claims by reviewing the source code:

**GitHub Repository**: [github.com/inetimimizzle/jackqr](https://github.com/inetimimizzle/jackqr)

---

## Contact

For privacy questions or concerns:

- **GitHub Issues**: [github.com/inetimimizzle/jackqr/issues](https://github.com/inetimimizzle/jackqr/issues)

---

## Summary

**jackqr is privacy-first by design:**

1. ✅ Zero data collection
2. ✅ 100% on-device processing
3. ✅ No cloud servers
4. ✅ No analytics or tracking
5. ✅ No accounts or authentication
6. ✅ Open-source and verifiable
7. ✅ Works offline after initial setup

**Your data is yours. Always.**

---

*This privacy policy is effective as of December 3, 2025.*
