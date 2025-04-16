package main

// import "base:intrinsics"
import "base:runtime"
import "core:fmt"
// import "core:io"
import "core:os"
import path "core:path/filepath"
import "core:slice"
import "core:strconv"
import "core:strings"

// save_map_to_string :: proc(m: Map, allocator: runtime.Allocator) -> (data: string) {
//     b := strings.builder_make(allocator)
//     _, _ = write_map(strings.to_writer(&b), m)
//     return strings.to_string(b)
// }


// write_section :: proc(w: io.Writer, name: string, n_written: ^int = nil) -> (n: int, err: io.Error) {
//     defer if n_written != nil {n_written^ += n}
//     io.write_byte(w, '[', &n) or_return
//     io.write_string(w, name, &n) or_return
//     io.write_byte(w, ']', &n) or_return
//     io.write_byte(w, '\n', &n) or_return
//     return
// }
//
// write_pair :: proc(w: io.Writer, key: string, value: $T, n_written: ^int = nil) -> (n: int, err: io.Error) {
//     defer if n_written != nil {n_written^ += n}
//     io.write_string(w, key, &n) or_return
//     io.write_string(w, " = ", &n) or_return
//     when intrinsics.type_is_string(T) {
//         val := string(value)
//         if len(val) > 0 && (val[0] == ' ' || val[len(val) - 1] == ' ') {
//             io.write_quoted_string(w, val, n_written = &n) or_return
//         }
//          else {
//             io.write_string(w, val, &n) or_return
//         }
//  } else {
//         n += fmt.wprint(w, value)
//     }
//     io.write_byte(w, '\n', &n) or_return
//     return
// }
//
// write_map :: proc(w: io.Writer, m: Map) -> (n: int, err: io.Error) {
//     section_index := 0
//     for section, section.fields in m {
//         if section_index == 0 && section == "" {
//             // ignore section
//         }
//          else {
//             write_section(w, section, &n) or_return
//         }
//         for key, values in section.fields {
//             if len(values) == 1 {
//                 write_pair(w, key, values[0], &n) or_return
//                 continue
//             }
//
//             arr_key := fmt.tprintf("%s[]", key)
//             for value in values {
//                 write_pair(w, arr_key, value, &n) or_return
//             }
//         }
//         section_index += 1
//     }
//     return
// }

Library :: struct {
    path:      string,
    link_opts: string,
}

Target :: struct {
    name:      string,
    directory: string,
    type:      string,
    source:    []string,
    src_dir:   []string,
    includes:  []string,
    archives:  []string,
    libraries: []Library,
    depends:   []string,
}

read_target_config :: proc() -> (targets: map[string]Target) {
    cwd := os.get_current_directory()
    if !os.exists(fmt.tprintf("%s/tango.toml", cwd)) {msg_panic("Cannot find tango.toml file in current directory.")}

    data, ok := os.read_entire_file(fmt.tprintf("%s/tango.toml", cwd))
    if !ok {msg_panic("Cannot read contents of tango.toml.")}

    toml := parse_toml(string(data))

    print_toml(toml)

    ArchiveDepend :: distinct string
    LibraryDepend :: struct {
        depend_name: string,
        link_opts:   string,
    }

    Archive :: string

    DependLink :: union #no_nil {
        Library,
        ArchiveDepend,
        LibraryDepend,
        Archive,
    }

    depend_links := make(map[string][]DependLink)

    for section in toml {
        name := section.name
        if "directory" not_in section.fields ||
           "type" not_in section.fields {msg_panic("Target %s is missing a target directory or compile type.", name)}
        if !os.is_dir(section.fields["directory"].(TomlLit)) {msg_panic("Cannot find target directory.")}
        if !slice.contains(
            []string{"exec", "shared", "static"},
            section.fields["type"].(TomlLit),
        ) {msg_panic("The compile type of target %s is invalid. Must be exec, shared or static.", name)}

        dir, _ := path.abs(section.fields["directory"].(TomlLit))

        target := Target {
            name      = name,
            directory = dir,
            type      = section.fields["type"].(TomlLit),
        }

        if "source" in section.fields {
            sources, ok := section.fields["source"].(TomlArr)
            source_strs := make([]string, len(sources))
            for source, i in sources {
                source_str, ok := source.(TomlLit)
                if !ok {msg_panic("Sources for target %s must be provided as an array of single paths.", name)}
                source_strs[i] = source_str
            }
            target.source = ok ? source_strs : []string{strings.clone(section.fields["source"].(TomlLit))}
            for source, i in target.source {
                if !os.is_file(source) {msg_panic("Cannot find %s source file for target %s.", source, name)}
                target.source[i], _ = path.abs(source)
            }
        }

        if "src_dir" in section.fields {
            src_dirs, ok := section.fields["src_dir"].(TomlArr)
            src_dir_strs := make([]string, len(src_dirs))
            for src_dir, i in src_dirs {
                src_dir_str, ok := src_dir.(TomlLit)
                if !ok {msg_panic("Source directories for target %s must be provided as an array of single paths.", name)}
                src_dir_strs[i] = src_dir_str
            }
            target.src_dir = ok ? src_dir_strs : []string{strings.clone(section.fields["src_dir"].(TomlLit))}
            for src_dir, i in target.src_dir {
                if !os.is_dir(src_dir) {msg_panic("Cannot find %s source directory for target %s.", src_dir, name)}
                target.src_dir[i], _ = path.abs(src_dir)
            }
        }

        if "includes" in section.fields {
            includes, ok := section.fields["includes"].(TomlArr)
            include_strs := make([]string, len(includes))
            for include, i in includes {
                include_str, ok := include.(TomlLit)
                if !ok {msg_panic("Include paths for target %s must be provided as an array of single paths.", name)}
                include_strs[i] = include_str

            }
            target.includes = ok ? include_strs : []string{strings.clone(section.fields["includes"].(TomlLit))}
            for include, i in target.includes {
                if !os.is_dir(include) {msg_panic("Cannot find %s include directory for target %s.", include, name)}
                target.includes[i], _ = path.abs(include)
            }
        }

        targets[name] = target

        links := make([dynamic]DependLink)

        if "archives" in section.fields {
            if archive, archive_ok := section.fields["archives"].(TomlLit); archive_ok {
                path, ok := get_file_path_if(archive, {".a"})
                if !ok {msg_panic("Invalid archive file path for target %s.", name)}
                append(&links, path)
            }
             else if archives, archives_ok := section.fields["archives"].(TomlArr); archives_ok {
                for archive in archives {
                    if archive_path, path_ok := archive.(TomlLit); path_ok {
                        path, ok := get_file_path_if(archive_path, {".a"})
                        if !ok {msg_panic("Invalid archive file path for target %s.", name)}
                        append(&links, path)
                    }
                     else {
                        archive_target, target_ok := archive.(TomlObj)
                        if !target_ok ||
                           "target" not_in archive_target {msg_panic("Invalid archive file path for target %s.", name)}
                        append(&links, ArchiveDepend(archive_target["target"].(TomlLit)))
                    }
                }
            }
             else {
                archive_target, target_ok := section.fields["archives"].(TomlObj)
                if !target_ok ||
                   "target" not_in archive_target {msg_panic("Invalid archive file path for target %s.", name)}
                append(&links, ArchiveDepend(archive_target["target"].(TomlLit)))
            }
        }

        if "libraries" in section.fields {
            if library, lib_ok := section.fields["libraries"].(TomlObj); lib_ok {
                if library["opts"].(TomlLit) != TomlLit("relative") &&
                   library["opts"].(TomlLit) !=
                       "absolute" {msg_panic("Tried to link with target for target %s.", name)}
                opts: string
                #partial switch t in library["opts"] {
                case TomlLit:
                    if library["opts"].(TomlLit) != "absolute" &&
                       library["opts"].(TomlLit) !=
                           "relative" {msg_panic("Tried to link with invalid linking methode for target %s. Specify it as relative or absolute.", name)}
                    opts = library["opts"].(TomlLit)
                case TomlArr, TomlObj:
                    msg_panic(
                        "Tried to link with invalid linking methode for target %s. Specify it as relative or absolute.",
                        name,
                    )
                }

                if "target" in library {
                    lib_target, target_ok := library["target"].(TomlLit)
                    if !target_ok {msg_panic("Tried to link to an invalid target for target %s.", name)}
                    append(&links, LibraryDepend{depend_name = lib_target, link_opts = opts})
                }
                 else if "path" in library {
                    lib_path, lib_ok := library["path"].(TomlLit)
                    if !lib_ok {msg_panic("Libraries for target %s must be provided as a structure with path and linking type.", name)}
                    path, ok := get_file_path_if(lib_path, {".so", ".dylib"})
                    if !ok {msg_panic("Invalid shared library path for target %s.", name)}
                    append(&links, Library{path = path, link_opts = opts})
                }
                 else {msg_panic(
                        "Libraries for target %s must be provided as a structure with path and linking type.",
                        name,
                    )}
            }
             else {
                libraries, ok := section.fields["libraries"].(TomlArr)
                if !ok {msg_panic("Libraries for target %s must be provided as a structure with path and linking type.", name)}
                for lib in libraries {
                    library, lib_ok := section.fields["libraries"].(TomlObj)
                    if !lib_ok {msg_panic("Libraries for target %s must be provided as a structure with path and linking type.", name)}
                    if "opts" not_in
                       library {msg_panic("Libraries for target %s must be provided as a structure with path and linking type.", name)}

                    if library["opts"].(TomlLit) != TomlLit("relative") &&
                       library["opts"].(TomlLit) !=
                           "absolute" {msg_panic("Tried to link with target for target %s.", name)}
                    opts: string
                    #partial switch t in library["opts"] {
                    case TomlLit:
                        if library["opts"].(TomlLit) != "absolute" &&
                           library["opts"].(TomlLit) !=
                               "relative" {msg_panic("Tried to link with invalid linking methode for target %s. Specify it as relative or absolute.", name)}
                        opts = library["opts"].(TomlLit)
                    case TomlArr, TomlObj:
                        msg_panic(
                            "Tried to link with invalid linking methode for target %s. Specify it as relative or absolute.",
                            name,
                        )
                    }

                    if "target" in library {
                        lib_target, target_ok := library["target"].(TomlLit)
                        if !target_ok {msg_panic("Tried to link to an invalid target for target %s.", name)}
                        append(&links, LibraryDepend{depend_name = lib_target, link_opts = opts})
                    }
                     else if "path" in library {
                        lib_path, lib_ok := library["path"].(TomlLit)
                        if !lib_ok {msg_panic("Libraries for target %s must be provided as a structure with path and linking type.", name)}
                        path, ok := get_file_path_if(lib_path, {".so", ".dylib"})
                        if !ok {msg_panic("Invalid shared library path for target %s.", name)}
                        append(&links, Library{path = path, link_opts = opts})
                    }
                     else {msg_panic(
                            "Libraries for target %s must be provided as a structure with path and linking type.",
                            name,
                        )}
                }
            }
        }

        depend_links[name] = slice.clone(links[:])
        delete(links)
    }

    for name, &target in targets {
        if name not_in depend_links {continue}

        libraries := make([dynamic]Library)
        archives := make([dynamic]string)
        depends := make([dynamic]string)
        links := depend_links[name]
        for link in links {
            switch v in link {
            case Library:
                append(&libraries, link.(Library))
            case Archive:
                append(&archives, link.(Archive))
            case ArchiveDepend:
                depend_name := string(link.(ArchiveDepend))
                if depend_name not_in
                   targets {msg_panic("Target %s depends on target %s which does not exist.", name, depend_name)}
                depend_target := targets[depend_name]
                if depend_target.type !=
                   "static" {msg_panic("Target %s wants to depend on target with type static but %s target has the wrong type.", name, depend_name)}
                append(&archives, fmt.tprintf("%s/lib%s.a", depend_target.directory, depend_target.name))
                append(&depends, depend_name)
            case LibraryDepend:
                lib_depend := link.(LibraryDepend)
                if lib_depend.depend_name not_in
                   targets {msg_panic("Target %s depends on target %s which does not exist.", name, lib_depend.depend_name)}
                depend_target := targets[lib_depend.depend_name]
                if depend_target.type !=
                   "shared" {msg_panic("Target %s wants to depend on target with type static but %s target has the wrong type.", name, lib_depend.depend_name)}
                append(
                    &libraries,
                    Library {
                        path = fmt.tprintf("%s/lib%s.dylib", depend_target.directory, depend_target.name),
                        link_opts = lib_depend.link_opts,
                    },
                )
                append(&depends, lib_depend.depend_name)
            }
        }

        target.libraries = slice.clone(libraries[:])
        target.archives = slice.clone(archives[:])
        target.depends = slice.clone(depends[:])
        delete(libraries)
        delete(archives)
        delete(depends)
    }
    return
}
