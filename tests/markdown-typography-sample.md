---
title: Front matter is removed, so this line should not appear
layout: sample
---

# Markdown typography sample (h1)

This file exercises the inline Markdown renderer used by `imgcat`. Run it with
`imgcat tests/markdown-typography-sample.md` and compare the result against what
a browser would show for the same source. It is deliberately long so that soft
wrapping, paragraph spacing, and vertical rhythm can be judged over several lines
of running text in the default terminal width.

## Headings (h2)

### Third level heading (h3)

#### Fourth level heading (h4)

##### Fifth level heading (h5)

###### Sixth level heading (h6)

Setext style heading
====================

Setext style subheading
-----------------------

## Inline styles

Plain, **bold**, *italic*, ***bold italic***, __bold with underscores__,
_italic with underscores_, ~~strikethrough~~, `inline code`, and a
[link to the iTerm2 site](https://iterm2.com). Autolink: <https://iterm2.com>
and a bare URL https://iterm2.com/documentation.html in prose.

Snake_case_identifiers like foo_bar_baz should not become italic, and
2 * 3 * 4 should not become emphasis either. A literal \*escaped asterisk\*,
a literal \`backtick\`, and a literal \# hash.

Smart punctuation: "double quotes", 'single quotes', an apostrophe in don't,
an ellipsis..., an en dash 1--2, and an em dash --- like this. Some
entities: &amp; &lt; &gt; &copy; &mdash; &nbsp;

Inline code with a very long token that will need to wrap somewhere:
`com.googlecode.iterm2.SomeVeryLongClassNameThatKeepsGoingAndGoingAndGoingUntilItRunsOutOfRoom`

A heading with **bold**, *italic*, and `code` inside:

## Heading with **bold**, *italic*, and `code`

## Paragraphs and line breaks

This is the first paragraph. It has two sentences. The second sentence is long
enough to wrap when the window is reasonably narrow, so that the leading and
the paragraph spacing can be evaluated.

This is the second paragraph. Between it and the previous one there should be
visible paragraph spacing, but not a full blank line of the body text size.
Line one of a hard break follows this sentence.  
Line two of the hard break (two trailing spaces above).
Line three of the hard break (backslash above).\
Line four, final.

## Lists

Unordered list:

- First item
- Second item with **bold** and `code`
- Third item that is long enough to wrap onto a second line so that the hanging
  indent of the continuation line can be checked against the bullet
    - Nested item one
    - Nested item two
        - Doubly nested item
- Fourth item

Alternate bullet markers:

* Star bullet
+ Plus bullet
- Dash bullet

Ordered list:

1. First step
2. Second step with a long description that wraps onto another line so the
   continuation indent can be evaluated against the number
3. Third step
    1. Nested numbered step
    2. Another nested numbered step
10. Tenth step (two digit number)

Ordered list starting at 5:

5. Five
6. Six
7. Seven

Task list:

- [x] Done item
- [ ] Not done item
- [ ] Another not done item

List item with multiple paragraphs:

1. First paragraph of the item.

   Second paragraph of the same item, indented three spaces.

2. Second item.

Blocks inside list items (the code and the quote line up with the item text):

1. Install it:

   ```shell
   make install
   ```

2. Read the note:

   > Restart after installing.

3. Done.

Four levels of nesting:

- Level one
  - Level two
    - Level three
      - Level four

A numbered list broken by a fence at the margin, as language models write it:

1. Clone the repository:
```shell
git clone https://example.com/repo.git
```
2. Build it.

## Blockquotes

> A single level blockquote that is long enough to wrap onto a second line in
> order to check the indent and the quote bar, if one is drawn.
>
> A second paragraph inside the same blockquote.
>
> > A nested blockquote inside the first one.
>
> Back to the first level with **bold** and `code`.

## Code

Fenced code block with a language:

```swift
struct Point {
    let x: Double
    let y: Double

    func distance(to other: Point) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
```

Fenced code block with no language and a very long line:

```
$ some-command --with-a-very-long-option-name=some-value --and-another-option=another-value --and-yet-another=value --until-it-overflows
```

Indented code block (four spaces):

    for i in range(10):
        print(i)

Tilde fence:

~~~
tilde fenced block
~~~

## Tables

| Left aligned | Center aligned | Right aligned | Default |
|:-------------|:--------------:|--------------:|---------|
| a            | b              | c             | d       |
| longer cell  | **bold**       | `code`        | [link](https://iterm2.com) |
| 1            | 22             | 333           | 4444    |

A table with no leading or trailing pipes:

Name | Value
---- | -----
foo  | 1
bar  | 2

## Horizontal rules

Above the rule.

---

Between the rules.

***

Below the rules.

___

## Images

Run imgcat from the repository root so these relative paths resolve.

Local images appear as placeholders. Click one to see the image.

A local image on its own line:

![A gradient with a circle and a box](tests/markdown-sample-image.png)

A local image inline ![small](tests/markdown-sample-image.png) in a sentence,
and a reference style local image ![reference image][local].

A remote image is never fetched, so it shows as a link:
![remote logo](https://iterm2.com/img/logo2x.jpg)

A missing local image explains why when clicked: ![missing picture](tests/no-such-file.png)

A reference style link [to the docs][docs].

[docs]: https://iterm2.com/documentation.html
[local]: tests/markdown-sample-image.png

## Footnotes and HTML

A sentence with a footnote.[^1] Inline <b>HTML bold</b>, <em>HTML emphasis</em>,
a <br> line break tag, and a <!-- comment -->comment.

[^1]: The footnote text.

<div align="center">A block level HTML div.</div>

## Mixed

1. Numbered item containing a list:
   - nested bullet
   - another nested bullet
2. Numbered item containing a code block:

   ```
   code inside a list item
   ```

3. Numbered item containing a quote:

   > quoted inside a list item

## Edge cases

Each case below once rendered wrongly. The text says what should happen.

This paragraph should stay one paragraph. The project was first released in
2020. It has since grown a lot.

1. A list item with two more paragraphs.

    This paragraph is indented four spaces and should not be code.

    Neither should this one.

    - A nested bullet after those paragraphs.

2. The next item, after a continuation paragraph.

   Its paragraph.
3. This item follows that paragraph directly and should still be item 3.

4. An item with real code indented past its text:

           indented code inside a list item

A YAML snippet with a two-space list should not change how the list after it
nests:

```yaml
steps:
  - name: build
```

- Top level, indented with four spaces below
    - Should be one level in, not two

### Indented code directly after a heading
    this should be a code block
    not a paragraph

An indented code block showing table syntax should stay code:

    a | b
    --|--

An indented code block showing a fence should keep its backtick lines:

    ```python
    print(1)
    ```

A longer fence containing a shorter one should show the inner fence as code:

````markdown
```swift
let x = 1
```
````

This paragraph should not be code.

A URL inside link text should not become a second link: [Visit https://iterm2.com today](https://iterm2.com).
A bare URL in parentheses should be a link without the parenthesis (https://iterm2.com).

HTML code should not be rewritten: <code>foo_bar</code>, <code>https://iterm2.com</code>,
<code>&lt;div&gt;</code>, and <code>a`b</code>. A double-backtick span: ``x`y``.

Nerd Font glyphs should survive (they look like boxes without a Nerd Font):  main,  , and in code ``.

| Option | Description |
|---|---|
| `--verbose` | Prints a great deal of extra information about every step the program takes, which is useful when working out why something went wrong. The short columns should not break mid-word. |
| `-q` | Quiet. |

## Code at the margin in list items

Models often indent a fence under a list item but put the code, or the closing
fence, at the left margin. The code should stay with its item, and item 2 should
follow it:

1. Install it:
   ```bash
npm ci
# then build (a shell comment, not a heading)
- old line, as in a diff
npm run build
```
2. Run it.

Indentation inside such code should keep its shape:

1. Define it:
   ```python
def f():
    if x:
        pass
   ```
2. Call it.

A fence that is never closed ends with its item, so the next item should be
item 2 and its code should be its own:

1. First:
   ```bash
   cmd1
2. Second:
   ```bash
   cmd2
   ```

Prose at the margin after a blank line ends the item, as on GitHub. The
sentence below should be ordinary text and the Python block should be code:

- step
  ```
  code

This sentence should not be code.

```python
print(1)
```

## Nesting

A quote inside a list item should line up with the item's text, and a quote
after the list should be separate and at the margin:

- An item

  > A quote in the item.

> A quote after the list.

Everything inside a quote should be dimmed, including its list and heading:

> Quoted text.
>
> - A quoted list item
>
> #### A quoted heading

A table in a quote should keep the quote bar through it and after it:

> Before the table.
>
> | a | b |
> |---|---|
> | 1 | 2 |
>
> After the table.

A table and a rule in a list item should line up with the item's text:

1. An item with a table:

   | a | b |
   |---|---|
   | 1 | 2 |

2. An item with a rule:

   ***

A list nested under a wide marker should be nested:

10.   Ten
    - Nested under ten

Ordered task items should keep their numbers:

1. [x] Done
2. [ ] Not done

## Blocks next to each other

Two code blocks with no blank line between them should be separate boxes:

```sh
ls
```
```python
print(1)
```

Two code blocks separated by a blank line should have a clear gap:

```sh
ls
```

```sh
pwd
```

A table right after a code block should have the same gap:

```sh
ls
```

| a |
|---|
| 1 |

An empty code block should still show as a box:

```
```

## Inline and HTML details

Back-to-back footnote definitions should each be their own line.[^2][^3]

[^2]: The second note.
[^3]: The third note.

A trailing break tag should not add an empty line under this sentence.<br>

<details>
<summary>This summary should not start with a space</summary>
</details>

A reference link whose label has an underscore should work: [the docs][api_ref].

[api_ref]: https://iterm2.com/

A definition directly under a paragraph line shows as text, as on GitHub:
[not_a_definition]: https://iterm2.com/

Three tildes used to hang the renderer: this is ~~~very~~~ odd.

Final paragraph after everything, to check bottom spacing.
