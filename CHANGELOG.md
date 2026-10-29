# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-29

### Added

- `rune_width` returns 0, 1 or 2 columns for a code point, from tables generated out of Unicode 16.0.0.
- `width` measures a string by grapheme, so ZWJ emoji, skin-tone modifiers, flags, keycaps, variation selectors and combining marks measure the way terminals draw them. It skips CSI, OSC and other ANSI escape sequences.
- `truncate` cuts text to a column budget with a tail, never splits a grapheme or an escape sequence, and appends `RESET` when the cut text is still styled.
- `pad_right`, `pad_left` and `center` pad text to a column width.
- `wrap` and `wrap_destroy` wrap text greedily on whitespace, hard-break long words and keep existing newlines. `Wrap_Options` sets the indent, the hanging indent and trailing-space trimming.
- `tools/gentables` regenerates the width tables from the Unicode Character Database.

[Unreleased]: https://github.com/alexisbcz/odin-textwidth/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alexisbcz/odin-textwidth/releases/tag/v0.1.0
