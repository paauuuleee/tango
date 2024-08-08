package main

import "core:strings"
import "core:os"

possible_target_name :: proc(name: string) -> bool {
    letters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    digits := "0123456789"
	for c, i in name {
		if !strings.contains_rune(letters, c) &&
           !(strings.contains_rune(digits, c) && i > 0) { return false }
	}
	return true
}

is_file :: proc(path: string, is_target: ^bool = nil) -> bool {
	if strings.contains(path, ":") {
		target_str := strings.split(path, ":")
		if len(target_str) != 2 ||
		   target_str[0] != "target" ||
		   !possible_target_name(target_str[1]) {return false}
		is_target^ = true
		return true
	}

	is_target^ = false
	return os.is_dir(path)
}