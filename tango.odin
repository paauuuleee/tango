package main

import libc "core:c/libc"
import "core:fmt"
import "core:os"
import path "core:path/filepath"
import str "core:strings"

error_exit :: proc(msg: string, error: any = nil) {
	if error == nil {
		fmt.eprintln("Error:", msg)
	} else {
		fmt.eprintln("Error:", msg, "::", error)
	}
	os.exit(1)
}

print_menu :: proc(is_error: bool = false) {
	CMD_OPTS :: `Tago is a modern build tool for c language targets

Usage:

    tango <cmd> [arg*] {opt*}

Commands:

    new     Creates a new c target
    build   Builds the target
    add     Adds source files to the target comilation
    inc     Sets an include path
    link    Links static and dynamic libraries (can also link to other target)
    depend  Makes building a target dependend on another target built

Type "-help" after unclear command and recieve an in depth explanation`

	fmt.println(CMD_OPTS)
	os.exit(1 if is_error else 0)
}

exec_new_cmd :: proc() {
	if len(os.args) != 5 {
		if len(os.args) == 3 && os.args[2] == "-help" { /*print new menu without error*/}
		// print new menu with error
	}

	if !possible_target_name(os.args[2]) {
		error_exit(
			"First argument must be the target name. Allowed characters: letters and numbers (first must be a letter)",
		)
	}
	target_name := os.args[2]
	if os.exists(fmt.tprintf("./%s.tango", target_name)) {
		error_exit("Cannot override existing target.")
	}

	if !os.is_dir(os.args[3]) {error_exit("The second argument must be the target folder.")}
	target_folder, ok := path.abs(os.args[3])
	if !ok {error_exit("Cannot determine absolute path from provided directory.")}

	target_type: string
	switch os.args[4] {
	case "--exec":
		target_type = "exec"
	case "--static":
		target_type = "static"
	case "--shared":
		target_type = "shared"
	case:
		error_exit("Allowed options are -exec, -static, -shared")
	}

	target_file, errno := os.open(
		fmt.tprintf("./%s.tango", target_name),
		os.O_CREATE | os.O_RDWR,
		0o0644,
	)
	if errno != 0 {error_exit("Cannot create tango file.", fmt.tprint("Errno: ", errno))}

	err := write_target_file(
		target_file,
		TargetFile {
			target_name = target_name,
			target_folder = target_folder,
			target_type = target_type,
		},
	)
	if err != .None {error_exit("Cannot write to tango file because", err)}
}

exec_add_cmd :: proc() {
	if len(os.args) != 4 {
		// print add menu with error
	}

	if !possible_target_name(os.args[2]) {
		error_exit(" Allowed characters: letters and numbers (first must be a letter)")
	}

	fd, target_file, read_err := read_target_file(os.args[2])
	if read_err != .None {error_exit("Cannot read tango file because", read_err)}

	if !os.is_file(os.args[3]) ||
	   path.ext(os.args[3]) != ".c" {error_exit("The second argument must be a c source file.")}
	src_file, ok := path.abs(os.args[3])
	if !ok {error_exit("Cannot determine absolute path for provided c source file.")}

	for file in target_file.src_files {
		if file == src_file {error_exit("Source file was already added to target")}
	}
	append(&target_file.src_files, src_file)
	write_err := write_target_file(fd, target_file)
	if write_err != .None {error_exit("Cannot write to tango file because", write_err)}
}

possible_target_name :: proc(name: string) -> bool {
	for c, i in name {
		check: switch c {
		case 'a' ..= 'z', 'A' ..= 'B':
			return true
		case '0' ..= '9':
			{
				if i > 0 {break check}
				return false
			}
		case:
			return false
		}
	}
	return true
}

is_file :: proc(path: string, is_target: ^bool = nil) -> bool {
	if str.contains(path, ":") {
		target_str := str.split(path, ":")
		if len(target_str) != 2 ||
		   target_str[0] != "target" ||
		   !possible_target_name(target_str[1]) {return false}
		is_target^ = true
		return true
	}

	is_target^ = false
	return os.is_dir(path)
}

TargetFile :: struct {
	target_name:   string,
	target_folder: string,
	target_type:   string,
	src_files:     [dynamic]string,
	inc_paths:     [dynamic]string,
	lib_paths:     [dynamic]string,
	links:         [dynamic]string,
	depends:       [dynamic]string,
}

WriteError :: enum {
	None,
	FlushError,
	WriteError,
	CloseError,
}

ReadError :: enum {
	None,
	NonExistError,
	OpenError,
	ReadError,
	ParseError,
}

write_target_file :: proc(fd: os.Handle, using target_file: TargetFile) -> WriteError {
	errno: os.Errno
	if errno = os.flush(fd); errno != 0 {return .FlushError}

	target_str := fmt.tprintf(
		"target %s\nfolder %s\ntype %s\n",
		target_name,
		target_folder,
		target_type,
	)

	if len(src_files) > 0 {
		target_str = fmt.tprintf("%ssrc_files\n", target_str)
		for file in src_files {
			target_str = fmt.tprintf("%s %s\n", target_str, file)
		}
	}

	if len(inc_paths) > 0 {
		target_str = fmt.tprintf("%sinc_paths\n", target_str)
		for path in inc_paths {
			target_str = fmt.tprintf("%s %s\n", target_str, path)
		}
	}

	if len(lib_paths) > 0 {
		target_str = fmt.tprintf("%slib_paths\n", target_str)
		for path in lib_paths {
			target_str = fmt.tprintf("%s %s\n", target_str, path)
		}
	}

	if len(links) > 0 {
		target_str = fmt.tprintf("%slinks\n", target_str)
		for link in links {
			target_str = fmt.tprintf("%s %s\n", target_str, link)
		}
	}

	if len(depends) > 0 {
		target_str = fmt.tprintf("%sdepends\n", target_str)
		for depend in depends {
			target_str = fmt.tprintf("%s %s\n", target_str, depend)
		}
	}

	if _, errno = os.write_at(fd, transmute([]byte)target_str, 0); errno != 0 {return .WriteError}
	if errno = os.close(fd); errno != 0 {return .CloseError}
	return .None
}

read_target_file :: proc(target_name: string) -> (os.Handle, TargetFile, ReadError) {
	if !os.exists(fmt.tprintf("./%s.tango", target_name)) {
		return 0, TargetFile{}, .NonExistError
	}

	fd: os.Handle
	errno: os.Errno
	if fd, errno = os.open(fmt.tprintf("./%s.tango", target_name), os.O_RDWR); errno != 0 {
		fmt.println(errno)
		return 0, TargetFile{}, .OpenError
	}

	target_file: TargetFile

	data, ok := os.read_entire_file(fd)
	if !ok {return 0, TargetFile{}, .ReadError}

	target_str := string(data)
	target_lines := str.split_lines(target_str)

	if len(target_lines) < 3 {return 0, TargetFile{}, .ParseError}

	i := int(0)
	line_elems := str.split(target_lines[i], " ")
	if len(line_elems) != 2 || line_elems[0] != "target" {return 0, TargetFile{}, .ParseError}
	if !possible_target_name(line_elems[1]) {return 0, TargetFile{}, .ParseError}
	target_file.target_name = line_elems[1]
	i += 1

	line_elems = str.split(target_lines[i], " ")
	if len(line_elems) != 2 || line_elems[0] != "folder" {return 0, TargetFile{}, .ParseError}
	if !os.is_dir(line_elems[1]) {return 0, TargetFile{}, .ParseError}
	target_file.target_folder = line_elems[1]
	i += 1

	line_elems = str.split(target_lines[i], " ")
	if len(line_elems) != 2 || line_elems[0] != "type" {return 0, TargetFile{}, .ParseError}
	if line_elems[1] != "exec" &&
	   line_elems[1] != "static" &&
	   line_elems[1] != "shared" {return 0, TargetFile{}, .ParseError}
	target_file.target_type = line_elems[1]

	i += 1
	loop: for i < len(target_lines) {
		switch target_lines[i] {
		case "src_files":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == ' ' {
					file := target_lines[i][1:]
					if !os.is_file(file) {return 0, TargetFile{}, .ParseError}
					append(&target_file.src_files, file)
					i += 1
				}
			}
		case "inc_paths":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == ' ' {
					path := target_lines[i][1:]
					if !os.is_dir(path) {return 0, TargetFile{}, .ParseError}
					append(&target_file.inc_paths, path)
					i += 1
				}
			}
		case "lib_paths":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == ' ' {
					path := target_lines[i][1:]
					if !os.is_dir(path) {return 0, TargetFile{}, .ParseError}
					append(&target_file.lib_paths, path)
					i += 1
				}
			}
		case "links":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == ' ' {
					link := target_lines[i][1:]
					if !is_file(link) {return 0, TargetFile{}, .ParseError}
					append(&target_file.links, link)
					i += 1
				}
			}
		case "depends":
			{
				i += 1
				for i < len(target_lines) &&
				    len(target_lines[i]) != 0 &&
				    target_lines[i][0] == ' ' {
					depend := target_lines[i][1:]
					if !possible_target_name(depend) {return 0, TargetFile{}, .ParseError}
					append(&target_file.depends, depend)
					i += 1
				}
			}
		case:
			break loop
		}
	}

	return fd, target_file, .None
}

exec_build_cmd :: proc() {
	if len(os.args) != 3 {
		// print build menu with error
	}

	if !possible_target_name(os.args[2]) {
		error_exit("First argument must be the target name.")
	}

	fd, target_file, read_err := read_target_file(os.args[2])
	if read_err != .None {error_exit("Cannot read tango file because", read_err)}

	cmd := "gcc "
	for path in target_file.inc_paths {
		cmd = fmt.tprintf("%s-I%s/ ", cmd, path)
	}

	for file in target_file.src_files {
		cmd = fmt.tprintf("%s%s ", cmd, file)
	}

	for path in target_file.lib_paths {
		cmd = fmt.tprintf("%s-L%s/ ", cmd, path)
	}

	for link in target_file.links {
		cmd = fmt.tprintf("%s-l:%s ", cmd, link)
	}

	cmd = fmt.tprintf("%s-o %s/%s", cmd, target_file.target_folder, target_file.target_name)
	switch target_file.target_type {
	case "exec":
		cmd = fmt.tprintf("%s -no-pie ", cmd)
	case "static":
		cmd = fmt.tprintf("%s.a -static ", cmd)
	case "shared":
		cmd = fmt.tprintf("%s.so -shared ", cmd)
	case:
		error_exit("No target type given.")
	}

	fmt.println(cmd)
	libc.system(str.clone_to_cstring(cmd))
}

exec_inc_cmd :: proc() {
	if len(os.args) != 4 {
		// print inc menu with error
	}

	if !possible_target_name(os.args[2]) {
		error_exit("First argument must be the target name.")
	}

	if !os.is_dir(os.args[3]) {
		error_exit("Second argument must be the include path.")
	}

	inc_path, ok := path.abs(os.args[2])
	if !ok {error_exit("Cannot determine absolute path for include path")}

	fd, target_file, read_err := read_target_file(os.args[2])
	if read_err != .None {error_exit("Cannot read tango file because", read_err)}

	append(&target_file.inc_paths, inc_path)
	write_err := write_target_file(fd, target_file)
	if write_err != .None {error_exit("Cannot write to tango file because", write_err)}
}

exec_link_cmd :: proc() {
	if len(os.args) != 5 {
		// if !(len(os.args) == 6 && os.args[5] == "--dynamic") { /* print link menu width error */}
	}

	if !possible_target_name(os.args[2]) {
		error_exit("First argument must be the target name")
	}

	fd, target_file, read_err := read_target_file(os.args[2])
	if read_err != .None {error_exit("Cannot read tango file because.", read_err)}

	link_target := false
	if !is_file(os.args[3], &link_target) {
		error_exit("Second argument must be the library file path.")
	}

	if link_target {

	}

	link, ok := path.abs(os.args[3])
	if !ok {error_exit("Cannot determin absolute path for include path to library file.")}

	switch os.args[4] {
	case "--static":
		{
			if path.ext(link) !=
			   ".a" {error_exit("When linking statically the library has to be static.")}

			if len(os.args) ==
			   6 {error_exit("When linking statically there are no further options.")}

			append(&target_file.src_files, link)
		}
	case "--dynamic":
		{
			if path.ext(link) != ".so" ||
			   path.ext(link) !=
				   ".dylib" {error_exit("When linking dynamically the library has to be shared.")}

			lib_path := path.dir(link)
			/*rel_lib_path, err := path.rel(target_file.target_folder, abs_lib_path)
			if err != .None {error_exit()}
			lib_path = rel_lib_path

			if len(os.args) == 6 {
				switch os.args[5] {
				case "--absolute":
					lib_path = lib_path
				case "--relative":
					lib_path = path.rel(target_file.target_folder, lib_path)
				case:
					error_exit("The last option must be \"--absolute\" or \"--relative\".")
				}
			}
            */

			lib_file := path.base(link)

			append(&target_file.lib_paths, lib_path)
			append(&target_file.links, lib_file)
		}
	}
}

main :: proc() {
	args := os.args
	switch len(os.args) {
	case 1:
		print_menu(true)
	case:
		{
			switch os.args[1] {
			case "new":
				exec_new_cmd()
			case "add":
				exec_add_cmd()
			case "link":
			case "inc":
				exec_inc_cmd()
			case "build":
				exec_build_cmd()
			case "depend":
			case "-help":
				print_menu()
			case:
				print_menu(true)
			}
		}
	}
}
