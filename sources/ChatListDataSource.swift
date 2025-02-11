//
//  ChatListDataSource.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

import AppKit

protocol ChatListDataSource: AnyObject, ChatSearchResultsDataSource {
    func numberOfChats(in chatListViewController: ChatListViewController) -> Int
    func chatListViewController(_ chatListViewController: ChatListViewController, chatAt index: Int) -> Chat
    func chatListViewController(_ viewController: ChatListViewController, indexOfChatID: String) -> Int?
    func snippet(forChatID: String) -> String?
}
