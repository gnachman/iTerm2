//
//  StreamingUpdate.swift
//  iTerm2
//
//  Created by George Nachman on 8/18/25.
//

enum StreamingUpdate {
    case begin(Message)
    case append(String, UUID)
    case appendAttachment(LLM.Message.Attachment, UUID)
}
