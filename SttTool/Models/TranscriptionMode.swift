import Foundation

struct TranscriptionMode: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let systemPrompt: String
    let isBuiltIn: Bool

    static let voice = TranscriptionMode(
        id: "voice",
        name: "Voice",
        systemPrompt: "",
        isBuiltIn: true
    )

    static let message = TranscriptionMode(
        id: "message",
        name: "Message",
        systemPrompt: "You are a text formatter. Take the following speech transcription and clean it up for a chat message. Make it casual and conversational. Fix grammar, remove filler words (um, uh, like), and make it concise. Do NOT add any preamble or explanation. Output ONLY the cleaned text.",
        isBuiltIn: true
    )

    static let email = TranscriptionMode(
        id: "email",
        name: "Email",
        systemPrompt: "You are a text formatter. Take the following speech transcription and format it as a professional email. Add appropriate greeting and closing. Fix grammar, remove filler words, and structure it clearly. Do NOT add any preamble or explanation. Output ONLY the formatted email text.",
        isBuiltIn: true
    )

    static let formal = TranscriptionMode(
        id: "formal",
        name: "Formal",
        systemPrompt: "You are a text formatter. Take the following speech transcription and rewrite it in a formal, professional tone. Fix grammar, remove filler words, and use polished language. Do NOT add any preamble or explanation. Output ONLY the formatted text.",
        isBuiltIn: true
    )

    static let code = TranscriptionMode(
        id: "code",
        name: "Code",
        systemPrompt: "You are a text formatter for developers. Take the following speech transcription and clean it up, preserving all technical terms, function names, variable names, and programming concepts exactly. Fix grammar and remove filler words but keep technical accuracy. Do NOT add any preamble or explanation. Output ONLY the cleaned text.",
        isBuiltIn: true
    )

    static let llmOptimize = TranscriptionMode(
        id: "llm_optimize",
        name: "LLM Optimize",
        systemPrompt: "You are a speech-to-prompt optimizer. Take the following speech transcription and condense it into a clear, concise LLM prompt. Remove all filler words, hedging, repetition, and verbal thinking-out-loud. Distill the core intent and requirements into direct, token-efficient instructions. Preserve technical details and specifics but eliminate conversational padding. Do NOT add any preamble or explanation. Output ONLY the optimized prompt text.",
        isBuiltIn: true
    )

    static let allBuiltIn: [TranscriptionMode] = [voice, message, email, formal, code, llmOptimize]
}
