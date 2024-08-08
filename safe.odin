package main

import "core:fmt"
import "core:os"
import "core:strings"

TargetFile :: struct {
	fd:        os.Handle,
	name:      string,
	folder:    string,
	type:      string,
	source:    [dynamic]string,
	includes:  [dynamic]string,
	libraries: [dynamic]string,
	links:     [dynamic]string,
	depends:   [dynamic]string,
}

TargetFileError :: enum {
	None,
	ExistError,
	NonExistError,
	ReadError,
	WriteError,
	OpenError,
	CloseError,
	CreateError,
	ParseError,
}

create_target_file :: proc(name, folder, type: string) -> (TargetFile, TargetFileError) {
	if os.exists(fmt.tprintf("./%s.tango", name)) {return TargetFile{}, .ExistError}

	fd, errno := os.open(fmt.tprintf("./%s.tango", name), os.O_CREATE | os.O_RDWR, 0o0644)
	if errno != 0 {return TargetFile{}, .CreateError}

	return TargetFile{fd = fd, name = name, folder = folder, type = type}, .None
}

close_target_file :: proc(target_file: TargetFile) -> TargetFileError {
	if os.close(target_file.fd) != 0 {return .CloseError}
	return .None
}

write_target_file :: proc(target_file: TargetFile) -> TargetFileError {
	target_file_content := fmt.tprintf(
		"target %s\nfolder %s\ntype %s\n",
		target_file.name,
		target_file.folder,
		target_file.type,
	)

	if len(target_file.source) > 0 {
		target_file_content = fmt.tprintf(
			"%ssource\n\t%s\n",
			target_file_content,
			strings.join(target_file.source[:], "\n\t"),
		)
	}

	if len(target_file.includes) > 0 {
		target_file_content = fmt.tprintf(
			"%sincludes\n\t%s\n",
			target_file_content,
			strings.join(target_file.includes[:], "\n\t"),
		)
	}

	if len(target_file.libraries) > 0 {
		target_file_content = fmt.tprintf(
			"%slibraries\n\t%s\n",
			target_file_content,
			strings.join(target_file.libraries[:], "\n\t"),
		)
	}

	if len(target_file.links) > 0 {
		target_file_content = fmt.tprintf(
			"%slinks\n\t%s\n",
			target_file_content,
			strings.join(target_file.links[:], "\n\t"),
		)
	}

	if len(target_file.depends) > 0 {
		target_file_content = fmt.tprintf(
			"%sdepends\n\t%s\n",
			target_file_content,
			strings.join(target_file.depends[:], "\n\t"),
		)
	}

	if _, errno := os.write_at(target_file.fd, transmute([]byte)target_file_content, 0);
	   errno != 0 {return .WriteError}
	return .None
}

read_target_file :: proc(target_name: string) -> (TargetFile, TargetFileError) {
	if !os.exists(fmt.tprintf("./%s.tango", target_name)) {
		return TargetFile{}, .NonExistError
	}

	fd: os.Handle
	errno: os.Errno
	if fd, errno = os.open(fmt.tprintf("./%s.tango", target_name), os.O_RDWR); errno != 0 {
		return TargetFile{}, .OpenError
	}

	target_file := TargetFile {
		fd = fd,
	}

	data, ok := os.read_entire_file(fd)
	if !ok {return TargetFile{}, .ReadError}

	target_file_content := string(data)
	target_lines := strings.split_lines(target_file_content)

	if len(target_lines) < 3 {return TargetFile{}, .ParseError}

	i := int(0)
	line_elems := strings.split(target_lines[i], " ")
	if len(line_elems) != 2 || line_elems[0] != "target" {return TargetFile{}, .ParseError}
	if !possible_target_name(line_elems[1]) {return TargetFile{}, .ParseError}
	target_file.name = line_elems[1]
	i += 1

	line_elems = strings.split(target_lines[i], " ")
	if len(line_elems) != 2 || line_elems[0] != "folder" {return TargetFile{}, .ParseError}
	if !os.is_dir(line_elems[1]) {return TargetFile{}, .ParseError}
	target_file.folder = line_elems[1]
	i += 1

	line_elems = strings.split(target_lines[i], " ")
	if len(line_elems) != 2 || line_elems[0] != "type" {return TargetFile{}, .ParseError}
	if line_elems[1] != "exec" &&
	   line_elems[1] != "static" &&
	   line_elems[1] != "shared" {return TargetFile{}, .ParseError}
	target_file.type = line_elems[1]

	i += 1
	loop: for i < len(target_lines) {
		switch target_lines[i] {
		case "src_files":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == '\t' {
					file := target_lines[i][1:]
					if !os.is_file(file) {return TargetFile{}, .ParseError}
					append(&target_file.source, file)
					i += 1
				}
			}
		case "inc_paths":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == '\t' {
					path := target_lines[i][1:]
					if !os.is_dir(path) {return TargetFile{}, .ParseError}
					append(&target_file.includes, path)
					i += 1
				}
			}
		case "lib_paths":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == '\t' {
					path := target_lines[i][1:]
					if !os.is_dir(path) {return TargetFile{}, .ParseError}
					append(&target_file.libraries, path)
					i += 1
				}
			}
		case "links":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == '\t' {
					link := target_lines[i][1:]
					if !is_file(link) {return TargetFile{}, .ParseError}
					append(&target_file.links, link)
					i += 1
				}
			}
		case "depends":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == '\t' {
					depend := target_lines[i][1:]
					if !possible_target_name(depend) {return TargetFile{}, .ParseError}
					append(&target_file.depends, depend)
					i += 1
				}
			}
		case:
			break loop
		}
	}

	return target_file, .None
}
