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
    AbsPathError,
    WrongTypeError,
    AlreadyInitError,
}

init_tango :: proc() -> Error {
    cwd := os.get_current_directory()
    tango_dir := fmt.tprintf("%s/.tango", cwd)
    if os.is_dir(tango_dir) {return Error.AlreadyInitError}
    os.make_directory(tango_dir, 0o0755)
    return Error.None
}

write_and_close :: proc(target_file: TargetFile) {
    err := write_target_file(target_file)
    msg_panic_if(err, .WriteError, "Cannot write to tango file.")

    err = close_target_file(target_file)
    msg_panic_if(err, .CloseError, "Cannot close tango file.")
}

construct_depend_list :: proc(target_file: TargetFile) -> [dynamic]TargetFile {
    depend_list := make([dynamic]TargetFile)
    defer delete(depend_list)
    append(&depend_list, target_file)
    open_depends(target_file.depends, &depend_list)

    sorted_depend_list := make([dynamic]TargetFile)
    sort_depend_list(&sorted_depend_list, &depend_list)

    return sorted_depend_list
}

open_depends :: proc(depends: [dynamic]string, depend_list: ^[dynamic]TargetFile) {
    for depend in depends {
        depend_target_file, err := read_target_file(depend)
        msg_panic_if(err, Error.NonExistError, "Target %s does not exists.", depend)
        msg_panic_if(err, Error.OpenError, "Cannot open %s tango file.", depend)
        msg_panic_if(err, Error.ReadError, "Cannot read %s tango file contents.", depend)
        msg_panic_if(err, Error.ParseError, "Cannot parse %s tango file contents.", depend)

        already_present := false
        for target_file in depend_list {
            if target_file.name == depend_target_file.name {already_present = true}
        }
        if !already_present {
            append(depend_list, depend_target_file)
        }
         else {
            err = close_target_file(depend_target_file)
            msg_panic_if(err, Error.CloseError, "Cannot close %s tango file.", depend)
        }

        open_depends(depend_target_file.depends, depend_list)
    }
}

sort_depend_list :: proc(sorted_depend_list: ^[dynamic]TargetFile, unsorted_remains: ^[dynamic]TargetFile) {
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

compile :: proc(target_file: TargetFile) {
    if target_file.type == "static" {
        compile_static(target_file)
        return
    }

    source := make([dynamic]string, 0, len(target_file.source))
    defer delete(source)
    append(&source, ..target_file.source[:])

    for dir in target_file.src_dir {
        source_files, err := path.glob(fmt.tprintf("%s/*.c", dir))
        if err != path.Match_Error.None {msg_panic("Cannot read source directory %s.", dir)}
        append(&source, ..source_files)
    }

    cmd := "gcc"

    if len(source) < 1 {msg_panic("Target has to have at least one source file to be compiled")}
    cmd = fmt.tprintf("%s %s", cmd, strings.join(source[:], " "))

    if len(target_file.archives) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(target_file.archives[:], " "))
    }

    if target_file.type == "exec" {
        cmd = fmt.tprintf(
            "%s -o %s/%s",
            /* -Wall -Werror" */ // TODO: Add an options field to TargetFile structure and also add an comp-opts command to tango so the user can decide what compile options to use
            cmd,
            target_file.directory,
            target_file.name,
        )
    }

    if target_file.type == "shared" {
        cmd = fmt.tprintf(
            "%s -o %s/lib%s.dylib -dynamiclib",
            /* -Wall -Werror" */
            cmd,
            target_file.directory,
            target_file.name,
        )
    }

    if len(target_file.includes) > 0 {
        cmd = fmt.tprintf("%s -I%s", cmd, strings.join(target_file.includes[:], " -I"))
    }

    if len(target_file.libraries) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(wlist_libraries(target_file.libraries[:])[:], " "))
    }

    fmt.println(cmd)
    libc.system(strings.clone_to_cstring(cmd))

    for lib in target_file.libraries {
        if lib.abs_path == "system" {continue}
        install_name := get_install_name(lib)
        install_cmd := "install_name_tool -change"
        switch lib.link_opts {
        case "absolute":
            install_cmd = fmt.tprintf("%s %s %s/lib%s.dylib", install_cmd, install_name, lib.abs_path, lib.name)
        case "relative":
            rel_path, rel_err := path.rel(target_file.directory, lib.abs_path)
            if rel_err !=
               path.Relative_Error.None {msg_panic("Cannot determine relative path between executable and library.")}
            install_cmd = fmt.tprintf(
                "%s %s @executable_path/%s/lib%s.dylib",
                install_cmd,
                install_name,
                rel_path,
                lib.name,
            )
        }
        if target_file.type == "exec" {
            install_cmd = fmt.tprintf("%s %s/%s", install_cmd, target_file.directory, target_file.name)
        }
        if target_file.type == "shared" {
            install_cmd = fmt.tprintf("%s %s/lib%s.dylib", install_cmd, target_file.directory, target_file.name)
        }
        fmt.println(install_cmd)
        libc.system(strings.clone_to_cstring(install_cmd))
    }
}

compile_static :: proc(target_file: TargetFile) {
    gcc_cmd := "gcc"

    source := make([dynamic]string, 0, len(target_file.source))
    defer delete(source)
    append(&source, ..target_file.source[:])

    for dir in target_file.src_dir {
        source_files, err := path.glob(fmt.tprintf("%s/*.c", dir))
        if err != path.Match_Error.None {msg_panic("Cannot read source directory %s.", dir)}
        append(&source, ..source_files)
    }

    if len(source) < 1 {msg_panic("Target has to have at least one source file to be compiled.")}

    object_files := make([]string, len(source))
    for src, i in source {
        object_files[i] = fmt.tprintf("%s.o", path.stem(target_file.source[i]))
    }
    gcc_cmd = fmt.tprintf(
        "%s %s -c",
        /* -Wall -Werror" */
        gcc_cmd,
        strings.join(source[:], " "),
    )

    if len(target_file.includes) > 0 {
        gcc_cmd = fmt.tprintf("%s -I%s", gcc_cmd, strings.join(target_file.includes[:], " -I"))
    }

    lib_cmd := "libtool -static -o"
    lib_cmd = fmt.tprintf(
        "%s %s/lib%s.a %s",
        lib_cmd,
        target_file.directory,
        target_file.name,
        strings.join(object_files, " "),
    )

    lib_cmd = fmt.tprintf("%s %s", lib_cmd, strings.join(target_file.archives[:], " "))

    if len(target_file.libraries) > 0 {
        lib_cmd = fmt.tprintf("%s %s", lib_cmd, strings.join(wlist_libraries(target_file.libraries[:])[:], " "))
    }

    fmt.println(gcc_cmd)
    libc.system(strings.clone_to_cstring(gcc_cmd))
    fmt.println(lib_cmd)
    libc.system(strings.clone_to_cstring(lib_cmd))

    rm_cmd := fmt.tprintf("rm %s", strings.join(object_files, " "))
    libc.system(strings.clone_to_cstring(rm_cmd))

    for lib in target_file.libraries {
        if lib.abs_path == "system" {continue}
        install_name := get_install_name(lib)
        install_cmd := "install_name_tool -change"
        switch lib.link_opts {
        case "absolute":
            install_cmd = fmt.tprintf("%s %s %s/lib%s.dylib", install_cmd, install_name, lib.abs_path, lib.name)
        case "relative":
            rel_path, rel_err := path.rel(target_file.directory, lib.abs_path)
            if rel_err !=
               path.Relative_Error.None {msg_panic("Cannot determine relative path between executable and library.")}
            install_cmd = fmt.tprintf(
                "%s %s @executable_path/%s/lib%s.dylib",
                install_cmd,
                install_name,
                rel_path,
                lib.name,
            )
        }
        install_cmd = fmt.tprintf("%s %s/lib%s.a", install_cmd, target_file.directory, target_file.name)
        fmt.println(install_cmd)
        libc.system(strings.clone_to_cstring(install_cmd))
    }
}

get_install_name :: proc(lib: Library) -> string {
    otool_cmd := fmt.tprintf("otool -D %s/lib%s.dylib | tr '\n' ' '", lib.abs_path, lib.name)
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
        wl := fmt.tprintf("-L %s -l %s", lib.abs_path, lib.name)
        if lib.abs_path == "system" {wl = fmt.tprintf("-l %s", lib.name)}
        wls[i] = wl
    }
    return wls
}

write_libraries :: proc(libs: []Library) -> []string {
    fmts := make([]string, len(libs))
    for lib, i in libs {
        lib_fmt := fmt.tprintf("%s %s %s", lib.name, lib.abs_path, lib.link_opts)
        fmts[i] = lib_fmt
    }

    return fmts
}

hash_elems :: proc(elems: []string) -> []u64 {
    hashes := make([]u64, len(elems))
    for elem, i in elems {
        hashes[i] = hash.murmur64a(transmute([]u8)elem)
    }
    return hashes
}

log_hashed_elems :: proc(elems: []string) -> []string {
    hashes := hash_elems(elems)
    results := make([]string, len(elems))
    for elem, i in elems {
        results[i] = fmt.tprintf("%s \033[0m[\033[0;35m%x\033[0m]", elem, hashes[i])
    }
    return results
}

hash_lib_elems :: proc(elems: []Library) -> []u64 {
    hashes := make([]u64, len(elems))
    for elem, i in elems {
        hashes[i] = hash.murmur64a(transmute([]u8)fmt.tprintf("%s %s %s", elem.abs_path, elem.name, elem.link_opts))
    }
    return hashes
}

log_hashed_lib_elems :: proc(elems: []Library, target_path: string) -> []string {
    hashes := hash_lib_elems(elems)
    results := make([]string, len(elems))
    for elem, i in elems {
        if elem.abs_path == "system" {
            results[i] = fmt.tprintf("\033[0;31mSystem:lib%s \033[0m[\033[0;35m%x\033[0m]", elem.name, hashes[i])
            continue
        }

        rel_path, err := path.rel(target_path, elem.abs_path)
        if err != path.Relative_Error.None {msg_panic("Cannot determine relative path.")}
        path := fmt.tprintf("@executable_path/%s", rel_path)

        if elem.link_opts == "absolute" {path = elem.abs_path}
        results[i] = fmt.tprintf("\033[0;31m%s/lib%s.dylib \033[0m[\033[0;35m%x\033[0m]", path, elem.name, hashes[i])
    }
    return results
}

possible_target_name :: proc(name: string) -> bool {
    letters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    digits := "0123456789"
    for c, i in name {
        if !strings.contains_rune(letters, c) && !(strings.contains_rune(digits, c) && i > 0) {return false}
    }
    return true
}

get_dir_path :: proc(partial_path: string) -> (string, Error) {
    if !os.is_dir(partial_path) {return "", Error.NotDirError}
    abs_path, ok := path.abs(partial_path)
    if !ok {return "", Error.AbsPathError}
    return abs_path, Error.None
}

get_file_path_if :: proc(partial_path: string, file_type: []string) -> (string, Error) {
    if !os.is_file(partial_path) {return "", Error.NotFileError}
    abs_path, ok := path.abs(partial_path)
    if !ok {return "", Error.AbsPathError}
    if !slice.contains(file_type, path.ext(abs_path)) {return "", Error.WrongTypeError}
    return abs_path, Error.None
}
