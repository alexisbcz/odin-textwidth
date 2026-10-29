# textwidth

[![CI](https://github.com/alexisbcz/odin-textwidth/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisbcz/odin-textwidth/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09-1e5a99.svg)](https://odin-lang.org)

Measure how many terminal columns text takes, then truncate, pad and wrap it by that width, with correct results for CJK, emoji, combining marks and ANSI colors.

Odin's `core:unicode/utf8` counts runes and `core:text/table` lays out cells, but neither knows that `日` takes two columns, that `é` written as `e` plus a combining accent takes one, or that `\x1b[31m` takes none. This package does, using tables generated from the Unicode Character Database 16.0.0.

## Install

The repository root is the package, so you can vendor it in two ways.

As a Git submodule inside your project:

```sh
git submodule add https://github.com/alexisbcz/odin-textwidth libs/textwidth
```

```odin
import "libs/textwidth"
```

As a copy in a shared collection that all your projects use:

```sh
git clone https://github.com/alexisbcz/odin-textwidth ~/odin-shared/textwidth
odin build . -collection:shared=$HOME/odin-shared
```

```odin
import "shared:textwidth"
```

## Quick start

```odin
package main

import "core:fmt"
import "shared:textwidth"

main :: proc() {
	fmt.println(textwidth.width("日本語"))             // 6
	fmt.println(textwidth.width("👩🏽‍💻"))              // 2
	fmt.println(textwidth.width("\x1b[1mbold\x1b[0m")) // 4

	name := textwidth.pad_right("山田太郎", 10)
	defer delete(name)
	fmt.printf("| %s |\n", name) // | 山田太郎   |

	short := textwidth.truncate("\x1b[31mhello world\x1b[0m", 5)
	defer delete(short)
	fmt.println(short) // "hell…" in red, followed by a reset

	lines := textwidth.wrap("the quick brown fox jumps", 10, {hanging_indent = "  "})
	defer textwidth.wrap_destroy(lines)
	for line in lines {
		fmt.println(line) // "the quick", "  brown", "  fox", "  jumps"
	}
}
```

## API overview

| Declaration | Purpose | Allocates | Free with |
| --- | --- | --- | --- |
| `rune_width(r)` | Columns for one code point: 0, 1 or 2 | No | Not needed |
| `width(s)` | Columns for a string, by grapheme, skipping escape sequences | No | Not needed |
| `truncate(s, max_width, tail, allocator)` | Cut to `max_width` columns and append `tail`, "…" by default | Yes | `delete` |
| `pad_right(s, w, allocator)` | Append spaces up to `w` columns | Yes | `delete` |
| `pad_left(s, w, allocator)` | Prepend spaces up to `w` columns | Yes | `delete` |
| `center(s, w, allocator)` | Pad both sides up to `w` columns | Yes | `delete` |
| `wrap(s, max_width, options, allocator)` | Greedy word wrap into lines | Yes | `wrap_destroy` |
| `Wrap_Options` | Indent, hanging indent and trailing-space trim for `wrap` | No | Not needed |
| `RESET`, `ESC`, `UNICODE_VERSION` | The SGR reset sequence, the escape byte and the table version | No | Not needed |

Every allocating procedure returns `(result, runtime.Allocator_Error)` with `#optional_allocator_error`, so you can ignore the error or check it.

## How width works

- East Asian Wide and Fullwidth characters, such as CJK ideographs, kana, Hangul and most emoji, take two columns. Ambiguous characters take one.
- Combining marks, format characters such as the zero width joiner, variation selectors and Hangul medial jamo take zero.
- Control characters take zero, including tab and newline. Invalid UTF-8 bytes take one each, because terminals draw them as U+FFFD.
- `width` groups code points into graphemes first. A ZWJ sequence such as 👨‍👩‍👧‍👦 is one two-column grapheme, a skin-tone modifier joins the emoji before it, two regional indicators form one flag, U+FE0F makes an emoji two columns wide and U+FE0E makes it one.
- CSI sequences (colors, cursor movement), OSC sequences (titles, hyperlinks) and other ANSI escapes take zero columns. A malformed sequence ends before the first byte that can't belong to it.

## Wrapping

`wrap` puts as many words on a line as fit and drops the whitespace where it breaks. It breaks on spaces, tabs and Unicode spaces such as U+3000 IDEOGRAPHIC SPACE, but not on no-break spaces. A word longer than a line continues on the next one, cut between graphemes, which also wraps CJK text that has no spaces. Each newline in the input ends a paragraph, so blank lines stay blank. A grapheme wider than the whole line, such as `日` at width 1, gets a line of its own.

```odin
opts := textwidth.Wrap_Options {
	indent              = "- ",
	hanging_indent      = "  ",
	trim_trailing_space = true,
}
lines := textwidth.wrap("first item wraps here\nsecond", 12, opts)
defer textwidth.wrap_destroy(lines)
// {"- first item", "  wraps here", "- second"}
```

## Examples

Each directory under `examples/` is a runnable program:

```sh
odin run examples/basic
```

## Design notes

- Measuring never allocates. Layout procedures take `allocator := context.allocator`, and on failure they free what they allocated before returning the error.
- The package keeps no global mutable state, so every procedure is safe to call from several threads at once.
- Grapheme grouping covers what terminals draw as one cell. It isn't a full Unicode text segmentation: spacing marks in Indic scripts count as their own column, as they do in `wcwidth`.
- To update the tables to a newer Unicode release, download the files listed in `tools/gentables/main.odin` and run `odin run tools/gentables -- <ucd-dir> <version> > tables.odin`.

## Testing

```sh
odin check . -vet -strict-style -disallow-do -no-entry-point
odin test tests -vet -strict-style -disallow-do
vale sync && vale *.md
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow Conventional Commits, and every change that users can see gets a line in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
