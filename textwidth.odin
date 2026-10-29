/*
Package textwidth measures how many terminal columns text takes and lays it out
by that width.

A terminal draws most characters in one column, East Asian wide characters
and emoji in two, and combining marks in none. This package knows those rules
from tables generated out of the Unicode Character Database (see
UNICODE_VERSION), groups code points into graphemes the way a terminal draws
them, and skips ANSI escape sequences so that colored text measures the same
as plain text.

Measuring never allocates. Layout procedures (truncate, pad_right, pad_left,
center and wrap) take an allocator and return memory that the caller owns.

Example:
	import "core:fmt"
	import "shared:textwidth"

	main :: proc() {
		fmt.println(textwidth.width("日本語"))           // 6
		fmt.println(textwidth.width("\x1b[31mred\x1b[0m")) // 3

		cell := textwidth.pad_right("名前", 8)
		defer delete(cell)
		fmt.printf("[%s]\n", cell) // [名前    ]
	}

All procedures are safe to call from several threads at once: the package keeps
no mutable state.
*/
package textwidth

import "core:unicode/utf8"

// ESC is the byte that starts every ANSI escape sequence.
ESC :: '\x1b'

// RESET is the SGR sequence that turns off every color and text attribute.
// truncate appends it when it cuts text that is still styled.
RESET :: "\x1b[0m"

@(private)
ZWJ :: '‍'
@(private)
VS15 :: '︎'
@(private)
VS16 :: '️'

@(private)
Range :: struct {
	lo, hi: rune,
}

@(private)
in_table :: proc "contextless" (r: rune, table: []Range) -> bool {
	lo, hi := 0, len(table)
	for lo < hi {
		mid := int(uint(lo + hi) >> 1)
		switch {
		case r < table[mid].lo:
			hi = mid
		case r > table[mid].hi:
			lo = mid + 1
		case:
			return true
		}
	}
	return false
}

@(private)
is_control :: #force_inline proc "contextless" (r: rune) -> bool {
	return r < 0x20 || (r >= 0x7F && r < 0xA0)
}

@(private)
is_regional_indicator :: #force_inline proc "contextless" (r: rune) -> bool {
	return r >= 0x1F1E6 && r <= 0x1F1FF
}

@(private)
is_emoji_modifier :: #force_inline proc "contextless" (r: rune) -> bool {
	return r >= 0x1F3FB && r <= 0x1F3FF
}

/*
rune_width returns how many terminal columns the code point `r` takes on its
own: 0, 1 or 2.

- 0 for control characters (including tab and newline), nonspacing and
  enclosing combining marks, format characters such as U+200D ZERO WIDTH
  JOINER, variation selectors and Hangul medial and final jamo.
- 2 for code points whose East_Asian_Width is Wide or Fullwidth: CJK
  ideographs, kana, Hangul syllables, fullwidth forms and most emoji.
- 1 for everything else, including East_Asian_Width Ambiguous characters,
  unassigned code points, and values that are not Unicode scalar values,
  which terminals draw as U+FFFD.

rune_width looks at one code point only. Use width for strings: it groups
emoji sequences and combining marks into graphemes first.
*/
rune_width :: proc "contextless" (r: rune) -> int {
	switch {
	case r >= 0x20 && r < 0x7F:
		return 1
	case r < 0 || r > utf8.MAX_RUNE || (r >= 0xD800 && r <= 0xDFFF):
		return 1
	case is_control(r):
		return 0
	case in_table(r, zero_width_table[:]):
		return 0
	case in_table(r, wide_table[:]):
		return 2
	}
	return 1
}

/*
width returns how many terminal columns `s` takes when printed on one line.

width walks `s` grapheme by grapheme. A grapheme takes the width of its first
code point, with these refinements:

- Combining marks, variation selectors and emoji skin-tone modifiers add no
  width to the character they follow.
- A ZWJ emoji sequence, such as a family or a profession emoji, counts as one
  two-column grapheme.
- U+FE0F (emoji presentation) makes an emoji two columns wide, and U+FE0E
  (text presentation) makes it one.
- Two regional indicators form one two-column flag.

ANSI escape sequences (CSI, such as colors, and OSC, such as hyperlinks)
take no columns. Control characters, including newline and tab, take none
either. Invalid UTF-8 bytes take one column each.
*/
width :: proc "contextless" (s: string) -> (columns: int) {
	rest := s
	for len(rest) > 0 {
		tok := next_token(rest)
		columns += tok.width
		rest = rest[len(tok.text):]
	}
	return
}

@(private)
Token_Kind :: enum u8 {
	Grapheme,
	Escape,
}

// A Token is one grapheme or one escape sequence.
@(private)
Token :: struct {
	text:  string,
	width: int,
	kind:  Token_Kind,
}

// next_token splits the first grapheme or escape sequence off a non-empty `s`.
@(private)
next_token :: proc "contextless" (s: string) -> Token {
	c := s[0]
	if c == ESC {
		return Token{s[:escape_len(s)], 0, .Escape}
	}
	// Fast path: an ASCII byte followed by another ASCII byte, or by nothing,
	// is a grapheme on its own.
	if c < 0x80 && (len(s) == 1 || s[1] < 0x80) {
		return Token{s[:1], 1 if c >= 0x20 && c < 0x7F else 0, .Grapheme}
	}

	r, n := utf8.decode_rune_in_string(s)
	if r == utf8.RUNE_ERROR && n <= 1 {
		// An invalid byte: the terminal draws U+FFFD in one column.
		return Token{s[:max(n, 1)], 1, .Grapheme}
	}
	w := rune_width(r)
	if is_control(r) {
		return Token{s[:n], w, .Grapheme}
	}

	emoji := in_table(r, emoji_table[:])
	pictographic := in_table(r, pictographic_table[:])
	regional := 1 if is_regional_indicator(r) else 0

	i := n
	extend: for i < len(s) {
		next, m := utf8.decode_rune_in_string(s[i:])
		switch {
		case next == utf8.RUNE_ERROR && m <= 1:
			break extend
		case next == ZWJ:
			i += m
			// A ZWJ between two pictographs joins them into one grapheme.
			if pictographic && i < len(s) {
				joined, k := utf8.decode_rune_in_string(s[i:])
				if in_table(joined, pictographic_table[:]) {
					i += k
				}
			}
		case next == VS16:
			if emoji {
				w = 2
			}
			i += m
		case next == VS15:
			if emoji {
				w = 1
			}
			i += m
		case is_emoji_modifier(next):
			if !pictographic {
				break extend
			}
			i += m
		case is_regional_indicator(next):
			if regional != 1 {
				break extend
			}
			regional += 1
			w = 2
			i += m
		case is_control(next):
			break extend
		case in_table(next, zero_width_table[:]):
			i += m
		case:
			break extend
		}
	}
	return Token{s[:i], w, .Grapheme}
}

/*
escape_len returns the byte length of the escape sequence at the start of `s`,
where `s[0] == ESC`. A truncated or malformed sequence ends right before the
first byte that cannot belong to it, so the result never splits a UTF-8
character.
*/
@(private)
escape_len :: proc "contextless" (s: string) -> int {
	if len(s) < 2 {
		return len(s)
	}
	switch s[1] {
	case '[':
		// CSI: parameter and intermediate bytes, then one final byte.
		for i in 2 ..< len(s) {
			switch s[i] {
			case 0x40 ..= 0x7E:
				return i + 1
			case 0x20 ..= 0x3F:
				continue
			case:
				return i
			}
		}
		return len(s)
	case ']', 'P', 'X', '^', '_':
		// OSC, DCS, SOS, PM and APC: a string ended by BEL or by ST (ESC \).
		for i in 2 ..< len(s) {
			switch s[i] {
			case 0x07:
				return i + 1
			case ESC:
				if i + 1 < len(s) && s[i + 1] == '\\' {
					return i + 2
				}
				return i
			}
		}
		return len(s)
	}
	// Any other sequence: intermediate bytes, then one final byte.
	i := 1
	for i < len(s) && s[i] >= 0x20 && s[i] <= 0x2F {
		i += 1
	}
	if i < len(s) && s[i] >= 0x30 && s[i] <= 0x7E {
		return i + 1
	}
	return i
}

// is_sgr reports whether the escape `seq` is a Select Graphic Rendition (color or style) sequence.
@(private)
is_sgr :: proc "contextless" (seq: string) -> bool {
	return len(seq) >= 3 && seq[1] == '[' && seq[len(seq) - 1] == 'm'
}

// is_sgr_reset reports whether the SGR sequence `seq` resets every attribute.
@(private)
is_sgr_reset :: proc "contextless" (seq: string) -> bool {
	params := seq[2:len(seq) - 1]
	for c in transmute([]u8)params {
		if c != '0' {
			return false
		}
	}
	return true
}
