package main

import "base:runtime"
import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

TomlLit :: string
TomlArr :: []TomlValue
TomlObj :: map[string]TomlValue

TomlValue :: union #no_nil {
    TomlLit,
    TomlArr,
    TomlObj,
}

TomlSection :: struct {
    name:   string,
    fields: map[string]TomlValue,
}

parse_toml :: proc(toml_source: string) -> []TomlSection {
    sections := make([dynamic]TomlSection)
    source := toml_source
    curr_section := TomlSection {
        fields = make(map[string]TomlValue),
    }

    for {
        source = strings.trim_left_space(source)
        if len(source) == 0 {
            append(&sections, curr_section)
            break
        }

        if source[0] == ';' {
            index := strings.index_rune(source, '\n')
            if index < 0 {
                source = ""
                continue
            }
            source = source[index + 1:]
            continue
        }

        if source[0] == '[' {
            if curr_section.name != "" || len(curr_section.fields) > 0 {
                append(&sections, curr_section)
            }
            curr_section = TomlSection {
                fields = make(map[string]TomlValue),
            }

            index := index_rune_inline(source, ']')
            if index < 0 {msg_panic("Cannot parse toml file.")}

            section_name := strings.clone(source[1:index])
            if !has_allowed_runes(
                section_name,
                "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            ) {msg_panic("Cannot parse toml file.")}
            curr_section.name = section_name
            source = source[index + 1:]
            continue
        }

        {
            if !strings.contains_rune(
                "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
                rune(source[0]),
            ) {msg_panic("Cannot parse toml file.")}

            equals_index := index_rune_inline(source, '=')
            if equals_index < 0 {msg_panic("Cannot parse toml file.")}
            attr_name := strings.trim_space(strings.clone(source[:equals_index]))

            if !has_allowed_runes(
                attr_name,
                "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",
            ) {msg_panic("Cannot parse toml file.")}

            if attr_name in curr_section.fields {msg_panic("Cannot parse toml file.")}

            source = strings.trim_left_space(source[equals_index + 1:])

            if source[0] == '{' {
                obj, new_source := parse_toml_obj(source[1:])
                curr_section.fields[attr_name] = obj
                source = new_source
            }
             else if source[0] == '[' {
                arr, new_source := parse_toml_arr(source[1:])
                curr_section.fields[attr_name] = arr
                source = new_source
            }
             else {
                index := strings.index_rune(source, '\n')
                value := strings.trim_space(strings.clone(source[:index]))
                value = unquote(value)

                curr_section.fields[attr_name] = TomlLit(value)
                source = source[index + 1:]
            }
        }
    }

    return slice.clone(sections[:])
}

unquote :: proc(val: string) -> string {
    if len(val) > 0 && (val[0] == '"' || val[0] == '\'') {
        v, allocated, ok := strconv.unquote_string(val)
        if !ok {
            return strings.clone(val)
        }
        if allocated {
            return v
        }
        return strings.clone(v)
    }
    return strings.clone(val)
}

has_allowed_runes :: proc(s: string, pool: string) -> bool {
    for r in s {
        if !strings.contains_rune(pool, r) {return false}
    }
    return true
}

index_rune_inline :: proc(haystack: string, needle: rune) -> int {
    index := strings.index_rune(haystack, needle)
    nl_index := strings.index_rune(haystack, '\n')

    if index < 0 || (nl_index > 0 && nl_index < index) {return -1}
    return index
}

parse_toml_obj :: proc(source: string) -> (TomlObj, string) {
    source := source
    obj := make(map[string]TomlValue)
    for source[0] != '}' {
        source = strings.trim_left_space(source)

        if !strings.contains_rune(
            "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            rune(source[0]),
        ) {msg_panic("Cannot parse toml file.")}

        equals_index := index_rune_inline(source, '=')
        if equals_index < 0 {msg_panic("Cannot parse toml file.1")}
        attr_name := strings.trim_space(strings.clone(source[:equals_index]))

        if !has_allowed_runes(
            attr_name,
            "abcdefghijklmnopqrstuwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_",
        ) {msg_panic("Cannot parse toml file.")}

        if attr_name in obj {msg_panic("Cannot parse toml file.2")}

        source = strings.trim_left_space(source[equals_index + 1:])

        if source[0] == '{' {
            toml_obj, new_source := parse_toml_obj(source[1:])
            obj[attr_name] = toml_obj
            source = new_source
            source = strings.trim_left_space(source)
            if source[0] != ',' {
                if source[0] != '}' {msg_panic("Cannot parse toml file.3")}
                continue
            }
            source = source[1:]
        }
         else if source[0] == '[' {
            arr, new_source := parse_toml_arr(source[1:])
            obj[attr_name] = arr
            source = new_source
            source = strings.trim_left_space(source)
            if source[0] != ',' {
                if source[0] != '}' {msg_panic("Cannot parse toml file.4")}
                continue
            }
            source = source[1:]
        }
         else {
            index := index_rune_inline(source, ',')
            if index < 0 {
                index = index_rune_inline(source, '}')
                if index < 0 {msg_panic("Cannot parse toml file.5")}
            }
            value := strings.trim_space(strings.clone(source[:index]))
            value = unquote(value)

            obj[attr_name] = TomlLit(value)
            fmt.println(source)
            source = source[index] == '}' ? source[index:] : source[index + 1:]
            fmt.println(source)
        }
    }

    return obj, source[1:]
}

parse_toml_arr :: proc(source: string) -> (TomlArr, string) {
    source := source
    arr_items := make([dynamic]TomlValue)
    defer delete(arr_items)

    for source[0] != ']' {
        source = strings.trim_left_space(source)
        if source[0] == '{' {
            obj, new_source := parse_toml_obj(source[1:])
            append(&arr_items, obj)
            source = new_source
            source = strings.trim_left_space(source)
            if source[0] != ',' {
                if source[0] != ']' {msg_panic("Cannot parse toml file.")}
                continue
            }
            source = source[1:]
        }
         else if source[0] == '[' {
            arr, new_source := parse_toml_arr(source[1:])
            append(&arr_items, arr)
            source = new_source
            source = strings.trim_left_space(source)
            if source[0] != ',' {
                if source[0] != ']' {msg_panic("Cannot parse toml file.")}
                continue
            }
            source = source[1:]
        }
         else {
            index := index_rune_inline(source, ',')
            if index < 0 {
                index = index_rune_inline(source, ']')
                if index < 0 {msg_panic("Cannot parse toml file.")}
            }
            value := strings.trim_space(strings.clone(source[:index]))
            value = unquote(value)

            append(&arr_items, TomlLit(value))
            source = source[index] == ']' ? source[index:] : source[index + 1:]
        }
    }

    return TomlArr(slice.clone(arr_items[:])), source[1:]
}

print_toml :: proc(sections: []TomlSection) {
    for sec in sections {
        fmt.printfln("[%s]", sec.name)
        for key, value in sec.fields {
            fmt.printf("%s = ", key)
            #partial switch t in value {
            case TomlArr:
                print_toml_arr(value.(TomlArr))
            case TomlObj:
                print_toml_obj(value.(TomlObj))
            case TomlLit:
                fmt.printfln("%s", value.(TomlLit))
            }
        }
    }
}

print_toml_obj :: proc(obj: TomlObj) {
    fmt.printf("{{ ")
    index := 0
    for key, value in obj {
        fmt.printf("%s = ", key)
        #partial switch t in value {
        case TomlArr:
            print_toml_arr(value.(TomlArr))
        case TomlObj:
            print_toml_obj(value.(TomlObj))
        case TomlLit:
            fmt.printf("%s", value.(TomlLit))
        }
        if index + 1 < len(obj) {fmt.printf(", ")}
        index += 1
    }
    fmt.printfln(" }}")
}

print_toml_arr :: proc(arr: TomlArr) {
    fmt.printf("[ ")
    for item, i in arr {
        #partial switch t in item {
        case TomlArr:
            print_toml_arr(item.(TomlArr))
        case TomlObj:
            print_toml_obj(item.(TomlObj))
        case TomlLit:
            fmt.printf("%s", item.(TomlLit))
        }
        if i + 1 < len(arr) {fmt.printf(", ")}
    }
    fmt.printfln(" ]")
}
