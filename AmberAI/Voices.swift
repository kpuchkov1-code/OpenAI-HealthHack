//
//  Voices.swift
//  AmberAI
//
//  The voices Amber can speak in. With the Runware TTS path, a voice is optional
//  (Fish Audio has a usable default), but the preference is kept so a future
//  OpenAI-realtime path could use it directly.
//

import Foundation

let VOICES: [String] = [
    "alloy", "ash", "ballad", "coral", "echo",
    "sage", "shimmer", "verse", "marin", "cedar",
]

let DEFAULT_VOICE = "marin"

func isVoice(_ v: String?) -> Bool {
    guard let v else { return false }
    return VOICES.contains(v)
}
