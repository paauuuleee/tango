package main

import "core:os"

main :: proc() {
    args := os.args
    switch len(os.args) {
    case 1:
        print_desc_panic(CMD_DESC)
    case:
        switch os.args[1] {
        case "build":
            exec_build_cmd()
        case "depend":
            exec_run_cmd()
        case "--help":
            print_desc_exit(CMD_DESC)
        case:
            print_desc_panic(CMD_DESC)
        }
    }
}
