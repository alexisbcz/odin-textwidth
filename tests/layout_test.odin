package textwidth_tests

import textwidth ".."
import "core:strings"
import "core:testing"

// truncate

@(test)
test_truncate_returns_copy_when_it_fits :: proc(t: ^testing.T) {
	s := textwidth.truncate("hello", 5)
	defer delete(s)
	testing.expect_value(t, s, "hello")
}

@(test)
test_truncate_ascii_appends_ellipsis :: proc(t: ^testing.T) {
	s := textwidth.truncate("hello world", 8)
	defer delete(s)
	testing.expect_value(t, s, "hello w…")
	testing.expect_value(t, textwidth.width(s), 8)
}

@(test)
test_truncate_custom_and_empty_tail :: proc(t: ^testing.T) {
	a := textwidth.truncate("hello world", 8, "...")
	defer delete(a)
	testing.expect_value(t, a, "hello...")

	b := textwidth.truncate("hello world", 8, "")
	defer delete(b)
	testing.expect_value(t, b, "hello wo")
}

@(test)
test_truncate_exactly_at_wide_boundary :: proc(t: ^testing.T) {
	// The cut falls right after the third two-column character.
	a := textwidth.truncate("日本語x", 6, "")
	defer delete(a)
	testing.expect_value(t, a, "日本語")
	testing.expect_value(t, textwidth.width(a), 6)

	// Seven columns minus one for the tail leaves room for exactly three.
	b := textwidth.truncate("日本語のテキスト", 7)
	defer delete(b)
	testing.expect_value(t, b, "日本語…")
	testing.expect_value(t, textwidth.width(b), 7)
}

@(test)
test_truncate_never_splits_wide_character :: proc(t: ^testing.T) {
	// Five columns cannot hold half of 語, so the result is one column short.
	a := textwidth.truncate("日本語", 5, "")
	defer delete(a)
	testing.expect_value(t, a, "日本")

	b := textwidth.truncate("日本語", 4)
	defer delete(b)
	testing.expect_value(t, b, "日…")
	testing.expect_value(t, textwidth.width(b), 3)
}

@(test)
test_truncate_keeps_whole_graphemes :: proc(t: ^testing.T) {
	a := textwidth.truncate("ééé", 2, "")
	defer delete(a)
	testing.expect_value(t, a, "éé")

	b := textwidth.truncate("👨‍👩‍👧‍👦👨‍👩‍👧‍👦", 3, "")
	defer delete(b)
	testing.expect_value(t, b, "👨‍👩‍👧‍👦")

	c := textwidth.truncate("👍🏽👍🏽", 3)
	defer delete(c)
	testing.expect_value(t, c, "👍🏽…")
}

@(test)
test_truncate_ansi_reappends_reset :: proc(t: ^testing.T) {
	s := textwidth.truncate("\x1b[31mhello world\x1b[0m", 5)
	defer delete(s)
	testing.expect_value(t, s, "\x1b[31mhell…" + textwidth.RESET)
	testing.expect_value(t, textwidth.width(s), 5)
}

@(test)
test_truncate_ansi_no_reset_when_style_closed :: proc(t: ^testing.T) {
	s := textwidth.truncate("\x1b[1mab\x1b[0mcdef", 4)
	defer delete(s)
	testing.expect_value(t, s, "\x1b[1mab\x1b[0mc…")
}

@(test)
test_truncate_ansi_keeps_escape_at_cut :: proc(t: ^testing.T) {
	// The reset sits right at the cut, so it is kept and no second reset follows.
	s := textwidth.truncate("\x1b[32mabc\x1b[0mdef", 4)
	defer delete(s)
	testing.expect_value(t, s, "\x1b[32mabc\x1b[0m…")
}

@(test)
test_truncate_plain_text_gets_no_reset :: proc(t: ^testing.T) {
	s := textwidth.truncate("abcdef", 3)
	defer delete(s)
	testing.expect(t, !strings.contains(s, "\x1b"))
}

@(test)
test_truncate_zero_and_negative_width :: proc(t: ^testing.T) {
	a := textwidth.truncate("hello", 0)
	defer delete(a)
	testing.expect_value(t, a, "")

	b := textwidth.truncate("hello", -3)
	defer delete(b)
	testing.expect_value(t, b, "")

	c := textwidth.truncate("", 0)
	defer delete(c)
	testing.expect_value(t, c, "")
}

@(test)
test_truncate_drops_tail_wider_than_budget :: proc(t: ^testing.T) {
	s := textwidth.truncate("hello", 2, "...")
	defer delete(s)
	testing.expect_value(t, s, "he")
}

@(test)
test_truncate_invalid_utf8_keeps_whole_bytes :: proc(t: ^testing.T) {
	s := textwidth.truncate("\xff\xfe\xfd", 2, "")
	defer delete(s)
	testing.expect_value(t, s, "\xff\xfe")
}

// pad_right, pad_left, center

@(test)
test_pad_right_ascii_and_cjk :: proc(t: ^testing.T) {
	a := textwidth.pad_right("ab", 5)
	defer delete(a)
	testing.expect_value(t, a, "ab   ")

	b := textwidth.pad_right("名前", 8)
	defer delete(b)
	testing.expect_value(t, b, "名前    ")
	testing.expect_value(t, textwidth.width(b), 8)
}

@(test)
test_pad_left_ascii_and_cjk :: proc(t: ^testing.T) {
	a := textwidth.pad_left("42", 5)
	defer delete(a)
	testing.expect_value(t, a, "   42")

	b := textwidth.pad_left("価格", 6)
	defer delete(b)
	testing.expect_value(t, b, "  価格")
}

@(test)
test_center_puts_odd_space_on_the_right :: proc(t: ^testing.T) {
	a := textwidth.center("ab", 6)
	defer delete(a)
	testing.expect_value(t, a, "  ab  ")

	b := textwidth.center("ab", 5)
	defer delete(b)
	testing.expect_value(t, b, " ab  ")

	c := textwidth.center("日", 5)
	defer delete(c)
	testing.expect_value(t, c, " 日  ")
}

@(test)
test_pad_wider_text_is_unchanged :: proc(t: ^testing.T) {
	for w in ([]int{-1, 0, 3, 4}) {
		a := textwidth.pad_right("日本", w)
		b := textwidth.pad_left("日本", w)
		c := textwidth.center("日本", w)
		testing.expect_value(t, a, "日本")
		testing.expect_value(t, b, "日本")
		testing.expect_value(t, c, "日本")
		delete(a)
		delete(b)
		delete(c)
	}
}

@(test)
test_pad_ignores_escape_sequences :: proc(t: ^testing.T) {
	s := textwidth.pad_right("\x1b[31mok\x1b[0m", 4)
	defer delete(s)
	testing.expect_value(t, s, "\x1b[31mok\x1b[0m  ")
	testing.expect_value(t, textwidth.width(s), 4)
}

@(test)
test_pad_empty_string :: proc(t: ^testing.T) {
	s := textwidth.center("", 3)
	defer delete(s)
	testing.expect_value(t, s, "   ")
}
