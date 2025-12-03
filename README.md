# jackqr

**Offline AI-powered study companion for students. Transform chaotic PDFs into readable content and master your courses with AI-graded flashcards—no internet required.**

[![On-Device](https://img.shields.io/badge/100%25-On--Device-purple?style=flat-square)]()
[![Offline First](https://img.shields.io/badge/Offline-First-green?style=flat-square)]()
[![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue?style=flat-square)]()

---

## The Problem

In Nigeria (and across Africa), most university students can't afford textbooks. A single textbook can cost more than a month's allowance. So students share PDFs—scanned lecture notes, photographed textbook pages, materials passed around on WhatsApp groups.

But these PDFs are often terrible:
- Poorly scanned and badly formatted
- 200+ pages of dense, unstructured text
- Nearly impossible to read on a phone
- No way to search or navigate efficiently

On top of that, internet data is expensive and unreliable. Cloud-based AI tools aren't an option when your data runs out mid-study session.

**jackqr solves this by bringing AI-powered study tools completely offline.**

---

## Features

### 📚 Document Processing
- Import PDFs or images of textbook pages
- On-device OCR extracts text from even poorly scanned documents
- Intelligent chunking breaks content into digestible sections
- AI-powered simplification rewrites complex passages while preserving core concepts

### 📖 Smart Reading
- Clean, formatted text that's easy to read on any screen
- Navigate through content in logical chunks
- Simplify difficult sections on-demand with a single tap

### 🎴 Flashcard System with AI Grading
- Create flashcard decks from your study materials
- Import existing flashcards via CSV/JSON
- SM-2 spaced repetition algorithm optimizes review timing
- **On-device AI grades your answers**—understands context and semantic meaning, not just exact matches
- Track progress and focus on what you need to review

### 🔒 100% Offline
- Everything runs locally after initial model download
- No subscriptions, no cloud fees, no data costs
- Works in areas with poor or no internet connectivity

---

## Technical Stack

| Component | Technology |
|-----------|------------|
| **Framework** | SwiftUI |
| **AI Inference** | MediaPipe Tasks GenAI (Gemma models) |
| **OCR** | Apple Vision Framework |
| **Persistence** | SwiftData |
| **PDF Processing** | PDFKit |

### On-Device AI Models
- **Gemma 3 1B** - Primary model for text simplification and flashcard grading
- **Gemma 3 270M** - Lightweight alternative for older devices

---

## How It Works

### Document Flow
1. Import PDF or capture image of textbook page
2. Vision framework extracts text via OCR
3. Text chunker segments content at natural boundaries
4. AI simplifier rewrites complex passages (optional)
5. Read through clean, navigable content

### Flashcard Grading
The AI grader uses a simple YES/NO/PARTIAL prompt for reliability on small models:

```
Question: What is the powerhouse of the cell?
Expected: Mitochondria
User Answer: The mitochondria produces ATP energy

AI Response: YES (semantically equivalent)
```

Fallback to string similarity with semantic bonuses ensures grading works even if the model returns empty responses.

---

## Setup

### Requirements
- iOS 17.0+
- ~500MB-1GB storage for AI models
- iPhone with A12 chip or newer recommended

### Installation

```bash
git clone https://github.com/inetimimizzle/jackqr.git
cd jackqr
pod install
open Pic2PDF.xcworkspace
```

### First Run
1. Build and run the app
2. Navigate to Settings
3. Download your preferred AI model (Gemma 1B recommended)
4. Start importing documents or creating flashcards

---

## Project Structure

```
Pic2PDF/
├── Models/
│   ├── Document.swift          # Document data model
│   └── Flashcard.swift         # Flashcard & Deck models
├── Services/
│   ├── DocumentManager.swift   # Document persistence
│   ├── TextExtractor.swift     # OCR service
│   ├── TextChunker.swift       # Content segmentation
│   ├── TextSimplifier.swift    # AI simplification
│   ├── FlashcardManager.swift  # Flashcard persistence
│   └── FlashcardGrader.swift   # AI grading service
├── Views/
│   ├── LibraryView.swift       # Document library
│   ├── ReaderView.swift        # Document reader
│   ├── FlashcardsView.swift    # Flashcard decks
│   ├── DeckDetailView.swift    # Deck management
│   └── ReviewSessionView.swift # Study session UI
├── OnDeviceLLMService.swift    # Core LLM inference
├── ModelDownloadManager.swift  # Model management
└── ContentView.swift           # Main navigation
```

---

## Flashcard Import Format

### CSV
```csv
question,answer
What is photosynthesis?,The process by which plants convert sunlight into energy
What is the capital of Nigeria?,Abuja
```

### JSON
```json
[
  {"question": "What is photosynthesis?", "answer": "The process by which plants convert sunlight into energy"},
  {"question": "What is the capital of Nigeria?", "answer": "Abuja"}
]
```

---

## Privacy

jackqr is privacy-first by design:
- Zero data collection
- 100% on-device processing
- No cloud servers or analytics
- No accounts required
- Works completely offline

See [PRIVACY.md](./PRIVACY.md) for full details.

---

## License

[MIT License](./LICENSE)

---

## Acknowledgments

- **Google MediaPipe Team** - On-device AI inference framework
- **Google Gemma Team** - Open-source language models
- **Apple** - Vision framework for OCR

---

**Built for students who make the most of what they have. 📚**
