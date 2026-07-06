//
//  ChatProviderBinding.swift
//  iTerm2
//
//  Model-layer enforcement that a chat stays on one provider (vendor) for its
//  whole life. The UI already locks the provider picker after the first
//  conversational message, but turns can arrive from surfaces with no picker
//  (the phone sends configuration == nil) or with a stale/hand-crafted
//  configuration, so the binding is decided here, next to the model, and the
//  agent consults it before every turn.
//
//  The chat's binding is the persisted Chat.modelName; the vendor it implies
//  is the bound provider. Switching models WITHIN the bound vendor remains
//  allowed (that is a model switch, not a provider switch).
//

import Foundation

enum ChatProviderBinding {
    enum Verdict: Equatable {
        /// Run the turn on `modelName` (nil = the global default model).
        /// When `bindChatTo` is non-nil the chat had no binding yet and the
        /// caller must persist it as Chat.modelName.
        case proceed(modelName: String?, bindChatTo: String?)
        /// The turn names a model on a different provider than the chat is
        /// bound to; the turn must not be sent. `reason` is user-facing.
        case reject(reason: String)
    }

    /// Decide how a turn's model interacts with the chat's binding.
    /// - boundModelName: the chat's persisted model (Chat.modelName), nil if
    ///   the chat has never been bound.
    /// - turnModelName: the model named by the incoming message's
    ///   configuration, nil when the surface sent none (e.g. the phone).
    /// - defaultModelName: the global default model's name, used to bind a
    ///   chat whose first turn names no model.
    /// - vendor: resolves a model name to its provider; nil when unknown
    ///   (e.g. a retired or manual model whose vendor can't be classified).
    static func evaluate(boundModelName: String?,
                         turnModelName: String?,
                         defaultModelName: String?,
                         vendor: (String) -> iTermAIVendor?) -> Verdict {
        guard let bound = boundModelName else {
            // First conversational turn: bind the chat to whatever model it
            // runs on (the turn's, else the global default). When neither
            // exists there is nothing to bind to; proceed and let the
            // request surface the ordinary "no model configured" error.
            let effective = turnModelName ?? defaultModelName
            return .proceed(modelName: effective, bindChatTo: effective)
        }
        guard let turn = turnModelName else {
            // No configuration on the turn (the phone sends none): the
            // chat's own model applies, NOT the global default, so a chat
            // pinned to one provider never silently runs on another.
            return .proceed(modelName: bound, bindChatTo: nil)
        }
        if turn == bound {
            return .proceed(modelName: turn, bindChatTo: nil)
        }
        guard let boundVendor = vendor(bound), let turnVendor = vendor(turn) else {
            // A retired or manual model whose vendor can't be classified
            // must never brick the chat; be permissive.
            return .proceed(modelName: turn, bindChatTo: nil)
        }
        if boundVendor == turnVendor {
            // A model switch within the provider is allowed (the UI offers
            // exactly these).
            return .proceed(modelName: turn, bindChatTo: nil)
        }
        return .reject(reason: "This chat uses “\(bound)”, and “\(turn)” belongs to a different AI provider. A chat cannot change providers once the conversation has started; start a new chat to use “\(turn)”.")
    }

    /// Resolve a model name to its vendor the way request routing does: the
    /// built-in catalog first, then manually configured models, then the
    /// name-based heuristic for retired models.
    static func vendor(forModelName name: String) -> iTermAIVendor? {
        if let vendor = AIMetadata.instance.models.first(where: { $0.name == name })?.vendor {
            return vendor
        }
        if let vendor = LLMMetadata.manualModels().first(where: { $0.name == name })?.vendor {
            return vendor
        }
        return LLMMetadata.vendor(forModelName: name)
    }
}
