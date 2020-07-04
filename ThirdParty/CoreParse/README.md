CoreParse
=========

CoreParse is a parsing library for Mac OS X and iOS.  It supports a wide range of grammars thanks to its shift/reduce parsing schemes.  Currently CoreParse supports SLR, LR(1) and LALR(1) parsers.

For full documentation see http://beelsebob.github.com/CoreParse.

Why Should You use CoreParse
----------------------------

You may wonder why and/or when you should use CoreParse.  There are already a number of parsers available in the wild, why should you use this one?

* Compared to ParseKit:
  * CoreParse supports more languages (LR(1) languages cover all LL(1) languages and more).  In practice, LALR(1) grammars cover most useful languages.
  * CoreParse produces faster parsers.
  * CoreParse parsers and tokenisers can be archived using NSKeyedArchivers to save regenerating them each time your application runs.
  * CoreParse's parsing algorithm is not recursive, meaning it could theoretically deal with much larger hierarchies of language structure without blowing the stack.
* Compared to lex/yacc or flex/bison:
  * While I have no explicitly benchmarked, I would expect parsers produced by lex/yacc or flex/bison to be faster than CoreParse ones.
  * CoreParse does not _require_ you to compile your parser before you start (though it is recommended).
  * CoreParse provides allows you to specify grammars right in your Objective-C source, rather than needing another language, which intermixes C/Obj-C.
  * CoreParse does not use global state, multiple parser instances can be run in parallel (or the same parser instance can parse multiple token streams in parallel).

Where is CoreParse Already Used?
--------------------------------

CoreParse is already used in a major way in at least two projects:

* Francis Chong uses it in his [CSS selector convertor](https://github.com/siuying/CSSSelectorConverter) to parse CSS3
* Matt Mower uses it in his [statec](https://github.com/mmower/statec) project to parse his state machine specifications.
* I use it in [OpenStreetPad](https://github.com/beelsebob/OpenStreetPad/) to parse MapCSS.

If you know of any other places it's been used, please feel free to get in touch.

Parsing Guide
=============

CoreParse is a powerful framework for tokenising and parsing.  This document explains how to create a tokeniser and parser from scratch, and how to use those parsers to create your model data structures for you.  We will follow the same example throughout this document.  This will deal with parsing a simple numerical expression and computing the result.

gavineadie has implemented this entire example, to see full working source see https://github.com/beelsebob/ParseTest/.

Tokenisation
------------

CoreParse's tokenisation class is CPTokeniser.  To specify how tokens are constructed you must add *token recognisers* in order of precidence to the tokeniser.

Our example language will involve several symbols, numbers, whitespace, and comments.  We add these to the tokeniser:

```objective-c
CPTokeniser *tokeniser = [[[CPTokeniser alloc] init] autorelease];
[tokeniser addTokenRecogniser:[CPNumberRecogniser numberRecogniser]];
[tokeniser addTokenRecogniser:[CPWhiteSpaceRecogniser whiteSpaceRecogniser]];
[tokeniser addTokenRecogniser:[CPQuotedRecogniser quotedRecogniserWithStartQuote:@"/*" endQuote:@"*/" name:@"Comment"]];
[tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"+"]];
[tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"-"]];
[tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"*"]];
[tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"/"]];
[tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@"("]];
[tokeniser addTokenRecogniser:[CPKeywordRecogniser recogniserForKeyword:@")"]];
```

Note that the comment tokeniser is added before the keyword recogniser for the divide symbol.  This gives it higher precidence, and means that the first slash of a comment will not be recognised as a division.

Next, we add ourself as a delegate to the tokeniser.  We implement the tokeniser delegate methods in such a way that whitespace tokens and comments, although consumed, will not appear in the tokeniser's output:

```objective-c
- (BOOL)tokeniser:(CPTokeniser *)tokeniser shouldConsumeToken:(CPToken *)token
{
    return YES;
}

- (void)tokeniser:(CPTokeniser *)tokeniser requestsToken:(CPToken *)token pushedOntoStream:(CPTokenStream *)stream
{
    if (![token isWhiteSpaceToken] && ![[token name] isEqualToString:@"Comment"])
    {
        [stream pushToken:token];
    }
}
```

We can now invoke our tokeniser.

```objective-c
CPTokenStream *tokenStream = [tokeniser tokenise:@"5 + (2.0 / 5.0 + 9) * 8"];
```

Parsing
-------

We construct parsers by specifying their grammar.  We can construct a grammar simply using a simple BNF like language.  Note the syntax tag@&lt;NonTerminal&gt; can be read simply as &lt;NonTerminal&gt;, the tag can be used later to quickly extract values from the parsed result:

```objective-c
NSString *expressionGrammar =
    @"Expression ::= term@<Term>   | expr@<Expression> op@<AddOp> term@<Term>;"
    @"Term       ::= fact@<Factor> | fact@<Factor>     op@<MulOp> term@<Term>;"
    @"Factor     ::= num@'Number' | '(' expr@<Expression> ')';"
    @"AddOp      ::= '+' | '-';"
    @"MulOp      ::= '*' | '/';";
NSError *err;
CPGrammar *grammar = [CPGrammar grammarWithStart:@"Expression" backusNaurForm:expressionGrammar error:&err];
if (nil == grammar)
{
    NSLog(@"Error creating grammar:");
    NSLog(@"%@", err);
}
else
{
    CPParser *parser = [CPLALR1Parser parserWithGrammar:grammar];
    [parser setDelegate:self];
    ...
}
```

When a rule is matched by the parser, the `initWithSyntaxTree:` method will be called on a new instance of the apropriate class.  If no such class exists the parser delegate's `parser:didProduceSyntaxTree:` method is called.  To deal with this cleanly, we implement 3 classes: Expression; Term; and Factor.  AddOp and MulOp non-terminals are dealt with by the parser delegate.  Here we see the initWithSyntaxTree: method for the Expression class, these methods are similar for Term and Factor:
    
```objective-c
- (id)initWithSyntaxTree:(CPSyntaxTree *)syntaxTree
{
    self = [self init];
    
    if (nil != self)
    {
        Term       *t = [syntaxTree valueForTag:@"term"];
        Expression *e = [syntaxTree valueForTag:@"expr"];
        
        if (nil == e)
        {
            [self setValue:[t value]];
        }
        else if ([[syntaxTree valueForTag:@"op"] isEqualToString:@"+"])
        {
            [self setValue:[e value] + [t value]];
        }
        else
        {
            [self setValue:[e value] - [t value]];
        }
    }
    
    return self;
}
```

We must also implement the delegate's method for dealing with AddOps and MulOps:

```objective-c
- (id)parser:(CPParser *)parser didProduceSyntaxTree:(CPSyntaxTree *)syntaxTree
{
    return [(CPKeywordToken *)[syntaxTree childAtIndex:0] keyword];
}
```

We can now parse the token stream we produced earlier:

```objective-c
NSLog(@"%f", [(Expression *)[parser parse:tokenStream] value]);
```

Which outputs:

    80.2

Best Practices
--------------

CoreParse offers three types of parser - SLR, LR(1) and LALR(1):
* SLR parsers cover the smallest set of languages, and are faster to generate than LALR(1) parsers.
* LR(1) parsers consume a lot of RAM, and are slow, but cover the largest set of languages.
* LALR(1) parsers are as fast as SLR parsers to run, but slower to generate, they cover almost as many languages as LR(1) parsers.

It is recommended that you start with an SLR parser (unless you know better), and when a parser cannot be generated for your grammar, move onto an LALR(1) parser.  LR(1) parsers are not really recommended at all, though may be useful in extreme circumstances.

It is recommended that if you have a significant grammar that requires an LALR(1) parser, you should use NSKeyedArchiving to archive the parser to a file.  You should then read this file, and unarchive it when your application runs to save generating the parser every time it runs, as parser generation can take some time.
