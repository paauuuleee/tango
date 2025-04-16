package main

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:hash"
import "core:os"
import path "core:path/filepath"
import "core:slice"
import "core:strings"

when ODIN_OS == .Windows {
    foreign import libc "system:libucrt.lib"
    POPEN_NAME :: "_popen"
    PCLOSE_NAME :: "_pclose"
} else when ODIN_OS == .Darwin {
    foreign import lib "system:System.framework"
    POPEN_NAME :: "popen"
    PCLOSE_NAME :: "pclose"
} else {
    foreign import lib "system:c"
    POPEN_NAME :: "popen"
    PCLOSE_NAME :: "pclose"
}

@(default_calling_convention = "c")
foreign lib {
    @(link_name = POPEN_NAME)
    popen :: proc(command: cstring, mode: cstring) -> ^libc.FILE ---
    @(link_name = PCLOSE_NAME)
    pclose :: proc(stream: ^libc.FILE) -> c.int ---
}

// Error :: enum {
//     None,
//     ExistError,
//     NonExistError,
//     ReadError,
//     WriteError,
//     OpenError,
//     CloseError,
//     CreateError,
//     ParseError,
//     NotDirError,
//     NotFileError,
//     AbsPathError,
//     WrongTypeError,
//     AlreadyInitError,
// }

// init_tango :: proc() -> Error {
//     cwd := os.get_current_directory()
//     tango_dir := fmt.tprintf("%s/.tango", cwd)
//     if os.is_dir(tango_dir) {return Error.AlreadyInitError}
//     os.make_directory(tango_dir, 0o0755)
//     return Error.None
// }

// write_and_close :: proc(target_file: TargetFile) {
//     err := write_target_file(target_file)
//     msg_panic_if(err, .WriteError, "Cannot write to tango file.")
//
//     err = close_target_file(target_file)
//     msg_panic_if(err, .CloseError, "Cannot close tango file.")
// }

construct_depend_list :: proc(target_name: string, targets: map[string]Target) -> [dynamic]Target {
    depend_list := get_depends(target_name, targets)
    defer delete(depend_list)

    sorted_depend_list := make([dynamic]Target, 0, len(depend_list))
    sort_depend_list(&sorted_depend_list, &depend_list)

    return sorted_depend_list
}

get_depends :: proc(target_name: string, targets: map[string]Target) -> [dynamic]Target {
    depends_map := make_map_cap(map[string]Target, cap(targets))
    depends_map[target_name] = targets[target_name]
    depend_names := make([dynamic]string, 0, 100)
    new_depend_names := make([dynamic]string, 0, 100)
    append_elems(&depend_names, ..targets[target_name].depends)
    for {
        added_new := false
        for name in depend_names {
            target := targets[name]
            if name not_in depends_map {
                depends_map[name] = target
                append_elems(&new_depend_names, ..target.depends)
                added_new = true
            }
        }

        depend_names, new_depend_names = new_depend_names, depend_names
        clear_dynamic_array(&new_depend_names)
        if !added_new || len(depend_names) == 0 {break}
    }

    delete(new_depend_names)
    delete(depend_names)

    depends := make([dynamic]Target, 0, len(depends_map))

    for _, target in depends_map {
        append(&depends, target)
    }

    delete(depends_map)
    return depends
}

// open_depends :: proc(depends: [dynamic]string, depend_list: ^[dynamic]TargetFile) {
//     for depend in depends {
//         depend_target_file, err := read_target_file(depend)
//         msg_panic_if(err, Error.NonExistError, "Target %s does not exists.", depend)
//         msg_panic_if(err, Error.OpenError, "Cannot open %s tango file.", depend)
//         msg_panic_if(err, Error.ReadError, "Cannot read %s tango file contents.", depend)
//         msg_panic_if(err, Error.ParseError, "Cannot parse %s tango file contents.", depend)
//
//         already_present := false
//         for target_file in depend_list {
//             if target_file.name == depend_target_file.name {already_present = true}
//         }
//         if !already_present {
//             append(depend_list, depend_target_file)
//         }
//          else {
//             err = close_target_file(depend_target_file)
//             msg_panic_if(err, Error.CloseError, "Cannot close %s tango file.", depend)
//         }
//
//         open_depends(depend_target_file.depends, depend_list)
//     }
// }

sort_depend_list :: proc(sorted_depend_list: ^[dynamic]Target, unsorted_remains: ^[dynamic]Target) {
    if len(unsorted_remains) == 0 {return}
    if len(sorted_depend_list) == 0 {
        remove_indecies := make([dynamic]int)
        defer delete(remove_indecies)
        for remain, i in unsorted_remains {
            if len(remain.depends) == 0 {

                append(sorted_depend_list, remain)
                append(&remove_indecies, i)
            }
        }

        if len(remove_indecies) == 0 {
            msg_panic("Targets cannot cyclically depend on each other.")
        }

        slice.reverse_sort(remove_indecies[:])
        remove_indecies_slice := slice.unique(remove_indecies[:])
        for remove_index in remove_indecies_slice {
            unordered_remove(unsorted_remains, remove_index)
        }

        sort_depend_list(sorted_depend_list, unsorted_remains)
        return
    }

    remove_indecies := make([dynamic]int)
    defer delete(remove_indecies)
    for remain, i in unsorted_remains {
        forward_depend := true
        for depend in remain.depends {
            depend_found := false
            for sorted_depend in sorted_depend_list {
                if depend == sorted_depend.name {
                    depend_found = true
                }
            }
            forward_depend = depend_found
        }
        if forward_depend {
            append(sorted_depend_list, remain)
            append(&remove_indecies, i)
        }
    }

    if len(remove_indecies) == 0 {
        msg_panic("Targets cannot cyclically depend on each other.")
    }

    slice.reverse_sort(remove_indecies[:])
    remove_indecies_slice := slice.unique(remove_indecies[:])
    for remove_index in remove_indecies_slice {
        unordered_remove(unsorted_remains, remove_index)
    }

    sort_depend_list(sorted_depend_list, unsorted_remains)
}

compile :: proc(target: Target) {
    objects, rm_cmd := compile_objects(target)

    fmt.println("Hallo")

    switch target.type {
    case "shared":
        compile_shared(target, objects)
    case "static":
        compile_static(target, objects)
    case "exec":
        compile_exec(target, objects)
    }

    msg_note("Removing object files. [%s]", rm_cmd)
    libc.system(strings.clone_to_cstring(rm_cmd))

    for lib in target.libraries {
        if strings.has_prefix(lib.path, "system") {continue}
        install_name := get_install_name(lib)
        install_cmd := "install_name_tool -change"
        switch lib.link_opts {
        case "absolute":
            install_cmd = fmt.tprintf("%s %s %s", install_cmd, install_name, lib.path)
        case "relative":
            rel_path, rel_err := path.rel(target.directory, lib.path)
            if rel_err !=
               path.Relative_Error.None {msg_panic("Cannot determine relative path between executable and library.")}
            install_cmd = fmt.tprintf("%s %s @executable_path/%s", install_cmd, install_name, rel_path)
        }
        binary: string
        switch target.type {
        case "exec":
            binary = fmt.tprintf("%s/%s", target.directory, target.name)
        case "shared":
            binary = fmt.tprintf("%s/lib%s.dylib", target.directory, target.name)
        case "static":
            binary = fmt.tprintf("%s/lib%s.a", target.directory, target.name)
        }
        install_cmd = fmt.tprintf("%s %s", install_cmd, binary)
        msg_note("Changing the dynamic library search path. [%s]", install_cmd)
        libc.system(strings.clone_to_cstring(install_cmd))
    }
}

compile_shared :: proc(target: Target, objects: []string) {
    cmd := "clang -shared"
    cmd = fmt.tprintf("%s %s", cmd, strings.join(objects[:], " "))

    if len(target.archives) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(target.archives[:], " "))
    }

    cmd = fmt.tprintf("%s -o %s/lib%s.dylib", cmd, target.directory, target.name)

    if len(target.libraries) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(wlist_libraries(target.libraries[:])[:], " "))
    }

    msg_note("Linking the final dynamic library. [%s]", cmd)
    libc.system(strings.clone_to_cstring(cmd))
}

compile_exec :: proc(target: Target, objects: []string) {
    cmd := "clang"
    cmd = fmt.tprintf("%s %s", cmd, strings.join(objects[:], " "))

    if len(target.archives) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(target.archives[:], " "))
    }

    cmd = fmt.tprintf("%s -o %s/%s", cmd, target.directory, target.name)

    if len(target.libraries) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(wlist_libraries(target.libraries[:])[:], " "))
    }

    msg_note("Linking the final executable. [%s]", cmd)
    libc.system(strings.clone_to_cstring(cmd))
}

compile_static :: proc(target: Target, objects: []string) {
    cmd := "libtool -static -o"
    cmd = fmt.tprintf("%s %s/lib%s.a %s", cmd, target.directory, target.name, strings.join(objects, " "))

    if len(target.archives) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(target.archives[:], " "))
    }

    if len(target.libraries) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(wlist_libraries(target.libraries[:])[:], " "))
    }

    msg_note("Linking the final archive file. [%s]", cmd)
    libc.system(strings.clone_to_cstring(cmd))
}

compile_objects :: proc(target: Target) -> ([]string, string) {
    cc_cmd := "gcc"

    sources := make([dynamic]string)
    defer delete(sources)
    append_elems(&sources, ..target.source)
    fmt.println(target.source[0])

    for dir in target.src_dir {
        source_files, err := path.glob(fmt.tprintf("%s/*.c", dir))
        if err != path.Match_Error.None {msg_panic("Cannot read source directory %s.", dir)}
        append_elems(&sources, ..source_files)
    }

    if len(sources) < 1 {msg_panic("Target has to have at least one source file to be compiled.")}

    objects := make([dynamic]string)

    for source in sources {
        // append(&objects, "hallo")
        // fmt.println(source)

        stem := path.stem(source)
        fmt.println("Haloo")

        // str := fmt.tprintf("%s.0", path.stem(strings.clone(source)))
        // append(&objects, fmt.tprintf("%s.0", path.stem(source)))
        fmt.println("Haloo")

    }

    rm_cmd := fmt.tprintf("rm %s", strings.join(objects[:], " "))
    fmt.println("Haloo")


    cc_cmd = fmt.tprintf("%s %s -c", cc_cmd, strings.join(sources[:], " "))
    fmt.println("Haloo")

    if len(target.includes) > 0 {
        cc_cmd = fmt.tprintf("%s -I%s", cc_cmd, strings.join(target.includes[:], " -I"))
    }

    msg_note("Compile c source files to object files. [%s]", cc_cmd)
    libc.system(strings.clone_to_cstring(cc_cmd))

    return objects[:], rm_cmd
}


get_install_name :: proc(lib: Library) -> string {
    otool_cmd := fmt.tprintf("otool -D %s | tr '\n' ' '", lib.path)
    fp := popen(strings.clone_to_cstring(otool_cmd), "r")

    size := i32(1024)
    data := make([]u8, size)
    if libc.fgets(raw_data(data), size, fp) == nil {
        msg_panic("Cannot determine library id name.")
    }

    if -1 == pclose(fp) {
        msg_panic("Cannot close pipe stream.")
    }
    install_name := strings.split(fmt.tprintf("%s", &data), " ")[1]
    return install_name
}

wlist_libraries :: proc(libs: []Library) -> []string {
    wls := make([]string, len(libs))
    for lib, i in libs {
        wl := fmt.tprintf("-L %s -l %s", path.dir(lib.path), path.stem(path.base(lib.path))[3:])
        if strings.has_prefix(lib.path, "system") {wl = fmt.tprintf("-l %s", path.stem(path.base(lib.path))[3:])}
        wls[i] = wl
    }
    return wls
}

// write_libraries :: proc(libs: []Library) -> []string {
//     fmts := make([]string, len(libs))
//     for lib, i in libs {
//         lib_fmt := fmt.tprintf("%s %s %s", lib.name, lib.abs_path, lib.link_opts)
//         fmts[i] = lib_fmt
//     }
//
//     return fmts
// }

// hash_elems :: proc(elems: []string) -> []u64 {
//     hashes := make([]u64, len(elems))
//     for elem, i in elems {
//         hashes[i] = hash.murmur64a(transmute([]u8)elem)
//     }
//     return hashes
// }

// log_hashed_elems :: proc(elems: []string) -> []string {
//     hashes := hash_elems(elems)
//     results := make([]string, len(elems))
//     for elem, i in elems {
//         results[i] = fmt.tprintf("%s \033[0m[\033[0;35m%x\033[0m]", elem, hashes[i])
//     }
//     return results
// }

// hash_lib_elems :: proc(elems: []Library) -> []u64 {
//     hashes := make([]u64, len(elems))
//     for elem, i in elems {
//         hashes[i] = hash.murmur64a(transmute([]u8)fmt.tprintf("%s %s %s", elem.abs_path, elem.name, elem.link_opts))
//     }
//     return hashes
// }

// log_hashed_lib_elems :: proc(elems: []Library, target_path: string) -> []string {
//     hashes := hash_lib_elems(elems)
//     results := make([]string, len(elems))
//     for elem, i in elems {
//         if elem.abs_path == "system" {
//             results[i] = fmt.tprintf("\033[0;31mSystem:lib%s \033[0m[\033[0;35m%x\033[0m]", elem.name, hashes[i])
//             continue
//         }
//
//         rel_path, err := path.rel(target_path, elem.abs_path)
//         if err != path.Relative_Error.None {msg_panic("Cannot determine relative path.")}
//         path := fmt.tprintf("@executable_path/%s", rel_path)
//
//         if elem.link_opts == "absolute" {path = elem.abs_path}
//         results[i] = fmt.tprintf("\033[0;31m%s/lib%s.dylib \033[0m[\033[0;35m%x\033[0m]", path, elem.name, hashes[i])
//     }
//     return results
// }

// possible_target_name :: proc(name: string) -> bool {
//     letters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
//     digits := "0123456789"
//     for c, i in name {
//         if !strings.contains_rune(letters, c) && !(strings.contains_rune(digits, c) && i > 0) {return false}
//     }
//     return true
// }

// get_dir_path :: proc(partial_path: string) -> (string, Error) {
//     if !os.is_dir(partial_path) {return "", Error.NotDirError}
//     abs_path, ok := path.abs(partial_path)
//     if !ok {return "", Error.AbsPathError}
//     return abs_path, Error.None
// }

get_file_path_if :: proc(partial_path: string, file_type: []string) -> (string, bool) {
    if !os.is_file(partial_path) {return "", false}
    abs_path, ok := path.abs(partial_path)
    if !ok {return "", false}
    if !slice.contains(file_type, path.ext(abs_path)) {return "", false}
    return abs_path, true
}
