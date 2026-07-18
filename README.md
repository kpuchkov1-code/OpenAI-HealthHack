# AmberAI

A native **SwiftUI iOS** app — an AI health companion. Amber listens, remembers, and helps
you keep track of your health between doctor visits: talk to her by voice, log food and weight,
build habits, pull in wearable data, and generate a shareable doctor report.

This is a native iOS port of the original Ember web app built for the OpenAI HealthHack.

## Features

- **Talk** — real-time voice conversation with Amber, streamed both ways over OpenAI's Realtime API (server-side turn detection + barge-in).
- **Type** — text chat and durable-fact extraction, powered by Runware.
- **Food logging** — estimate nutrition from a typed description or a photo (vision model via Runware).
- **Weight & habits** — track weight over time and build daily habits with a dashboard.
- **Records** — send Amber into a Zoom/Meet/Teams appointment as a note-taker (Recall.ai), or listen on-device.
- **Wearables** — Apple Watch (HealthKit), plus Oura and WHOOP over OAuth, feeding Amber's context.
- **Doctor report** — generate a PDF summary to share with a clinician.
- **On-device speech-to-text** and a safety net for concerning input.

## Requirements

- Xcode 16 or later
- iOS 18 SDK
- API keys for the services you want to use (see below)

## Setup

The app reads secrets from a **git-ignored `Secrets.swift`** so keys never land in the repo.
After cloning, create `AmberAI/Secrets.swift`:

```swift
import Foundation

enum Secrets {
    /// OpenAI Realtime key powering the Talk screen.
    static let openAIAPIKey = "sk-proj-..."
}
```

Then open `AmberAI.xcodeproj` and build. The project uses Xcode's synchronized file groups,
so the new file is picked up automatically — no project changes needed.

Other providers (Runware, Recall.ai, Oura, WHOOP) can be configured in **Settings → Advanced**
at runtime, or baked into `Config.swift`. See `Config.swift` for the full list and defaults.

## Configuration reference

| Provider   | Used for                              | Where to set the key            |
| ---------- | ------------------------------------- | ------------------------------- |
| OpenAI     | Talk (real-time voice)                | `Secrets.swift` / Settings      |
| Runware    | Chat, fact extraction, food, TTS      | `Config.swift` / Settings       |
| Recall.ai  | Meeting-bot note-taker (Records)      | `Config.swift` / Records sheet  |
| Oura       | Wearable data (OAuth or legacy PAT)   | Settings → Advanced             |
| WHOOP      | Wearable data (OAuth)                 | Settings → Advanced             |

## A note on secrets

Never commit real API keys. `Secrets.swift` is git-ignored for this reason, and OpenAI keys
committed to a public repo are automatically revoked by GitHub push protection. If a key is ever
exposed, rotate it at the provider and update `Secrets.swift`.
