package main

import "core:fmt"
import "core:os"

CMD_DESC :: `Tango is a modern build tool for c language targets

Usage:

    tango <cmd> [args] {opts}

Commands:

    new     Creates a new c target
    build   Builds the target
    add     Adds source files to the target comilation
    inc     Sets an include path
    link    Links static and dynamic libraries (can also link to other target)
    depend  Makes building a target dependend on another target built

Type "--help" after unclear command and recieve an in depth explanation`

NEW_CMD_DESC :: `The new command creates a new c target.

Usage:

    tango new [target-name] [target-folder] {target-type}

Description:

    target-name:   The target name must consist of only english letters and arabic digits. The leading character must be a letter.
    target-folder  The target folder must be provided by absolute or relative path.
    target-type    The target type is and option and defines if the target is an executable, a static library or a shared library (--exec / --static / --shared)`


ADD_CMD_DESC :: `The add command adds c source files to the target compilation.

Usage:

    tango add [target-name] [c-source-file]

Description:

    target-name:   The target name must be the name of an existing target.
    c-source-file  The c source file must provided by absolute or relative path. (path to folder is permitted)`

INC_CMD_DESC :: `The inc command adds an include path to the target compilation.

Usage:

    tango inc [target-name] [include-path]

Description:

    target-name:   The target name must be the name of an existing target.
    include-path:  The include path must be an absolute or relative to a folder (path to file is permitted)`

BUILD_CMD_DESC :: `The build command compiles the target and all targets it is depending on.

Usage:

    tango build [target-name]

Description:

    target-name:   The target name must be the name of an existing target.`


LINK_CMD_DESC :: `The link command adds a library link to the traget compilation.

Usage:

    tango link [target-name] [library-file] {linking-method}

Description:

    traget-name:     The target name must be the name of an existing target.
    library-path:    The library path must be an absolute or realtive path to the library file.
                     You can also link to a differnet target that is a static or shared library.
                     To do that you have to type target:[link-target-name]. The link target name must also be an existing target.
                     This automatically adds this target to the targets that compilation depends on.
    linking-method:  The linking mathod is an option. 
                     For static linking it needs to be "--static" and the library has to be a static library.
                     For dynamic linking it needs to be "--absolute" or "--relative" 
                     to link with an absolute or relative path and the library has to be shared library`

DEPEND_CMD_DESC :: `The depend command schedules the compilation of another target before the compilation of the target.

Usage:

    tango depend [target-name] [depend-target-name]

Description:

    target-name:         The target name must be the name of an existing target.
    depend-target-name:  The depend target name must be the name of an existing target.
                         The link command also adds target that the giving target depends on when linking to a target.`

print_desc_panic :: proc(desc: string) {
	fmt.println(desc)
	os.exit(1)
}

print_desc_exit :: proc(desc: string) {
	fmt.println(desc)
	os.exit(0)
}

msg_panic :: proc(fmt_string: string, args: ..any) {
    msg := fmt.tprintf(fmt_string, ..args)
    fmt.printfln("Error: %s", msg)
    os.exit(1)
}

msg_panic_if :: proc(given_err, check_err: TargetFileError, fmt_string: string, args: ..any) {
	if given_err == check_err {
        msg := fmt.tprintf(fmt_string, ..args)
        fmt.printfln("Error: %s", msg)
        os.exit(1)
    }
}