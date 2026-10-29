package textwidth_tests

import textwidth ".."
import "base:runtime"
import "core:mem"
import "core:testing"

// Failing_Allocator forwards to `backing` until `budget` allocations have
// happened, then reports Out_Of_Memory for every further allocation.
Failing_Allocator :: struct {
	backing: runtime.Allocator,
	budget:  int,
}

failing_allocator :: proc(f: ^Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = failing_allocator_proc, data = f}
}

failing_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	runtime.Allocator_Error,
) {
	f := (^Failing_Allocator)(data)
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		if f.budget <= 0 {
			return nil, .Out_Of_Memory
		}
		f.budget -= 1
	case .Free, .Free_All, .Query_Features, .Query_Info:
	}
	return f.backing.procedure(f.backing.data, mode, size, alignment, old_memory, old_size, loc)
}

// expect_no_leaks fails the test when `track` still holds allocations or saw bad frees.
expect_no_leaks :: proc(t: ^testing.T, track: ^mem.Tracking_Allocator, loc := #caller_location) {
	testing.expectf(t, len(track.allocation_map) == 0, "%d allocations leaked", len(track.allocation_map), loc = loc)
	testing.expectf(t, len(track.bad_free_array) == 0, "%d bad frees", len(track.bad_free_array), loc = loc)
}

@(test)
test_every_layout_proc_frees_cleanly :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	alloc := mem.tracking_allocator(&track)

	text := "\x1b[31m日本語\x1b[0m and 👩🏽‍💻 text that wraps"
	for w in 0 ..= 12 {
		a := textwidth.truncate(text, w, allocator = alloc)
		b := textwidth.pad_right(text, w, alloc)
		c := textwidth.pad_left(text, w, alloc)
		d := textwidth.center(text, w, alloc)
		lines := textwidth.wrap(text, w, {indent = "* ", hanging_indent = "  ", trim_trailing_space = true}, alloc)
		delete(a, alloc)
		delete(b, alloc)
		delete(c, alloc)
		delete(d, alloc)
		textwidth.wrap_destroy(lines, alloc)
	}
	testing.expect(t, track.total_allocation_count > 0, "the tracker saw no allocations")
	expect_no_leaks(t, &track)
}

@(test)
test_wrap_reports_out_of_memory_without_leaking :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	// Fail at every allocation in turn until wrap gets enough to finish.
	succeeded := false
	for budget in 0 ..< 200 {
		f := Failing_Allocator{mem.tracking_allocator(&track), budget}
		lines, err := textwidth.wrap(SAMPLE, 10, allocator = failing_allocator(&f))
		if err == nil {
			textwidth.wrap_destroy(lines, mem.tracking_allocator(&track))
			succeeded = true
			break
		}
		testing.expect_value(t, err, runtime.Allocator_Error.Out_Of_Memory)
		testing.expect_value(t, len(lines), 0)
		expect_no_leaks(t, &track)
	}
	testing.expect(t, succeeded, "wrap never succeeded")
	expect_no_leaks(t, &track)
}

@(test)
test_truncate_reports_out_of_memory :: proc(t: ^testing.T) {
	f := Failing_Allocator{context.allocator, 0}
	s, err := textwidth.truncate("hello world", 5, allocator = failing_allocator(&f))
	testing.expect_value(t, err, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, s, "")

	// The copy for text that fits fails the same way.
	g := Failing_Allocator{context.allocator, 0}
	_, err = textwidth.truncate("hi", 5, allocator = failing_allocator(&g))
	testing.expect_value(t, err, runtime.Allocator_Error.Out_Of_Memory)
}

@(test)
test_pad_reports_out_of_memory :: proc(t: ^testing.T) {
	f := Failing_Allocator{context.allocator, 0}
	alloc := failing_allocator(&f)
	_, e1 := textwidth.pad_right("ab", 5, alloc)
	_, e2 := textwidth.pad_left("ab", 5, alloc)
	_, e3 := textwidth.center("ab", 5, alloc)
	testing.expect_value(t, e1, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, e2, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, e3, runtime.Allocator_Error.Out_Of_Memory)
}

@(test)
test_width_does_not_allocate :: proc(t: ^testing.T) {
	f := Failing_Allocator{context.allocator, 0}
	context.allocator = failing_allocator(&f)
	testing.expect_value(t, textwidth.width("日本語 👩🏽‍💻 \x1b[1mbold\x1b[0m"), 14)
	testing.expect_value(t, textwidth.rune_width('日'), 2)
}
