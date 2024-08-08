package main

import "core:c/libc"
import "core:fmt"
import "core:os"
import path "core:path/filepath"
import "core:slice"
import "core:strings"

exec_new_cmd :: proc() {
	if len(os.args) != 5 {
		if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(NEW_CMD_DESC)}
		print_desc_panic(NEW_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter.",
		)
	}
	target_name := os.args[2]

	target_directory, err := get_dir_path(os.args[3])
	msg_panic_if(err, .NotDirError, "Target directory must be a path to a folder.")
	msg_panic_if(err, .AbsPathError, "Cannot determine absolute path to directory.")

	if os.args[4] != "--exec" && os.args[4] != "--static" && os.args[4] != "--shared" {
		msg_panic("Allowed options are --exec, --static, --shared.")
	}
	target_type := os.args[4][2:]

	target_file: TargetFile
	target_file, err = create_target_file(target_name, target_directory, target_type)
	msg_panic_if(err, .ExistError, "Target with the same name already exists.")
	msg_panic_if(err, .CreateError, "Cannot create target file.")

	err = write_target_file(target_file)
	msg_panic_if(err, .WriteError, "Cannot write to tango file.")

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_add_cmd :: proc() {
	if len(os.args) != 4 {
		if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(ADD_CMD_DESC)}
		print_desc_panic(ADD_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter.",
		)
	}

	target_file, err := read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	src_file: string
	src_file, err = get_file_path_if(os.args[3], {".c"})
	msg_panic_if(err, .NotFileError, "The second argument must be a path to a c source file.")
	msg_panic_if(err, .AbsPathError, "Cannot determine absolute path for provided c source file.")
	msg_panic_if(err, .WrongTypeError, "Added file must be a path to a c source file.")

	if slice.contains(
		   target_file.source[:],
		   src_file,
	   ) {msg_panic("Source file was already added to target.")}
	append(&target_file.source, src_file)

	err = write_target_file(target_file)
	msg_panic_if(err, .WriteError, "Cannot write to tango file.")

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_build_cmd :: proc() {
	if len(os.args) != 3 {
		print_desc_panic(BUILD_CMD_DESC)
	} else if len(os.args) == 3 && os.args[2] == "--help" {
		print_desc_exit(BUILD_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter.",
		)
	}

	target_file, err := read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	compile(target_file)
}

compile :: proc(target_file: TargetFile) {
	cmd := "gcc"

	if len(target_file.includes) > 0 {
		cmd = fmt.tprintf("%s -I%s/", cmd, strings.join(target_file.includes[:], "/ -I"))
	}

	if len(target_file.source) < 1 {msg_panic("Target has to have one source file to be compiled")}
	cmd = fmt.tprintf("%s %s", cmd, strings.join(target_file.source[:], " "))

	if len(target_file.libraries) > 0 {
		cmd = fmt.tprintf("%s -L%s/", cmd, strings.join(target_file.libraries[:], "/ -L"))
	}

	if len(target_file.links) > 0 {
		cmd = fmt.tprintf("%s -l:%s", cmd, strings.join(target_file.links[:], " -l:"))
	}

	cmd = fmt.tprintf("%s -o %s/%s", cmd, target_file.directory, target_file.name)

	if target_file.type == "static" || target_file.type == "shared" {
		cmd = fmt.tprintf("%s.a -%s ", cmd, target_file.type)
	}

	fmt.println(cmd)
	libc.system(strings.clone_to_cstring(cmd))

	err := close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_inc_cmd :: proc() {
	if len(os.args) != 4 {
		if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(INC_CMD_DESC)}
		print_desc_panic(INC_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter.",
		)
	}

	include, err := get_rel_dir_path(os.args[3])
	msg_panic_if(err, .NotDirError, "The second argument must be a valid path to a directory.")
	msg_panic_if(err, .RelPathError, "Cannot determine relative path to include directory.")

	target_file: TargetFile
	target_file, err = read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	if slice.contains(
		   target_file.includes[:],
		   include,
	   ) {msg_panic("Include path was already added to target.")}
	append(&target_file.includes, include)

	err = write_target_file(target_file)
	msg_panic_if(err, .WriteError, "Cannot write to tango file.")

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_link_cmd :: proc() {
	if len(os.args) != 5 {
		if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(INC_CMD_DESC)}
		print_desc_panic(INC_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter.",
		)
	}

	target_file, err := read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	// Do linking stuff

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_depend_cmd :: proc() {
	if len(os.args) != 4 {
		if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(DEPEND_CMD_DESC)}
		print_desc_panic(DEPEND_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) || !possible_target_name(os.args[3]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter.",
		)
	}

	target_file, err := read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	depend_target_file: TargetFile
	depend_target_file, err = read_target_file(os.args[3])
	msg_panic_if(err, .NonExistError, "Dependency target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open dependency tango file.")

	err = close_target_file(depend_target_file)
	msg_panic_if(err, .CloseError, "Cannot close dependency tango file.")

	if slice.contains(target_file.depends[:], os.args[3]) {
		msg_panic("Given dependecy target is already added to target.")
	}
	append(&target_file.depends, os.args[3])

	err = write_target_file(target_file)
	msg_panic_if(err, .WriteError, "Cannot write to tango file.")

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}
