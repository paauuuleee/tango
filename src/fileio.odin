package main

import "core:fmt"
import "core:os"
import "core:strings"

Library :: struct {
    name:      string,
    abs_path:  string,
    link_opts: string,
}

TargetFile :: struct {
    fd:        os.Handle,
    name:      string,
    directory: string,
    type:      string,
    source:    [dynamic]string,
    src_dir:   [dynamic]string,
    includes:  [dynamic]string,
    libraries: [dynamic]Library,
    archives:  [dynamic]string,
    depends:   [dynamic]string,
}

create_target_file :: proc(name, directory, type: string) -> (TargetFile, Error) {
    cwd := os.get_current_directory()
    tango_dir := fmt.tprintf("%s/.tango", cwd)
    if os.exists(fmt.tprintf("%s/%s.tango", tango_dir, name)) {return TargetFile{}, Error.ExistError}

    fd, errno := os.open(fmt.tprintf("%s/%s.tango", tango_dir, name), os.O_CREATE | os.O_RDWR, 0o0644)
    if errno != 0 {return TargetFile{}, Error.CreateError}

    return TargetFile{fd = fd, name = name, directory = directory, type = type}, Error.None
}

close_target_file :: proc(target_file: TargetFile) -> Error {
    if os.close(target_file.fd) != 0 {return Error.CloseError}
    return Error.None
}

write_target_file :: proc(target_file: TargetFile) -> Error {
    target_file_content := fmt.tprintf(
        "target %s\ndirectory %s\ntype %s\n",
        target_file.name,
        target_file.directory,
        target_file.type,
    )

    if len(target_file.source) > 0 {
        target_file_content = fmt.tprintf(
            "%ssource\n\t%s\n",
            target_file_content,
            strings.join(target_file.source[:], "\n\t"),
        )
    }

    if len(target_file.src_dir) > 0 {
        target_file_content = fmt.tprintf(
            "%ssrc-dir\n\t%s\n",
            target_file_content,
            strings.join(target_file.src_dir[:], "\n\t"),
        )
    }

    if len(target_file.includes) > 0 {
        target_file_content = fmt.tprintf(
            "%sincludes\n\t%s\n",
            target_file_content,
            strings.join(target_file.includes[:], "\n\t"),
        )
    }

    if len(target_file.archives) > 0 {
        target_file_content = fmt.tprintf(
            "%sarchives\n\t%s\n",
            target_file_content,
            strings.join(target_file.archives[:], "\n\t"),
        )
    }

    if len(target_file.libraries) > 0 {
        target_file_content = fmt.tprintf(
            "%slibraries\n\t%s\n",
            target_file_content,
            strings.join(write_libraries(target_file.libraries[:])[:], "\n\t"),
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
       errno != 0 {return Error.WriteError}
    return Error.None
}

read_target_file :: proc(target_name: string) -> (TargetFile, Error) {
    cwd := os.get_current_directory()
    tango_dir := fmt.tprintf("%s/.tango", cwd)

    if !os.exists(fmt.tprintf("%s/%s.tango", tango_dir, target_name)) {
        return TargetFile{}, Error.NonExistError
    }

    fd: os.Handle
    errno: os.Errno
    if fd, errno = os.open(fmt.tprintf("%s/%s.tango", tango_dir, target_name), os.O_RDWR); errno != 0 {
        return TargetFile{}, Error.OpenError
    }

    target_file := TargetFile {
        fd = fd,
    }

    data, ok := os.read_entire_file(fd)
    if !ok {return TargetFile{}, Error.ReadError}

    target_file_content := string(data)
    target_lines := strings.split_lines(target_file_content)

    if len(target_lines) < 3 {return TargetFile{}, Error.ParseError}

    i := int(0)
    line_elems := strings.split(target_lines[i], " ")
    if len(line_elems) != 2 || line_elems[0] != "target" {return TargetFile{}, Error.ParseError}
    if !possible_target_name(line_elems[1]) {return TargetFile{}, Error.ParseError}
    target_file.name = line_elems[1]
    i += 1

    line_elems = strings.split(target_lines[i], " ")
    if len(line_elems) != 2 || line_elems[0] != "directory" {return TargetFile{}, Error.ParseError}
    if !os.is_dir(line_elems[1]) {return TargetFile{}, Error.ParseError}
    target_file.directory = line_elems[1]
    i += 1

    line_elems = strings.split(target_lines[i], " ")
    if len(line_elems) != 2 || line_elems[0] != "type" {return TargetFile{}, Error.ParseError}
    if line_elems[1] != "exec" &&
       line_elems[1] != "static" &&
       line_elems[1] != "shared" {return TargetFile{}, Error.ParseError}
    target_file.type = line_elems[1]

    i += 1
    loop: for i < len(target_lines) {
        switch target_lines[i] {
        case "source":
            i += 1
            for i < len(target_lines) && len(target_lines[i]) != 0 && target_lines[i][0] == '\t' {
                file := target_lines[i][1:]
                append(&target_file.source, file)
                i += 1
            }

        case "src-dir":
            i += 1
            for i < len(target_lines) && len(target_lines[i]) != 0 && target_lines[i][0] == '\t' {
                dir := target_lines[i][1:]
                if !os.is_dir(dir) {msg_panic("Cannot find source file directory %s.", dir)}
                append(&target_file.src_dir, dir)
                i += 1
            }

        case "includes":
            i += 1
            for i < len(target_lines) && len(target_lines[i]) != 0 && target_lines[i][0] == '\t' {
                path := target_lines[i][1:]
                if !os.is_dir(path) {return TargetFile{}, Error.ParseError}
                append(&target_file.includes, path)
                i += 1
            }

        case "archives":
            i += 1
            for i < len(target_lines) && len(target_lines[i]) != 0 && target_lines[i][0] == '\t' {
                file := target_lines[i][1:]
                append(&target_file.archives, file)
                i += 1
            }

        case "libraries":
            i += 1
            for i < len(target_lines) && len(target_lines[i]) != 0 && target_lines[i][0] == '\t' {
                library := target_lines[i][1:]
                parts := strings.split(library, " ")
                if !os.is_dir(parts[1]) && parts[1] != "system" {
                    return TargetFile{}, Error.ParseError
                }
                if parts[2] != "relative" && parts[2] != "absolute" {
                    return TargetFile{}, Error.ParseError
                }
                append(&target_file.libraries, Library{parts[0], parts[1], parts[2]})
                i += 1
            }
        case "depends":
            i += 1
            for i < len(target_lines) && len(target_lines[i]) != 0 && target_lines[i][0] == '\t' {
                depend := target_lines[i][1:]
                if !possible_target_name(depend) {return TargetFile{}, Error.ParseError}
                append(&target_file.depends, depend)
                i += 1
            }

        case:
            break loop
        }
    }

    return target_file, Error.None
}
