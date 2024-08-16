package main

import "core:os"

main :: proc() {
    args := os.args
    switch len(os.args) {
    case 1:
        print_desc_panic(CMD_DESC)
    case:
        switch os.args[1] {
        case "init":
            exec_init_cmd()
        case "new":
            exec_new_cmd()
        case "add":
            exec_add_cmd()
        case "add-dir":
            exec_add_dir_cmd()
        case "link":
            exec_link_cmd()
        case "inc":
            exec_inc_cmd()
        case "build":
            exec_build_cmd()
        case "depend":
            exec_depend_cmd()
        case "log":
            exec_log_cmd()
        case "ls":
            exec_ls_cmd()
        case "--help":
            print_desc_exit(CMD_DESC)
        case:
            print_desc_panic(CMD_DESC)
        }
    }
}
