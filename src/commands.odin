package main

import "core:fmt"
import "core:os"

exec_build_cmd :: proc() {
    if len(os.args) != 3 {
        print_desc_panic(BUILD_CMD_DESC)
    }
     else if len(os.args) == 3 && os.args[2] == "--help" {
        print_desc_exit(BUILD_CMD_DESC)
    }

    targets := read_target_config()
    msg_success("%d targets where found in tango.ini.", len(targets))

    if os.args[2] not_in targets {
        msg_panic("There is no target %s specified in tango.ini.")
    }

    depend_list := construct_depend_list(os.args[2], targets)
    defer delete(depend_list)

    msg_success("Constructed dependecy list.")

    for depend_target in depend_list {
        msg_note("Compiling %s target.", depend_target.name)
        // compile(depend_target)
        msg_success("Compiled %s target.", depend_target.name)
    }
}

exec_run_cmd :: proc() {
    if len(os.args) != 3 {
        print_desc_panic(RUN_CMD_DESC)
    }
     else if len(os.args) == 3 && os.args[2] == "--help" {
        print_desc_exit(RUN_CMD_DESC)
    }

    targets := read_target_config()
    msg_success("%d targets where found in tango.ini.", len(targets))

    if os.args[2] not_in targets {
        msg_panic("There is no target %s specified in tango.ini.", os.args[2])
    }

    target := targets[os.args[2]]

    switch target.type {
    case "shared":
        msg_panic("Target %s cannot be run because it compiles to a shared library.", target.name)
    case "static":
        msg_panic("Target %s cannot be run because it compiles to an archive file.", target.name)
    case:
    }

    depend_list := construct_depend_list(os.args[2], targets)
    defer delete(depend_list)

    msg_success("Constructed dependecy list.")

    for depend_target in depend_list {
        msg_note("Compiling %s target.", depend_target.name)
        compile(depend_target)
        msg_success("Compiled %s target.", depend_target.name)
    }

    msg_note("Launching %s target executable", target.name)
    run_cmd := fmt.tprintf("%s/%s", target.directory, target.name)
}
