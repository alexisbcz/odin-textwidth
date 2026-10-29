// Package textwidth_tests holds the unit tests for textwidth. Run them with `odin test tests`.
package textwidth_tests

import textwidth ".."
import "core:testing"

// rune_width

@(test)
test_rune_width_ascii_is_one :: proc(t: ^testing.T) {
	for r in ' ' ..= '~' {
		testing.expectf(t, textwidth.rune_width(r) == 1, "rune_width(%q) = %d", r, textwidth.rune_width(r))
	}
}

@(test)
test_rune_width_controls_are_zero :: proc(t: ^testing.T) {
	for r in ([]rune{0, '\t', '\n', '\r', '\x1b', 0x7F, 0x85, 0x9F}) {
		testing.expectf(t, textwidth.rune_width(r) == 0, "rune_width(%U) = %d", r, textwidth.rune_width(r))
	}
}

@(test)
test_rune_width_cjk_is_two :: proc(t: ^testing.T) {
	// Ideograph, hiragana, katakana, Hangul syllable, fullwidth Latin, ideographic comma.
	for r in ([]rune{'日', 'あ', 'カ', '한', 'Ａ', '、', 0x3000}) {
		testing.expectf(t, textwidth.rune_width(r) == 2, "rune_width(%q) = %d", r, textwidth.rune_width(r))
	}
}

@(test)
test_rune_width_cjk_extension_planes_are_two :: proc(t: ^testing.T) {
	// CJK Extension B, and an unassigned code point that EastAsianWidth.txt
	// reserves as wide.
	testing.expect_value(t, textwidth.rune_width(0x20000), 2)
	testing.expect_value(t, textwidth.rune_width(0x2FFFD), 2)
	testing.expect_value(t, textwidth.rune_width(0x3FFFD), 2)
}

@(test)
test_rune_width_halfwidth_katakana_is_one :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.rune_width('ｶ'), 1)
}

@(test)
test_rune_width_combining_marks_are_zero :: proc(t: ^testing.T) {
	// Acute accent, diaeresis, enclosing keycap, Devanagari virama, Hebrew point.
	for r in ([]rune{0x0301, 0x0308, 0x20E3, 0x094D, 0x05B0}) {
		testing.expectf(t, textwidth.rune_width(r) == 0, "rune_width(%U) = %d", r, textwidth.rune_width(r))
	}
}

@(test)
test_rune_width_format_characters_are_zero :: proc(t: ^testing.T) {
	// ZWSP, ZWNJ, ZWJ, word joiner, BOM, VS15, VS16, a supplementary variation selector.
	for r in ([]rune{0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0xFE0E, 0xFE0F, 0xE0100}) {
		testing.expectf(t, textwidth.rune_width(r) == 0, "rune_width(%U) = %d", r, textwidth.rune_width(r))
	}
}

@(test)
test_rune_width_visible_format_characters_are_one :: proc(t: ^testing.T) {
	// The soft hyphen and the Arabic number sign are format characters that terminals draw.
	testing.expect_value(t, textwidth.rune_width(0x00AD), 1)
	testing.expect_value(t, textwidth.rune_width(0x0600), 1)
}

@(test)
test_rune_width_hangul_jamo :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.rune_width(0x1100), 2) // leading consonant
	testing.expect_value(t, textwidth.rune_width(0x1161), 0) // medial vowel
	testing.expect_value(t, textwidth.rune_width(0x11A8), 0) // final consonant
}

@(test)
test_rune_width_emoji_is_two :: proc(t: ^testing.T) {
	for r in ([]rune{'😀', '👍', '🚀', '⌚', '🏽'}) {
		testing.expectf(t, textwidth.rune_width(r) == 2, "rune_width(%q) = %d", r, textwidth.rune_width(r))
	}
}

@(test)
test_rune_width_ambiguous_is_one :: proc(t: ^testing.T) {
	// East_Asian_Width Ambiguous characters default to narrow.
	for r in ([]rune{'±', 'α', '①', '…', '❤'}) {
		testing.expectf(t, textwidth.rune_width(r) == 1, "rune_width(%q) = %d", r, textwidth.rune_width(r))
	}
}

@(test)
test_rune_width_invalid_runes_are_one :: proc(t: ^testing.T) {
	for r in ([]rune{-1, 0xD800, 0xDFFF, 0x110000, max(rune)}) {
		testing.expectf(t, textwidth.rune_width(r) == 1, "rune_width(%d) = %d", r, textwidth.rune_width(r))
	}
}

@(test)
test_unicode_version_is_set :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.UNICODE_VERSION, "16.0.0")
}

// width: plain text

@(test)
test_width_empty_is_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width(""), 0)
}

@(test)
test_width_ascii :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("hello, world"), 12)
}

@(test)
test_width_cjk_counts_two_per_character :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("日本語"), 6)
	testing.expect_value(t, textwidth.width("a日b"), 4)
	testing.expect_value(t, textwidth.width("한국어 텍스트"), 13)
}

@(test)
test_width_ignores_newlines_and_tabs :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("a\tb\r\n"), 2)
}

// width: combining marks and graphemes

@(test)
test_width_combining_accents_are_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("é"), 1)
	testing.expect_value(t, textwidth.width("Café"), 4)
	testing.expect_value(t, textwidth.width("à́̂̃"), 1)
	// Precomposed and decomposed forms measure the same.
	testing.expect_value(t, textwidth.width("café"), textwidth.width("café"))
}

@(test)
test_width_lone_combining_mark_is_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("́"), 0)
	testing.expect_value(t, textwidth.width("́a"), 1)
}

@(test)
test_width_combining_mark_on_wide_base :: proc(t: ^testing.T) {
	// か plus the combining voiced sound mark draws as が in two columns.
	testing.expect_value(t, textwidth.width("が"), 2)
}

@(test)
test_width_hangul_jamo_sequence_is_one_syllable :: proc(t: ^testing.T) {
	// ᄒ + ᅡ + ᆫ composes to 한.
	testing.expect_value(t, textwidth.width("한"), 2)
}

// width: emoji

@(test)
test_width_zwj_family_is_one_grapheme :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("👨‍👩‍👧‍👦"), 2)
	testing.expect_value(t, textwidth.width("👨‍👩‍👧‍👦👨‍👩‍👧‍👦"), 4)
}

@(test)
test_width_skin_tone_modifier_joins_base :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("👍🏽"), 2)
	testing.expect_value(t, textwidth.width("👋🏻👋🏿"), 4)
}

@(test)
test_width_zwj_with_skin_tone :: proc(t: ^testing.T) {
	// Woman technologist with a medium skin tone: 👩 🏽 ZWJ 💻.
	testing.expect_value(t, textwidth.width("👩🏽‍💻"), 2)
	// Couple with heart and two skin tones.
	testing.expect_value(t, textwidth.width("🧑🏻‍❤️‍🧑🏿"), 2)
}

@(test)
test_width_lone_skin_tone_is_two :: proc(t: ^testing.T) {
	// A modifier after a letter does not attach to it; terminals draw a swatch.
	testing.expect_value(t, textwidth.width("a🏽"), 3)
}

@(test)
test_width_variation_selectors :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("❤"), 1)
	testing.expect_value(t, textwidth.width("❤️"), 2) // U+FE0F asks for emoji presentation
	testing.expect_value(t, textwidth.width("⌚"), 2)
	testing.expect_value(t, textwidth.width("⌚︎"), 1) // U+FE0E asks for text presentation
	testing.expect_value(t, textwidth.width("a️"), 1) // not an emoji: no effect
}

@(test)
test_width_keycap_sequence :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("1️⃣"), 2)
	testing.expect_value(t, textwidth.width("#️⃣9"), 3)
}

@(test)
test_width_flags_pair_regional_indicators :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("🇫🇷"), 2)
	testing.expect_value(t, textwidth.width("🇫🇷🇯🇵"), 4)
	// An unpaired indicator stays narrow.
	testing.expect_value(t, textwidth.width("🇫🇷🇯"), 3)
}

@(test)
test_width_zwj_after_text_does_not_join :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("a‍😀"), 3)
	testing.expect_value(t, textwidth.width("😀‍"), 2)
}

// width: escape sequences

@(test)
test_width_skips_sgr_colors :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("\x1b[31mred\x1b[0m"), 3)
	testing.expect_value(t, textwidth.width("\x1b[1;38;5;208mX\x1b[m"), 1)
	testing.expect_value(t, textwidth.width("\x1b[38;2;255;128;0m日本\x1b[39m"), 4)
}

@(test)
test_width_skips_cursor_and_erase_sequences :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("\x1b[2K\x1b[1Gok\x1b[?25h"), 2)
}

@(test)
test_width_skips_osc_hyperlinks :: proc(t: ^testing.T) {
	// OSC 8 terminated by ST, then by BEL.
	testing.expect_value(t, textwidth.width("\x1b]8;;https://odin-lang.org\x1b\\Odin\x1b]8;;\x1b\\"), 4)
	testing.expect_value(t, textwidth.width("\x1b]0;window title\x07ok"), 2)
}

@(test)
test_width_skips_short_escapes :: proc(t: ^testing.T) {
	// RIS, a character set selection, and keypad mode.
	testing.expect_value(t, textwidth.width("\x1bc\x1b(Bab\x1b="), 2)
}

@(test)
test_width_unterminated_escapes_are_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("ab\x1b[31"), 2)
	testing.expect_value(t, textwidth.width("ab\x1b]8;;https://example.com"), 2)
	testing.expect_value(t, textwidth.width("ab\x1b"), 2)
}

@(test)
test_width_malformed_csi_stops_at_stray_byte :: proc(t: ^testing.T) {
	// The CSI ends before "é", which is drawn.
	testing.expect_value(t, textwidth.width("\x1b[3é"), 1)
	testing.expect_value(t, textwidth.width("\x1b[3\n日"), 2)
}

@(test)
test_width_invalid_utf8_counts_one_per_byte :: proc(t: ^testing.T) {
	testing.expect_value(t, textwidth.width("\xff\xfe"), 2)
	testing.expect_value(t, textwidth.width("a\xe6\x97"), 3) // truncated 日
	testing.expect_value(t, textwidth.width("\xc0\x80"), 2) // overlong NUL
}
