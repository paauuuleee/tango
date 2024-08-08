package main

import "core:os"
import path "core:path/filepath"
import "core:fmt"
import "core:c/libc"
import "core:strings"

exec_new_cmd :: proc() {
	if len(os.args) != 5 {
		if len(os.args) == 3 && os.args[2] == "--help" { print_desc_exit(NEW_CMD_DESC) }
		print_desc_panic(NEW_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter."
		)
	}
	target_name := os.args[2]

	if !os.is_dir(os.args[3]) {msg_panic("The second argument must be the target folder.")}
	target_folder, ok := path.abs(os.args[3])
	if !ok {msg_panic("Cannot determine absolute path from provided directory.")}

	if os.args[4] != "--exec" && os.args[4] != "--static" && os.args[4] != "--shared" {
		msg_panic("Allowed options are --exec, --static, --shared.")
	}
	target_type := os.args[4][2:]

	target_file, err := create_target_file(target_name, target_folder, target_type)
	msg_panic_if(err, .ExistError, "Target with the same name already exists.")
	msg_panic_if(err, .CreateError, "Cannot create target file.")

	err = write_target_file(target_file)
	msg_panic_if(err, .WriteError, "Cannot write to tango file.")

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_add_cmd :: proc() {
	if len(os.args) != 4 {
		if len(os.args) == 3 && os.args[2] == "--help" { print_desc_exit(ADD_CMD_DESC) }
		print_desc_panic(ADD_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter."
		)
	}

	target_file, err := read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	if !os.is_file(os.args[3]) ||
	   path.ext(os.args[3]) != ".c" {msg_panic("The second argument must be a path to a c source file.")}
	src_file, ok := path.abs(os.args[3])
	if !ok {msg_panic("Cannot determine absolute path for provided c source file.")}

	for file in target_file.source {
		if file == src_file {msg_panic("Source file was already added to target.")}
	}
	append(&target_file.source, src_file)

	err = write_target_file(target_file)
	msg_panic_if(err, .WriteError, "Cannot write to tango file.")

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_build_cmd :: proc() {
	if len(os.args) != 3 {
		print_desc_panic(BUILD_CMD_DESC)
	}
	if len(os.args) == 3 && os.args[2] == "--help" { print_desc_exit(BUILD_CMD_DESC) }

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter."
		)
	}

	target_file, err := read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	cmd := "gcc "
	for path in target_file.includes {
		cmd = fmt.tprintf("%s-I%s/ ", cmd, path)
	}

	for file in target_file.source {
		cmd = fmt.tprintf("%s%s ", cmd, file)
	}

	for path in target_file.libraries {
		cmd = fmt.tprintf("%s-L%s/ ", cmd, path)
	}

	for link in target_file.links {
		cmd = fmt.tprintf("%s-l:%s ", cmd, link)
	}

	cmd = fmt.tprintf("%s-o %s/%s", cmd, target_file.folder, target_file.name)
	switch target_file.type {
	case "exec":
		cmd = fmt.tprintf("%s -no-pie ", cmd)
	case "static", "shared":
		cmd = fmt.tprintf("%s.a -%s ", cmd, target_file.type)
	case:
		msg_panic("No target type given.")
	}

	fmt.println(cmd)
	libc.system(strings.clone_to_cstring(cmd))

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_inc_cmd :: proc() {
	if len(os.args) != 4 {
		if len(os.args) == 3 && os.args[2] == "--help" { print_desc_exit(INC_CMD_DESC) }
		print_desc_panic(INC_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter."
		)
	}

	if !os.is_dir(os.args[3]) {
		msg_panic("Second argument must be the include path.")
	}

	include, ok := path.abs(os.args[2])
	if !ok {msg_panic("Cannot determine absolute path for include path.")}

	target_file, err := read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	for file in target_file.includes {
		if file == include {msg_panic("Include path was already added to target.")}
	}
	append(&target_file.includes, include)

	err = write_target_file(target_file)
	msg_panic_if(err, .WriteError, "Cannot write to tango file.")

	err = close_target_file(target_file)
	msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

exec_link_cmd :: proc() {
	if len(os.args) != 5 {
		if len(os.args) == 3 && os.args[2] == "--help" { print_desc_exit(INC_CMD_DESC) }
		print_desc_panic(INC_CMD_DESC)
	}

	if !possible_target_name(os.args[2]) {
		msg_panic(
			"The target name must consist of only engish letters and arabic digits. " +
			"The leading character must be a letter."
		)
	}

	target_file, err := read_target_file(os.args[2])
	msg_panic_if(err, .NonExistError, "Given target does not exists.")
	msg_panic_if(err, .OpenError, "Cannot open tango file.")
	msg_panic_if(err, .ReadError, "Cannot read tango file contents.")
	msg_panic_if(err, .ParseError, "Cannot parse tango file contents.")

	link_target := false
	if !is_file(os.args[3], &link_target) {
		msg_panic("Second argument must be the library file path.")
	}

	if link_target {

	}

	link, ok := path.abs(os.args[3])
	if !ok {msg_panic("Cannot determin absolute path for include path to library file.")}

	switch os.args[4] {
	case "--static":
		{
			if path.ext(link) !=
			   ".a" {msg_panic("When linking statically the library has to be static.")}

			if len(os.args) ==
			   6 {msg_panic("When linking statically there are no further options.")}

			append(&target_file.source, link)
		}
	case "--dynamic":
		{
			if path.ext(link) != ".so" ||
			   path.ext(link) !=
				   ".dylib" {msg_panic("When linking dynamically the library has to be shared.")}

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

			append(&target_file.libraries, lib_path)
			append(&target_file.links, lib_file)
		}
	}
}