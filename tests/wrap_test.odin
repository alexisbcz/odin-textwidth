package textwidth_tests

import textwidth ".."
import "core:strings"
import "core:testing"

SAMPLE :: #load("testdata/sample.txt", string)
GOLDEN_1 :: #load("testdata/wrap_1.golden", string)
GOLDEN_10 :: #load("testdata/wrap_10.golden", string)
GOLDEN_80 :: #load("testdata/wrap_80.golden", string)

// expect_lines wraps `s` and compares the result with `want` line by line.
expect_lines :: proc(
	t: ^testing.T,
	s: string,
	max_width: int,
	want: []string,
	options := textwidth.Wrap_Options{},
	loc := #caller_location,
) {
	lines := textwidth.wrap(s, max_width, options)
	defer textwidth.wrap_destroy(lines)
	if !testing.expectf(t, len(lines) == len(want), "got %d lines %q, want %d lines %q", len(lines), lines, len(want), want, loc = loc) {
		return
	}
	for line, i in lines {
		testing.expectf(t, line == want[i], "line %d: got %q, want %q", i, line, want[i], loc = loc)
	}
}

// expect_golden wraps SAMPLE and compares the lines, joined by newlines, with `golden`.
expect_golden :: proc(t: ^testing.T, max_width: int, golden: string, loc := #caller_location) {
	lines := textwidth.wrap(SAMPLE, max_width)
	defer textwidth.wrap_destroy(lines)
	got := strings.join(lines, "\n")
	defer delete(got)
	testing.expectf(t, got == golden, "wrap at %d differs from golden:\n%s", max_width, got, loc = loc)
}

@(test)
test_wrap_golden_width_1 :: proc(t: ^testing.T) {
	expect_golden(t, 1, GOLDEN_1)
}

@(test)
test_wrap_golden_width_10 :: proc(t: ^testing.T) {
	expect_golden(t, 10, GOLDEN_10)
}

@(test)
test_wrap_golden_width_80 :: proc(t: ^testing.T) {
	expect_golden(t, 80, GOLDEN_80)
}

@(test)
test_wrap_lines_never_exceed_width :: proc(t: ^testing.T) {
	for w in ([]int{2, 3, 7, 10, 25, 80}) {
		lines := textwidth.wrap(SAMPLE, w)
		defer textwidth.wrap_destroy(lines)
		for line in lines {
			testing.expectf(t, textwidth.width(line) <= w, "width %d: line %q takes %d columns", w, line, textwidth.width(line))
		}
	}
}

@(test)
test_wrap_greedy_words :: proc(t: ^testing.T) {
	expect_lines(t, "the quick brown fox", 10, {"the quick", "brown fox"})
	expect_lines(t, "a b c d e f", 3, {"a b", "c d", "e f"})
}

@(test)
test_wrap_empty_string_is_one_empty_line :: proc(t: ^testing.T) {
	expect_lines(t, "", 10, {""})
}

@(test)
test_wrap_keeps_existing_newlines :: proc(t: ^testing.T) {
	expect_lines(t, "one\n\ntwo", 10, {"one", "", "two"})
	expect_lines(t, "end\n", 10, {"end", ""})
	expect_lines(t, "windows\r\nline", 10, {"windows", "line"})
}

@(test)
test_wrap_collapses_whitespace_at_breaks :: proc(t: ^testing.T) {
	expect_lines(t, "aaaa    bbbb", 6, {"aaaa", "bbbb"})
	expect_lines(t, "aaaa\t\tbbbb", 6, {"aaaa", "bbbb"})
}

@(test)
test_wrap_keeps_inner_spacing_that_fits :: proc(t: ^testing.T) {
	expect_lines(t, "a  b", 10, {"a  b"})
}

@(test)
test_wrap_hard_breaks_long_word :: proc(t: ^testing.T) {
	expect_lines(t, "abcdefghij", 4, {"abcd", "efgh", "ij"})
}

@(test)
test_wrap_long_word_fills_current_line_first :: proc(t: ^testing.T) {
	expect_lines(t, "ab abcdefghij", 5, {"ab ab", "cdefg", "hij"})
}

@(test)
test_wrap_cjk_without_spaces :: proc(t: ^testing.T) {
	expect_lines(t, "日本語のテキスト", 5, {"日本", "語の", "テキ", "スト"})
	expect_lines(t, "日本語のテキスト", 6, {"日本語", "のテキ", "スト"})
}

@(test)
test_wrap_never_cuts_escape_sequences :: proc(t: ^testing.T) {
	expect_lines(t, "\x1b[31mabcdef\x1b[0m", 3, {"\x1b[31mabc", "def\x1b[0m"})
	expect_lines(t, "\x1b[1mbold\x1b[0m text", 4, {"\x1b[1mbold\x1b[0m", "text"})
}

@(test)
test_wrap_never_cuts_graphemes :: proc(t: ^testing.T) {
	expect_lines(t, "👨‍👩‍👧‍👦👍🏽é", 2, {"👨‍👩‍👧‍👦", "👍🏽", "é"})
	expect_lines(t, "🇫🇷🇯🇵", 3, {"🇫🇷", "🇯🇵"})
}

@(test)
test_wrap_wide_grapheme_wider_than_line_overflows :: proc(t: ^testing.T) {
	expect_lines(t, "日本", 1, {"日", "本"})
}

@(test)
test_wrap_width_below_one_counts_as_one :: proc(t: ^testing.T) {
	expect_lines(t, "ab", 0, {"a", "b"})
	expect_lines(t, "ab", -5, {"a", "b"})
}

@(test)
test_wrap_preserves_leading_indentation :: proc(t: ^testing.T) {
	expect_lines(t, "  code here", 7, {"  code", "here"})
}

@(test)
test_wrap_indent_and_hanging_indent :: proc(t: ^testing.T) {
	opts := textwidth.Wrap_Options {
		indent         = "- ",
		hanging_indent = "  ",
	}
	expect_lines(t, "first item wraps here\nsecond", 12, {"- first item", "  wraps here", "- second"}, opts)
}

@(test)
test_wrap_hanging_indent_with_long_word :: proc(t: ^testing.T) {
	opts := textwidth.Wrap_Options {
		hanging_indent = "> ",
	}
	expect_lines(t, "abcdefgh", 4, {"abcd", "> ef", "> gh"}, opts)
}

@(test)
test_wrap_indent_wider_than_line_still_progresses :: proc(t: ^testing.T) {
	opts := textwidth.Wrap_Options {
		hanging_indent = "    ",
	}
	expect_lines(t, "abc", 2, {"ab", "    c"}, opts)
}

@(test)
test_wrap_empty_paragraph_gets_no_indent :: proc(t: ^testing.T) {
	opts := textwidth.Wrap_Options {
		indent = "  ",
	}
	expect_lines(t, "a\n\nb", 10, {"  a", "", "  b"}, opts)
}

@(test)
test_wrap_keeps_trailing_space_by_default :: proc(t: ^testing.T) {
	expect_lines(t, "hello   ", 10, {"hello   "})
	expect_lines(t, "  ", 10, {"  "})
}

@(test)
test_wrap_trim_trailing_space :: proc(t: ^testing.T) {
	opts := textwidth.Wrap_Options {
		trim_trailing_space = true,
	}
	expect_lines(t, "hello   \nworld \t", 10, {"hello", "world"}, opts)

	indented := textwidth.Wrap_Options {
		indent              = "    ",
		trim_trailing_space = true,
	}
	expect_lines(t, " ", 10, {""}, indented)
}

@(test)
test_wrap_invalid_utf8 :: proc(t: ^testing.T) {
	expect_lines(t, "\xff\xfe \xfd", 2, {"\xff\xfe", "\xfd"})
}

@(test)
test_wrap_zero_width_word_stays_on_line :: proc(t: ^testing.T) {
	// A trailing reset after a space has no width, so it must not start a
	// line of its own that looks blank.
	expect_lines(t, "hello \x1b[0m", 5, {"hello\x1b[0m"})
	expect_lines(t, "\x1b[31mhello world \x1b[0m", 5, {"\x1b[31mhello", "world\x1b[0m"})
	// When it fits, the space before it stays.
	expect_lines(t, "ab \x1b[0m", 5, {"ab \x1b[0m"})
}

@(test)
test_wrap_breaks_on_unicode_spaces :: proc(t: ^testing.T) {
	// U+3000 IDEOGRAPHIC SPACE takes two columns; U+2003 EM SPACE takes one.
	expect_lines(t, "日本　語です　テスト", 6, {"日本", "語です", "テスト"})
	expect_lines(t, "ab cd ef", 5, {"ab cd", "ef"})
	// No-break spaces still join words.
	expect_lines(t, "a b c", 3, {"a b", "c"})
	expect_lines(t, "a b c", 3, {"a b", "c"})
	// Trimming removes Unicode spaces too.
	expect_lines(t, "ab　", 4, {"ab"}, {trim_trailing_space = true})
}
