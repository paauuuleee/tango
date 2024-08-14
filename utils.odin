package main

import "core:c/libc"
import "core:fmt"
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
    AbsPathError,
    WrongTypeError,
}

compile :: proc(target_file: TargetFile) {
    cmd := "gcc"

    if len(target_file.source) < 1 {msg_panic("Target has to have one source file to be compiled")}
    cmd = fmt.tprintf("%s %s", cmd, strings.join(target_file.source[:], " "))

    if target_file.type == "exec" {
        cmd = fmt.tprintf("%s -o %s/%s ", cmd, target_file.directory, target_file.name)
    }

    if target_file.type == "static" {
        cmd = fmt.tprintf("%s -o %s/lib%s.a -static", cmd, target_file.directory, target_file.name)
    }

    if target_file.type == "shared" {
        cmd = fmt.tprintf("%s -o %s/lib%s.dylib -dynamiclib ", cmd, target_file.directory, target_file.name)
    }

    if len(target_file.includes) > 0 {
        cmd = fmt.tprintf("%s -I%s/", cmd, strings.join(target_file.includes[:], "/ -I"))
    }

    if len(target_file.libraries) > 0 {
        cmd = fmt.tprintf("%s %s", cmd, strings.join(wlist_libraries(target_file.libraries[:])[:], " "))
    }

    fmt.println(cmd)
    libc.system(strings.clone_to_cstring(cmd))

    for lib in target_file.libraries {
        install_cmd := "install_name_tool -change"
        switch lib.link_opts {
        case "absolute":
            install_cmd = fmt.tprintf("%s lib%s.dylib %s/lib%s.dylib", install_cmd, lib.name, lib.abs_path, lib.name)
        case "relative":
            rel_path, rel_err := path.rel(target_file.directory, lib.abs_path)
            if rel_err != .None {msg_panic("Cannot determine relative path between executable and library.")}
            install_cmd = fmt.tprintf(
                "%s lib%s.dylib @executable_path/%s/lib%s.dylib",
                install_cmd,
                lib.name,
                rel_path,
                lib.name,
            )
        }
        install_cmd = fmt.tprintf("%s %s", install_cmd, target_file.name)
        fmt.println(install_cmd)
        libc.system(strings.clone_to_cstring(install_cmd))
    }

    err := close_target_file(target_file)
    msg_panic_if(err, .CloseError, "Cannot close tango file.")
}


wlist_libraries :: proc(libs: []Library) -> []string {
    wls := make([]string, len(libs))
    for lib, i in libs {
        wl := fmt.tprintf("-L %s -l %s", lib.abs_path, lib.name)
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

possible_target_name :: proc(name: string) -> bool {
    letters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    digits := "0123456789"
    for c, i in name {
        if !strings.contains_rune(letters, c) && !(strings.contains_rune(digits, c) && i > 0) {return false}
    }
    return true
}

get_dir_path :: proc(partial_path: string) -> (string, Error) {
    if !os.is_dir(partial_path) {return "", .NotDirError}
    abs_path, ok := path.abs(partial_path)
    if !ok {return "", .AbsPathError}
    return abs_path, .None
}

get_file_path_if :: proc(partial_path: string, file_type: []string) -> (string, Error) {
    if !os.is_file(partial_path) {return "", .NotFileError}
    abs_path, ok := path.abs(partial_path)
    if !ok {return "", .AbsPathError}
    if !slice.contains(file_type, path.ext(abs_path)) {return "", .WrongTypeError}
    return abs_path, .None
}
