package main

import "core:fmt"
import "core:os"

CMD_DESC :: `Tango is a modern build tool for c language targets

Usage:

    tango <cmd> [target-name] 

Commands:

    build    Builds the target
    run      Builds and runs the target

Type "--help" after unclear command and recieve an in depth explanation`

BUILD_CMD_DESC :: `The build command compiles the target and all targets it is depending on.

Usage:

    tango build [target-name]

Description:

    target-name  The target name must be the name of an existing target.`

RUN_CMD_DESC :: `The run command compiles the target and all targets it is depending on and runs the executable.

Usage:

    tango run [target-name]

Description:

    target-name  The target name must be the name of an existing executable target.`

print_desc_panic :: proc(desc: string) {
    fmt.println(desc)
    os.exit(1)
}

print_desc_exit :: proc(desc: string) {
    fmt.println(desc)
    os.exit(0)
}

msg_success :: proc(fmt_string: string, args: ..any) {
    msg := fmt.tprintf(fmt_string, ..args)
    fmt.printfln("\033[0;32mSuccess:\033[0m %s", msg)
}

msg_note :: proc(fmt_string: string, args: ..any) {
    msg := fmt.tprintf(fmt_string, ..args)
    fmt.printfln("\033[0;35mNote:\033[0m %s", msg)
}

// msg_warn :: proc(fmt_string: string, args: ..any) {
//     msg := fmt.tprintf(fmt_string, ..args)
//     fmt.printfln("\033[0;33mWarning:\033[0m %s", msg)
// }

msg_panic :: proc(fmt_string: string, args: ..any) {
    msg := fmt.tprintf(fmt_string, ..args)
    fmt.printfln("\033[0;31mError:\033[0m %s", msg)
    os.exit(1)
}

// msg_panic_if :: proc(given_err, check_err: Error, fmt_string: string, args: ..any) {
//     if given_err != check_err {return}
//     msg := fmt.tprintf(fmt_string, ..args)
//     fmt.printfln("\033[0;31mError:\033[0m %s", msg)
//     os.exit(1)
// }
