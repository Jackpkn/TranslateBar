# TranslateBar 🌐

A lightweight, zero-disk-bloat macOS menu bar app that automatically translates whatever you're typing in any app (WhatsApp, Slack, Messages, Web Browser, etc.) using DeepL.

---

## ✨ Features

- **🌐 System-Wide Translation**: Type naturally, pause for ~1 second (or press Enter), and watch your text get automatically translated in-place.
- **🔑 Keychain Security**: Your DeepL API key is securely stored in macOS Keychain (`Security` framework).
- **🛡️ Smart App Exclusion**: Automatically ignores typing in coding apps, terminals, and password managers (Terminal, iTerm2, VS Code, Xcode, 1Password, Bitwarden, Sublime Text).
- **⚡ Floating HUD Preview**: A subtle floating overlay appears near your cursor to show real-time translation status (`Translating...`, `Done!`, or error notices).
- **⌨️ Global Selection Hotkey (`Option + T`)**: Highlight text anywhere on screen and press `Option + T` for instant HUD translation and back-translation verification.
- **🔍 Spotlight Quick Translate Palette (`Cmd + Shift + T`)**: A Raycast/Spotlight-style floating palette window for instant typing and one-click copy.
- **🔊 Native Audio Pronunciation**: Pronounce translated text out loud using macOS built-in `AVSpeechSynthesizer`.
- **📜 Translation History**: View and re-copy your last 50 translated sentences directly from the menu bar.
- **📖 Custom Glossary**: Protect brand names or custom terms from being translated.
- **📊 API Quota Monitor**: Live tracking of monthly DeepL character usage (`X / 500,000 chars used`).
- **🎭 Tone & Formality**: Switch between **Default**, **Formal**, and **Informal** translation tones.
- **📋 Clipboard Auto-Translate**: Optional background monitor that translates text whenever you copy (`Cmd + C`).

---

## 🚀 Setup & Usage

1. **Get a DeepL API key** (free tier supports up to 500,000 chars/month at https://www.deepl.com/pro-api). Free keys end in `:fx`.
2. **Build and run**:
   ```bash
   cd TranslateBar
   swift run
   ```
3. **Set your API Key**:
   - Click the 🌐 icon in your macOS menu bar.
   - Select **Set DeepL API Key...**
   - Enter your key and click **Save** (it will be saved securely in your Keychain).

---

## ⌨️ Shortcuts & Hotkeys

- **`Option + T`**: Translate currently highlighted text anywhere on screen.
- **`Cmd + Shift + T`**: Open the Spotlight-style Quick Translate Palette.
- **`Return / Enter`**: Translates current typed line in-place before sending.

---

## 🔒 Permissions & Security

TranslateBar requires macOS **Accessibility** and **Input Monitoring** permissions:
- Open **System Settings** → **Privacy & Security** → **Accessibility** (and **Input Monitoring**).
- Enable permissions for Terminal / TranslateBar.

---

## 🛠️ Project Structure

```
Sources/TranslateBar/
├── AppDelegate.swift                  # Status bar menu, language selection, formality, & hotkeys
├── AccessibilityHelper.swift          # Focused UI element inspection & cursor coordinate helper
├── AppFilter.swift                    # App exclusion & blacklist tracking (Terminal, Xcode, VS Code)
├── AudioSpeechHelper.swift            # Native text-to-speech audio pronunciation (AVFoundation)
├── ClipboardMonitor.swift             # Background clipboard observer (Cmd + C auto-translate)
├── DeepLService.swift                 # DeepL REST API client with Keychain & /v2/usage support
├── GlobalHotkeyManager.swift          # Global Option + T hotkey listener
├── GlossaryManager.swift              # Custom protected terms & phrasebook dictionary
├── HUDWindowController.swift          # Floating overlay HUD window near cursor
├── KeychainHelper.swift               # macOS Keychain manager (SecItem API)
├── KeyEventTap.swift                  # Global CGEvent key listener & debounced flush
├── PasteHelper.swift                  # Clipboard paste & restoration helper
├── QuickPaletteWindowController.swift # Spotlight-style floating translation palette window
├── TranslationHistory.swift           # Sliding log of recent translations
├── UsageTracker.swift                 # DeepL character quota calculation & formatting
└── main.swift                         # App entry point & NSApplication initialization
```
