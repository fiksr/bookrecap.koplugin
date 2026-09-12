# 📖 BookRecap for KOReader

[![KOReader](https://img.shields.io/badge/KOReader-2024%2B-blue.svg)](https://github.com/koreader/koreader)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Zero Spoilers](https://img.shields.io/badge/Zero--Spoilers-Guaranteed-red.svg)]()
[![Storefront Compatible](https://img.shields.io/badge/Storefront-Compatible-purple.svg)](https://omer-faruq.github.io/koreader-plugin-index/)

**BookRecap** is an intelligent, strictly spoiler-guarded reading companion for **KOReader**. 

Ever put down an 800-page fantasy or sci-fi epic, come back after two weeks, and completely forgotten what just happened? Or met a character whose name sounds familiar, but searching online would spoil major future plot twists? **BookRecap** solves this by strictly bounding its answers to your **current chapter and page**.

---

## ✨ Features

- 🛡️ **Strict Zero-Spoiler Guard**: The AI is strictly instructed with your exact reading location (`Chapter 14, Page 435`). It summarizes *only* what has happened up to that moment, with zero future plot twists, secret identities, or deaths revealed.
- 📖 **"Catch Me Up" (Narrative Recap)**: Generates 3–4 concise bullet points summarizing recent plot developments when resuming a book.
- 👤 **"Who is this?" (Character Memory)**: Highlight any character's name in the text and tap **"Who is this?"** to get a 2-sentence spoiler-free reminder of who they are and their role so far.
- 💾 **Automatic Offline Caching**: Character bios and chapter summaries are cached locally on your device. Once looked up, they open in **0.0 seconds** with zero Wi-Fi needed!
- ⚡ **Blazing Fast Multi-Provider Support**:
  - **Groq** (Recommended: free tier, responds in under 1.5 seconds via Llama 3.3).
  - **Google Gemini** (Free tier via Gemini 1.5 Flash).
  - **OpenAI** (GPT-4o-mini).
  - **DeepSeek** (DeepSeek-V3 / Chat).
  - **Local Ollama** (100% offline via your local home network).
- ⌨️ **Zero-Typing Key Import**: Don't want to type long API keys on e-ink? Just drop `ai_key.txt` onto your Kindle root via USB and tap **Import Key**!

---

## 📸 How It Works

### 1. "Catch Me Up" (Story Recap)
1. While reading any book, tap the top menu ➔ **Tools** ➔ **BookRecap** ➔ **📖 Catch Me Up**.
2. BookRecap analyzes your current chapter and page, then displays a clear 3–4 bullet recap in a clean scrollable reader dialog.

### 2. "Who is this?" (Character Identification)
1. Select any character's name in your book (e.g., *Avrana Kern*, *Holsten*, *Paul Atreides*).
2. Tap **"Who is this?"** in the highlight popup.
3. The spoiler-free identity card appears instantly.

---

## 🔑 Setup & API Keys

### Option A: One-Tap File Import (Recommended for E-Ink)
1. Connect your Kindle/Kobo to your PC via USB.
2. Create a file named `ai_key.txt` in the root folder (`/mnt/us/ai_key.txt`).
3. Paste your API key inside (e.g. from [console.groq.com](https://console.groq.com) or [aistudio.google.com](https://aistudio.google.com)).
4. In KOReader, go to **Tools** ➔ **BookRecap** ➔ **📥 Import Key from /mnt/us/ai_key.txt**.
5. The key is saved securely and the temporary file is deleted!

### Option B: On-Screen Keyboard
- Go to **Tools** ➔ **BookRecap** ➔ **⌨️ Enter API Key Manually**.

---

## 🚀 Installation

### Via Storefront / AppStore
1. Open KOReader ➔ **Tools** ➔ **App Store** (or **Storefront**).
2. Search for **BookRecap** and tap **Install**.
3. Restart KOReader.

### Manual Installation
1. Download `bookrecap.koplugin.zip` from Releases.
2. Extract to:
   - **Kindle**: `/mnt/us/koreader/plugins/bookrecap.koplugin/`
   - **Kobo**: `.kobo/koreader/plugins/bookrecap.koplugin/`
3. Restart KOReader.

---

## 📄 License

MIT License. Built for the KOReader e-reading community.
