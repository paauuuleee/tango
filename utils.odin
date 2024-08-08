package main

import "core:os"
import path "core:path/filepath"
import "core:slice"
import "core:strings"

Error :: enum {
	None,
	ExistError,
	NonExistError,
	ReadError,
	WriteError,
	OpenError,
	CloseError,
	CreateError,
	ParseError,
	NotDirError,
	NotFileError,
	RelPathError,
	AbsPathError,
	WrongTypeError,
}

possible_target_name :: proc(name: string) -> bool {
	letters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	digits := "0123456789"
	for c, i in name {
		if !strings.contains_rune(letters, c) &&
		   !(strings.contains_rune(digits, c) && i > 0) {return false}
	}
	return true
}

get_dir_path :: proc(partial_path: string) -> (string, Error) {
	if !os.is_dir(partial_path) {return "", .NotDirError}
	abs_path, ok := path.abs(partial_path)
	if !ok {return "", .AbsPathError}
	return abs_path, .None
}

get_rel_dir_path :: proc(partial_path: string) -> (string, Error) {
	cwd := os.get_current_directory()
	if !os.is_dir(partial_path) {return "", .NotDirError}
	abs_path, ok := path.abs(partial_path)
	rel_path, err := path.rel(cwd, abs_path)
	if err != .None || !ok {return "", .RelPathError}
	return rel_path, .None
}

get_file_path_if :: proc(partial_path: string, file_type: []string) -> (string, Error) {
	if !os.is_file(partial_path) {return "", .NotFileError}
	abs_path, ok := path.abs(partial_path)
	if !ok {return "", .AbsPathError}
	if !slice.contains(file_type, path.ext(abs_path)) {return "", .WrongTypeError}
	return abs_path, .None
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
