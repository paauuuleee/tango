package main

import "core:fmt"
import "core:os"
import path "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

exec_init_cmd :: proc() {
    if len(os.args) != 2 {
        if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(INIT_CMD_DESC)}
        print_desc_panic(INIT_CMD_DESC)
    }

    err := init_tango()
    msg_panic_if(err, Error.AlreadyInitError, "Directory is already initialised to tango.")
}

exec_new_cmd :: proc() {
    _ = init_tango()

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
    msg_panic_if(err, Error.NotDirError, "Target directory must be a path to a folder.")
    msg_panic_if(err, Error.AbsPathError, "Cannot determine absolute path to directory.")

    if os.args[4] != "--exec" && os.args[4] != "--static" && os.args[4] != "--shared" {
        msg_panic("Allowed options are --exec, --static, --shared.")
    }
    target_type := os.args[4][2:]

    target_file: TargetFile
    target_file, err = create_target_file(target_name, target_directory, target_type)
    msg_panic_if(err, Error.ExistError, "Target with the same name already exists.")
    msg_panic_if(err, Error.CreateError, "Cannot create target file.")

    err = write_target_file(target_file)
    msg_panic_if(err, Error.WriteError, "Cannot write to tango file.")

    err = close_target_file(target_file)
    msg_panic_if(err, Error.CloseError, "Cannot close tango file.")
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
    msg_panic_if(err, Error.NonExistError, "Given target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
    msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
    msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

    src_file: string
    src_file, err = get_file_path_if(os.args[3], {".c"})
    msg_panic_if(err, Error.NotFileError, "The second argument must be a path to a c source file.")
    msg_panic_if(err, Error.AbsPathError, "Cannot determine absolute path for provided c source file.")
    msg_panic_if(err, Error.WrongTypeError, "Added file must be a path to a c source file.")

    if slice.contains(target_file.source[:], src_file) {msg_panic("Source file was already added to target.")}
    append(&target_file.source, src_file)

    err = write_target_file(target_file)
    msg_panic_if(err, Error.WriteError, "Cannot write to tango file.")

    err = close_target_file(target_file)
    msg_panic_if(err, Error.CloseError, "Cannot close tango file.")
}

exec_add_dir_cmd :: proc() {
    if len(os.args) != 4 {
        if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(ADD_DIR_CMD_DESC)}
        print_desc_panic(ADD_DIR_CMD_DESC)
    }

    if !possible_target_name(os.args[2]) {
        msg_panic(
            "The target name must consist of only engish letters and arabic digits. " +
            "The leading character must be a letter.",
        )
    }

    target_file, err := read_target_file(os.args[2])
    msg_panic_if(err, Error.NonExistError, "Given target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
    msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
    msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

    dir_path: string
    dir_path, err = get_dir_path(os.args[3])
    msg_panic_if(err, Error.NotDirError, "Given directoy does not exist.")
    msg_panic_if(err, Error.AbsPathError, "Cannot determine absolute path of directory.")

    if !slice.contains(target_file.src_dir[:], dir_path) {
        append(&target_file.src_dir, dir_path)
    }

    err = write_target_file(target_file)
    msg_panic_if(err, Error.WriteError, "Cannot write to tango file.")

    err = close_target_file(target_file)
    msg_panic_if(err, Error.CloseError, "Cannot close tango file.")
}

exec_build_cmd :: proc() {
    if len(os.args) != 3 {
        print_desc_panic(BUILD_CMD_DESC)
    }
     else if len(os.args) == 3 && os.args[2] == "--help" {
        print_desc_exit(BUILD_CMD_DESC)
    }

    if !possible_target_name(os.args[2]) {
        msg_panic(
            "The target name must consist of only engish letters and arabic digits. " +
            "The leading character must be a letter.",
        )
    }

    target_file, err := read_target_file(os.args[2])
    msg_panic_if(err, Error.NonExistError, "Given target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
    msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
    msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

    depend_list := construct_depend_list(target_file)
    defer delete(depend_list)

    for depend_target_file in depend_list {compile(depend_target_file)}
    for depend_target_file in depend_list {
        err = close_target_file(depend_target_file)
        msg_panic_if(err, Error.CloseError, "Cannot close tango file.")
    }
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

    include, err := get_dir_path(os.args[3])
    msg_panic_if(err, Error.NotDirError, "Target directory must be a path to a folder.")
    msg_panic_if(err, Error.AbsPathError, "Cannot determine absolute path to directory.")

    target_file: TargetFile
    target_file, err = read_target_file(os.args[2])
    msg_panic_if(err, Error.NonExistError, "Given target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
    msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
    msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

    if slice.contains(target_file.includes[:], include) {msg_panic("Include path was already added to target.")}
    append(&target_file.includes, include)

    err = write_target_file(target_file)
    msg_panic_if(err, Error.WriteError, "Cannot write to tango file.")

    err = close_target_file(target_file)
    msg_panic_if(err, Error.CloseError, "Cannot close tango file.")
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
    msg_panic_if(err, Error.NonExistError, "Given target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
    msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
    msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

    lib_path := os.args[3]
    if strings.contains(os.args[3], "target:") {
        if !possible_target_name(os.args[3][7:]) {
            msg_panic(
                "The second target name must consist of only engish letters and arabic digits. " +
                "The leading character must be a letter.",
            )
        }
        lib_target_file: TargetFile
        lib_target_file, err = read_target_file(os.args[3][7:])
        msg_panic_if(err, Error.NonExistError, "Second target does not exists.")
        msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
        msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
        msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

        if !slice.contains(target_file.depends[:], os.args[3][7:]) {
            append(&target_file.depends, os.args[3][7:])
        }

        if lib_target_file.type == "static" && os.args[4] == "--static" {
            lib_path = fmt.tprintf("%s/lib%s.a", lib_target_file.directory, lib_target_file.name)
        }
         else if lib_target_file.type == "shared" && (os.args[4] == "--absolute" || os.args[4] == "--relative") {
            lib_path = fmt.tprintf("%s/lib%s.dylib", lib_target_file.directory, lib_target_file.name)
        }
         else {
            msg_panic("Provided linking target is not a static or shared target.")
        }

        err = close_target_file(lib_target_file)
        msg_panic_if(err, Error.CloseError, "Cannot close tango file.")
    }
     else if strings.contains(os.args[3], "system:") {
        if os.args[4] != "--absolute" {msg_panic("System libraries have to be linked with the absolute path.")}
        lib_path = fmt.tprintf("system/lib%s.dylib", os.args[3][7:])
    }
     else {
        lib_path, err = get_file_path_if(lib_path, {".a", ".dylib", ".so"})
        msg_panic_if(err, Error.NotFileError, "Given library does not exist.")
        msg_panic_if(err, Error.AbsPathError, "Cannot determine absolute path to library.")
        msg_panic_if(err, Error.WrongTypeError, "Given file is not a library file.")
        if (os.args[4] == "--static" && path.ext(lib_path) != ".a") ||
           (os.args[4] == "--relative" && (path.ext(lib_path) != ".dylib" && path.ext(lib_path) != ".so")) {
            msg_panic(
                "Static libraries must be linked with --static option" +
                "and shared libraries with either --absolute or --relative option.",
            )
        }
    }

    switch os.args[4] 
    {
    case "--static":
        if !slice.contains(target_file.archives[:], lib_path) {
            append(&target_file.archives, lib_path)
        }
    case "--absolute":
        lib := Library{path.stem(path.base(lib_path))[3:], path.dir(lib_path), "absolute"}
        if !slice.contains(target_file.libraries[:], lib) {
            append(&target_file.libraries, lib)
        }
    case "--relative":
        lib := Library{path.stem(path.base(lib_path))[3:], path.dir(lib_path), "relative"}
        if !slice.contains(target_file.libraries[:], lib) {
            append(&target_file.libraries, lib)
        }
    case:
        msg_panic("Option has to --static, --absolute or --relative")
    }

    err = write_target_file(target_file)
    msg_panic_if(err, Error.WriteError, "Cannot write to tango file.")

    err = close_target_file(target_file)
    msg_panic_if(err, Error.CloseError, "Cannot close tango file.")
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

    if os.args[2] == os.args[3] {
        msg_panic("Target cannot depend on itself.")
    }

    target_file, err := read_target_file(os.args[2])
    msg_panic_if(err, Error.NonExistError, "Given target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
    msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
    msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

    depend_target_file: TargetFile
    depend_target_file, err = read_target_file(os.args[3])
    msg_panic_if(err, Error.NonExistError, "Dependency target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open dependency tango file.")

    err = close_target_file(depend_target_file)
    msg_panic_if(err, Error.CloseError, "Cannot close dependency tango file.")

    if slice.contains(target_file.depends[:], os.args[3]) {
        msg_panic("Given dependecy target is already added to target.")
    }
    append(&target_file.depends, os.args[3])

    err = write_target_file(target_file)
    msg_panic_if(err, Error.WriteError, "Cannot write to tango file.")

    err = close_target_file(target_file)
    msg_panic_if(err, Error.CloseError, "Cannot close tango file.")
}

exec_log_cmd :: proc() {
    if len(os.args) != 3 {print_desc_panic(LOG_CMD_DESC)}
    if os.args[2] == "--help" {print_desc_exit(LOG_CMD_DESC)}

    if !possible_target_name(os.args[2]) {
        msg_panic(
            "The target name must consist of only engish letters and arabic digits. " +
            "The leading character must be a letter.",
        )
    }

    target_file, err := read_target_file(os.args[2])
    msg_panic_if(err, Error.NonExistError, "Given target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
    msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
    msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

    err = close_target_file(target_file)
    msg_panic_if(err, Error.CloseError, "Cannot close tango file.")

    target_type := ""
    switch target_file.type {
    case "exec":
        target_type = "Executable"
    case "shared":
        target_type = "Shared library"
    case "static":
        target_type = "Static library"
    }

    log_source := log_hashed_elems(target_file.source[:])
    source := ""
    if len(target_file.source) == 0 {source = "[]"}
     else {source = fmt.tprintf("%s", strings.join(log_source, ",\n                         "))}

    log_src_dir := log_hashed_elems(target_file.src_dir[:])
    src_dir := ""
    if len(target_file.src_dir) == 0 {src_dir = "[]"}
     else {src_dir = fmt.tprintf(
            "\033[0;34m%s\033[0m",
            strings.join(log_src_dir, "\033[0m,\n                         \033[0;34m"),
        )}

    log_includes := log_hashed_elems(target_file.includes[:])
    includes := ""
    if len(target_file.includes) == 0 {includes = "[]"}
     else {includes = fmt.tprintf(
            "\033[0;34m%s\033[0m",
            strings.join(log_includes, "\033[0m,\n                         \033[0;34m"),
        )}

    log_archives := log_hashed_elems(target_file.archives[:])
    archives := ""
    if len(target_file.archives) == 0 {archives = "[]"}
     else {archives = fmt.tprintf("%s", strings.join(log_archives, ",\n                         "))}

    log_depends := log_hashed_elems(target_file.depends[:])
    depends := ""
    if len(target_file.depends) == 0 {depends = "[]"}
     else {depends = fmt.tprintf(
            "\033[0;33m%s\033[0m",
            strings.join(log_depends, "\033[0m,\n                         \033[0;33m"),
        )}

    log_libraries := log_hashed_lib_elems(target_file.libraries[:], target_file.directory)
    libraries := ""
    if len(target_file.libraries) == 0 {libraries = "[]"}
     else {libraries = fmt.tprintf("%s", strings.join(log_libraries, ",\n                         "))}

    fmt.printf(
        "Logged target:           \033[0;33m%s\033[0m\n" +
        "Compile destination:     \033[0;34m%s\033[0m\n" +
        "Target type:             %s\n" +
        "C source files:          %s\n" +
        "C source directory:      %s\n" +
        "Include paths:           %s\n" +
        "Linked static libraries: %s\n" +
        "Linked shared libraries: %s\n" +
        "Target dependecies:      %s\n",
        target_file.name,
        target_file.directory,
        target_type,
        source,
        src_dir,
        includes,
        archives,
        libraries,
        depends,
    )
}

exec_ls_cmd :: proc() {
    if len(os.args) != 2 {
        if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(LS_CMD_DESC)}
        print_desc_panic(LS_CMD_DESC)
    }

    cwd := os.get_current_directory()
    if !os.is_dir(fmt.tprintf("%s/.tango", cwd)) {
        msg_panic("Current directory is not initialised to tango.")
    }

    target_files_paths, match_err := path.glob(fmt.tprintf("%s/.tango/*.tango", cwd))
    if match_err != path.Match_Error.None {msg_panic("Cannot read .tango directory.")}

    target_files := make([]TargetFile, len(target_files_paths))
    for target_file_path, i in target_files_paths {
        target_name := path.stem(path.base(target_file_path))
        file, err := read_target_file(target_name)
        msg_panic_if(err, Error.NonExistError, "%s target does not exists.", target_name)
        msg_panic_if(err, Error.OpenError, "Cannot open %s tango file.", target_name)
        msg_panic_if(err, Error.ReadError, "Cannot read %s tango file contents.", target_name)
        msg_panic_if(err, Error.ParseError, "Cannot parse %s tango file contents.", target_name)

        err = close_target_file(file)
        msg_panic_if(err, Error.CloseError, "Cannot close %s tango file.", target_name)
        target_files[i] = file
    }

    output := ""
    for target_file in target_files {
        output = fmt.tprintf("%s%s", output, target_file.name)
        if len(target_file.depends) > 0 {
            output = fmt.tprintf("%s -> %s", output, strings.join(target_file.depends[:], ", "))
        }
        output = fmt.tprintf("%s\n", output)
    }

    fmt.printf("%s", output)
}

exec_rm_cmd :: proc() {
    force := false
    if len(os.args) == 5 && os.args[4] == "--force" {
        force = true
    }
     else if len(os.args) != 4 {
        if len(os.args) == 3 && os.args[2] == "--help" {print_desc_exit(RM_CMD_DESC)}
        print_desc_panic(RM_CMD_DESC)
    }

    if !possible_target_name(os.args[2]) {
        msg_panic(
            "The target name must consist of only engish letters and arabic digits. " +
            "The leading character must be a letter.",
        )
    }

    target_file, err := read_target_file(os.args[2])
    msg_panic_if(err, Error.NonExistError, "Given target does not exists.")
    msg_panic_if(err, Error.OpenError, "Cannot open tango file.")
    msg_panic_if(err, Error.ReadError, "Cannot read tango file contents.")
    msg_panic_if(err, Error.ParseError, "Cannot parse tango file contents.")

    rm_hash, ok := strconv.parse_u64_of_base(os.args[3], 16)
    if !ok {msg_panic("Second argument is not a valid hash.")}

    source_hash := hash_elems(target_file.source[:])
    src_dir_hash := hash_elems(target_file.src_dir[:])
    includes_hash := hash_elems(target_file.includes[:])
    archives_hash := hash_elems(target_file.archives[:])
    libraries_hash := hash_lib_elems(target_file.libraries[:])
    depends_hash := hash_elems(target_file.depends[:])

    for h, i in source_hash {
        if h == rm_hash {
            unordered_remove(&target_file.source, i)
            write_and_close(target_file)
            return
        }
    }

    for h, i in src_dir_hash {
        if h == rm_hash {
            unordered_remove(&target_file.src_dir, i)
            write_and_close(target_file)
            return
        }
    }

    for h, i in includes_hash {
        if h == rm_hash {
            unordered_remove(&target_file.includes, i)
            write_and_close(target_file)
            return
        }
    }

    for h, i in archives_hash {
        if h == rm_hash {
            unordered_remove(&target_file.archives, i)
            write_and_close(target_file)
            return
        }
    }

    for h, i in libraries_hash {
        if h == rm_hash {
            unordered_remove(&target_file.libraries, i)
            write_and_close(target_file)
            return
        }
    }

    for h, i in depends_hash {
        if h == rm_hash {
            if !force {
                depend_target_file: TargetFile
                depend_target_file, err = read_target_file(target_file.depends[i])
                msg_panic_if(
                    err,
                    Error.NonExistError,
                    "Target corresponding to the hash does not exists. To remove add --force option.",
                )
                msg_panic_if(err, Error.OpenError, "Cannot open dependency tango file. To remove add --force option.")
                msg_panic_if(
                    err,
                    Error.ReadError,
                    "Cannot read dependency tango file contents. To remove add --force option.",
                )
                msg_panic_if(
                    err,
                    Error.ParseError,
                    "Cannot parse dependency tango file contents. To remove add --force option.",
                )

                if depend_target_file.type == "static" {
                    depend_archive := fmt.tprint("%s/lib%s.a", depend_target_file.directory, depend_target_file.name)
                    for archive in target_file.archives {
                        if archive == depend_archive {
                            msg_panic(
                                "Cannot remove dependency because it is required to build the static library: %s. " +
                                "To remove anyway add --force option.",
                                archive,
                            )
                        }
                    }
                }
                if depend_target_file.type == "shared" {
                    for lib in target_file.libraries {
                        if lib.name == depend_target_file.name && lib.abs_path == depend_target_file.directory {
                            rel_path, rel_err := path.rel(target_file.directory, lib.abs_path)
                            if rel_err != path.Relative_Error.None {msg_panic("Cannot determine relative path.")}
                            path := lib.abs_path
                            if lib.link_opts == "relative" {
                                path = fmt.tprintf("@executable_path/%s", rel_path)
                            }
                            msg_panic(
                                "Cannot remove dependency because it is required to build the shared library: %s. " +
                                "To remove anyway add --force option.",
                                fmt.tprintf("%s/lib%s.dylib", path, lib.name),
                            )
                        }
                    }
                }
            }
            unordered_remove(&target_file.depends, i)
            write_and_close(target_file)
            return
        }
    }

    msg_panic("Remove hash does not correspond to any compilation element of given target.")
}
