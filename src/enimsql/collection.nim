# A simple ORM for poets
#
# (c) 2021 Enimsql is released under MIT License
#          Made by Humans from OpenPeep
#          https://supranim.com

import std/tables
export tables

type
    ColKey* = string
    ColValue* = string
    Entry* = TableRef[ColKey, ColValue]
    Collection* = object
        entries*: Table[int, Entry]

method addRow*(c: var Collection, i: int, columns: seq[tuple[key, value: string]]) =
    c.entries[i] = newTable[string, string]()
    for col in columns:
        c.entries[i][col.key] = col.value

method isEmpty*(c: Collection): bool {.base.} =
    ## Returns `true` if the collection is empty (has no results),
    ## otherwise returns `false`.
    result = c.entries.len == 0

method exists*[A](item: A): bool {.base.} =
    result = item != nil

method count*(c: Collection): int {.base.} = 
    ## Returns the total number of items in the collection.
    ## This is a more specific alias for `len`
    result = c.entries.len

method first*(c: Collection, cb: proc(k, v: string)): Entry {.base.} =
    ## The `first` method returns any first element
    ## in the collection that match in given callback

method firstWhere*(c: Collection, key: ColKey, val: ColValue): Entry {.base.} =
    ## Returns the first entry in the collection with the given key/value pair
    for entry in values(c.entries):
        if entry.hasKey key:
            if entry[key] == val:
                return entry