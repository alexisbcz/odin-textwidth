package textwidth

import "base:runtime"
import "core:strings"

/*
truncate shortens `s` so that it takes at most `max_width` columns.

When `s` already fits, truncate returns an unchanged copy. Otherwise it keeps
as many whole graphemes as fit in `max_width` minus the width of `tail`, then
appends `tail`. It never splits a grapheme or an escape sequence, so the result
can be narrower than `max_width` when a two-column character does not fit in
the last column. When `tail` alone is wider than `max_width`, truncate drops it.

Escape sequences before the cut stay in place. When the kept text ends inside
an OSC 8 hyperlink, truncate closes the link after `tail`. When it ends with a
color or style still active, truncate then appends RESET. Neither leaks into
whatever the terminal prints next.

Inputs:
- s: the text to shorten; it may contain ANSI escape sequences.
- max_width: the column budget; zero or less gives an empty string.
- tail: the marker for removed text, "…" by default; pass "" for none.
- allocator: allocates the result.

Returns:
- res: a new string owned by the caller; free it with `delete(res, allocator)`.
- err: an allocator error, if any.

Example:
	s := textwidth.truncate("日本語のテキスト", 7) // "日本語…"
	defer delete(s)
*/
truncate :: proc(
	s: string,
	max_width: int,
	tail := "…",
	allocator := context.allocator,
) -> (
	res: string,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	if width(s) <= max_width {
		return strings.clone(s, allocator)
	}
	if max_width <= 0 {
		return "", nil
	}
	tail := tail
	tail_width := width(tail)
	if tail_width > max_width {
		tail, tail_width = "", 0
	}
	budget := max_width - tail_width

	buf := make([dynamic]u8, 0, len(s) + len(tail) + len(RESET), allocator) or_return
	defer if err != nil {
		delete(buf)
	}
	used := 0
	styled := false
	linked := false
	rest := s
	for len(rest) > 0 {
		tok := next_token(rest)
		if tok.kind == .Escape {
			if is_sgr(tok.text) {
				styled = !is_sgr_reset(tok.text)
			} else if uri, ok := hyperlink_uri(tok.text); ok {
				linked = uri != ""
			}
		} else if used + tok.width > budget {
			break
		}
		append(&buf, tok.text) or_return
		used += tok.width
		rest = rest[len(tok.text):]
	}
	append(&buf, tail) or_return
	if linked {
		append(&buf, HYPERLINK_END) or_return
	}
	if styled {
		append(&buf, RESET) or_return
	}
	shrink(&buf) or_return
	return string(buf[:]), nil
}

// HYPERLINK_END is the OSC 8 sequence that closes a hyperlink.
@(private = "file")
HYPERLINK_END :: "\x1b]8;;\x1b\\"

/*
hyperlink_uri returns the URI of the OSC 8 escape `seq`, and whether `seq` is
an OSC 8 sequence at all. An empty URI closes the current hyperlink.
*/
@(private = "file")
hyperlink_uri :: proc(seq: string) -> (uri: string, ok: bool) {
	body := strings.trim_prefix(seq, "\x1b]8;")
	if len(body) == len(seq) {
		return "", false
	}
	if strings.has_suffix(body, "\x1b\\") {
		body = body[:len(body) - 2]
	} else if strings.has_suffix(body, "\x07") {
		body = body[:len(body) - 1]
	}
	// The parameters come first and end at the first semicolon.
	semi := strings.index_byte(body, ';')
	if semi < 0 {
		return "", true
	}
	return body[semi + 1:], true
}

/*
pad_right appends spaces to `s` until it takes `w` columns. Text that already
takes `w` columns or more comes back unchanged. Use it to left-align a cell.

Returns a new string owned by the caller; free it with `delete(res, allocator)`.
*/
pad_right :: proc(s: string, w: int, allocator := context.allocator) -> (res: string, err: runtime.Allocator_Error) #optional_allocator_error {
	missing := max(w - width(s), 0)
	return pad(s, 0, missing, allocator)
}

/*
pad_left prepends spaces to `s` until it takes `w` columns. Text that already
takes `w` columns or more comes back unchanged. Use it to right-align a cell.

Returns a new string owned by the caller; free it with `delete(res, allocator)`.
*/
pad_left :: proc(s: string, w: int, allocator := context.allocator) -> (res: string, err: runtime.Allocator_Error) #optional_allocator_error {
	missing := max(w - width(s), 0)
	return pad(s, missing, 0, allocator)
}

/*
center surrounds `s` with spaces until it takes `w` columns. When the padding
is odd, the extra space goes on the right. Text that already takes `w` columns
or more comes back unchanged.

Returns a new string owned by the caller; free it with `delete(res, allocator)`.
*/
center :: proc(s: string, w: int, allocator := context.allocator) -> (res: string, err: runtime.Allocator_Error) #optional_allocator_error {
	missing := max(w - width(s), 0)
	return pad(s, missing / 2, missing - missing / 2, allocator)
}

@(private = "file")
pad :: proc(s: string, left, right: int, allocator: runtime.Allocator) -> (res: string, err: runtime.Allocator_Error) {
	buf := make([]u8, left + len(s) + right, allocator) or_return
	for i in 0 ..< left {
		buf[i] = ' '
	}
	copy(buf[left:], s)
	for i in left + len(s) ..< len(buf) {
		buf[i] = ' '
	}
	return string(buf), nil
}

/*
Wrap_Options adjusts how wrap lays out lines. The zero value wraps without
indentation and keeps trailing whitespace.
*/
Wrap_Options :: struct {
	// indent starts the first line of every paragraph, for example "  " or "- ".
	indent:              string,
	// hanging_indent starts every line that wrap creates inside a paragraph.
	hanging_indent:      string,
	// trim_trailing_space removes spaces and tabs from the end of every line.
	trim_trailing_space: bool,
}

/*
wrap breaks `s` into lines that take at most `max_width` columns.

wrap is greedy: it puts as many words on a line as fit, and breaks at spaces
and tabs. The whitespace at a break disappears. A word longer than a whole line
continues on the next line, cut between graphemes. Existing newlines stay: each
one ends a paragraph, and an empty paragraph gives an empty line. A trailing
carriage return before a newline is dropped.

wrap never cuts inside an escape sequence or a grapheme. When a single
grapheme is wider than the line, for example a CJK character at width 1, it
gets a line of its own and that line overflows. A tab counts as one column;
expand tabs first if you need tab stops. A `max_width` below 1 counts as 1.

Inputs:
- s: the text to wrap; it may contain ANSI escape sequences and newlines.
- max_width: the line width in columns, including any indent.
- options: indentation and trimming; see Wrap_Options.
- allocator: allocates the slice and every line.

Returns:
- lines: owned by the caller; free them with `wrap_destroy(lines, allocator)`.
- err: an allocator error, if any. On error wrap frees what it allocated.

Example:
	lines := textwidth.wrap("the quick brown fox", 10)
	defer textwidth.wrap_destroy(lines)
	// lines == {"the quick", "brown fox"}
*/
wrap :: proc(
	s: string,
	max_width: int,
	options := Wrap_Options{},
	allocator := context.allocator,
) -> (
	lines: []string,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	wr := Wrapper {
		max_width    = max(max_width, 1),
		options      = options,
		allocator    = allocator,
		indent_width = width(options.indent),
		hang_width   = width(options.hanging_indent),
	}
	wr.lines = make([dynamic]string, allocator) or_return
	defer if err != nil {
		for line in wr.lines {
			delete(line, allocator)
		}
		delete(wr.lines)
	}
	wr.buf = make([dynamic]u8, allocator) or_return
	defer delete(wr.buf)

	rest := s
	for {
		nl := strings.index_byte(rest, '\n')
		para := rest if nl < 0 else rest[:nl]
		wrap_paragraph(&wr, strings.trim_suffix(para, "\r")) or_return
		if nl < 0 {
			break
		}
		rest = rest[nl + 1:]
	}
	shrink(&wr.lines) or_return
	return wr.lines[:], nil
}

/*
wrap_destroy frees the lines that wrap returned, and the slice that holds them.
Pass the same allocator that wrap used.
*/
wrap_destroy :: proc(lines: []string, allocator := context.allocator) {
	for line in lines {
		delete(line, allocator)
	}
	delete(lines, allocator)
}

@(private = "file")
Wrapper :: struct {
	lines:        [dynamic]string,
	buf:          [dynamic]u8,
	// Columns used by buf.
	line_width:   int,
	// Whether buf holds any visible text beyond the indent.
	has_content:  bool,
	max_width:    int,
	indent_width: int,
	hang_width:   int,
	options:      Wrap_Options,
	allocator:    runtime.Allocator,
}

@(private = "file")
is_break_space :: proc "contextless" (tok: Token) -> bool {
	return tok.kind == .Grapheme && (tok.text == " " || tok.text == "\t")
}

@(private = "file")
start_line :: proc(wr: ^Wrapper, first: bool) -> runtime.Allocator_Error {
	prefix := wr.options.indent if first else wr.options.hanging_indent
	append(&wr.buf, prefix) or_return
	wr.line_width = wr.indent_width if first else wr.hang_width
	wr.has_content = false
	return nil
}

@(private = "file")
flush_line :: proc(wr: ^Wrapper) -> runtime.Allocator_Error {
	line := string(wr.buf[:])
	if wr.options.trim_trailing_space {
		line = strings.trim_right(line, " \t")
	}
	owned := strings.clone(line, wr.allocator) or_return
	if _, err := append(&wr.lines, owned); err != nil {
		delete(owned, wr.allocator)
		return err
	}
	clear(&wr.buf)
	wr.line_width = 0
	wr.has_content = false
	return nil
}

@(private = "file")
push :: proc(wr: ^Wrapper, text: string, columns: int) -> runtime.Allocator_Error {
	append(&wr.buf, text) or_return
	wr.line_width += columns
	if columns > 0 {
		wr.has_content = true
	}
	return nil
}

// first_width returns the width of the first visible grapheme of `word`.
@(private = "file")
first_width :: proc "contextless" (word: string) -> int {
	rest := word
	for len(rest) > 0 {
		tok := next_token(rest)
		if tok.width > 0 {
			return tok.width
		}
		rest = rest[len(tok.text):]
	}
	return 0
}

@(private = "file")
wrap_paragraph :: proc(wr: ^Wrapper, para: string) -> runtime.Allocator_Error {
	if len(para) == 0 {
		return flush_line(wr)
	}
	start_line(wr, true) or_return
	first_line := true
	space, word: string
	space_width, word_width: int

	rest := para
	for len(rest) > 0 {
		// Read one run of spaces, then one word.
		space, space_width = "", 0
		start := rest
		for len(rest) > 0 {
			tok := next_token(rest)
			if !is_break_space(tok) {
				break
			}
			space_width += 1
			rest = rest[len(tok.text):]
		}
		space = start[:len(start) - len(rest)]

		word_width = 0
		start = rest
		for len(rest) > 0 {
			tok := next_token(rest)
			if is_break_space(tok) {
				break
			}
			word_width += tok.width
			rest = rest[len(tok.text):]
		}
		word = start[:len(start) - len(rest)]

		if len(word) == 0 {
			// Whitespace at the end of the paragraph.
			if wr.line_width + space_width <= wr.max_width {
				push(wr, space, space_width) or_return
			}
			break
		}
		place_word(wr, space, space_width, word, word_width, &first_line) or_return
	}
	return flush_line(wr)
}

@(private = "file")
place_word :: proc(
	wr: ^Wrapper,
	space: string,
	space_width: int,
	word: string,
	word_width: int,
	first_line: ^bool,
) -> runtime.Allocator_Error {
	if !wr.has_content {
		// Leading whitespace survives only on the first line of a paragraph,
		// where it is the author's own indentation.
		if first_line^ && wr.line_width + space_width + word_width <= wr.max_width {
			push(wr, space, space_width) or_return
		}
		if wr.line_width + word_width <= wr.max_width {
			return push(wr, word, word_width)
		}
		return hard_break(wr, word, first_line)
	}

	if wr.line_width + space_width + word_width <= wr.max_width {
		push(wr, space, space_width) or_return
		return push(wr, word, word_width)
	}
	if word_width <= wr.max_width - wr.hang_width {
		new_line(wr, first_line) or_return
		return push(wr, word, word_width)
	}
	// The word is longer than any line: start it here when its first
	// grapheme fits after the space, otherwise on a fresh line.
	if wr.line_width + space_width + first_width(word) <= wr.max_width {
		push(wr, space, space_width) or_return
	} else {
		new_line(wr, first_line) or_return
	}
	return hard_break(wr, word, first_line)
}

@(private = "file")
new_line :: proc(wr: ^Wrapper, first_line: ^bool) -> runtime.Allocator_Error {
	flush_line(wr) or_return
	first_line^ = false
	return start_line(wr, false)
}

// hard_break places `word` grapheme by grapheme, starting new lines as needed.
@(private = "file")
hard_break :: proc(wr: ^Wrapper, word: string, first_line: ^bool) -> runtime.Allocator_Error {
	rest := word
	for len(rest) > 0 {
		tok := next_token(rest)
		if tok.width > 0 && wr.has_content && wr.line_width + tok.width > wr.max_width {
			new_line(wr, first_line) or_return
		}
		push(wr, tok.text, tok.width) or_return
		rest = rest[len(tok.text):]
	}
	return nil
}
