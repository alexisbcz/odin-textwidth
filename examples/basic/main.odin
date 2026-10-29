// Example basic aligns a table of mixed-width text and wraps a paragraph. Run it with `odin run examples/basic`.
package main

import textwidth "../.."
import "core:fmt"

Row :: struct {
	name: string,
	city: string,
}

main :: proc() {
	fmt.println(textwidth.width("hello"))          // 5
	fmt.println(textwidth.width("日本語"))           // 6
	fmt.println(textwidth.width("👩🏽‍💻"))            // 2
	fmt.println(textwidth.width("\x1b[1mbold\x1b[0m")) // 4

	// Columns line up because padding counts columns, not bytes.
	rows := []Row {
		{"Ada", "London"},
		{"山田太郎", "東京"},
		{"Zoë", "Zürich"},
		{"\x1b[32mGinger\x1b[0m", "Bergen, a city with a long name"},
	}
	for row in rows {
		name := textwidth.pad_right(row.name, 10)
		defer delete(name)
		city := textwidth.truncate(row.city, 12)
		defer delete(city)
		fmt.printf("| %s | %s |\n", name, textwidth.pad_right(city, 12, context.temp_allocator))
	}
	free_all(context.temp_allocator)

	// Wrap a paragraph as a bullet with a hanging indent.
	text := "Terminals draw 日本語 and emoji like 👍🏽 in two columns, and \x1b[4mescape sequences\x1b[0m in none."
	lines := textwidth.wrap(text, 30, {indent = "- ", hanging_indent = "  "})
	defer textwidth.wrap_destroy(lines)
	for line in lines {
		fmt.println(line)
	}
}
