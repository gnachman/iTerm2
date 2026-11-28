//
//  iTermGrammarProcessor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/21/18.
//

import Foundation

// Associates production rules with syntax tree transforms. Combines production
// rules to make numbered BNF. Offers an interface to run a transform block for
// a syntax tree, whose tag gives the index of the rule.
@objc(iTermGrammarProcessor)
class iTermGrammarProcessor: NSObject {
    private var rules = [String]()
    private var transforms = [(CPSyntaxTree?) -> Any?]()

    // Concatenated rules with each prefixed by a unique number.
    @objc var backusNaurForm: String {
        return rules.joined(separator: "\n")
    }

    // The rule's number is its index, which is the tag CoreParse gives the
    // syntax trees that the rule produces. A nil rule is written as
    // “(null)”. Every rule needs a transform.
    @objc(addProductionRule:treeTransform:)
    func addProductionRule(_ bnf: String?,
                           treeTransform transform: ((CPSyntaxTree?) -> Any?)?) {
        guard let transform else {
            it_fatalError("A production rule needs a tree transform: \(bnf ?? "(null)")")
        }
        rules.append("\(rules.count) \(bnf ?? "(null)");")
        transforms.append(transform)
    }

    // Calls the block for the rule that matched the root of this tree and
    // returns its value. A nil tree has tag zero.
    @objc(transformSyntaxTree:)
    func transform(_ syntaxTree: CPSyntaxTree?) -> Any? {
        let tag = syntaxTree?.rule?.tag ?? 0
        guard let index = Int(exactly: tag), transforms.indices.contains(index) else {
            return nil
        }
        return transforms[index](syntaxTree)
    }
}
