# A simple ORM for poets
#
# (c) 2021 Enimsql is released under MIT License
#          Made by Humans from OpenPeep
#          https://supranim.com

import std/[tables, macros]
export tables

type
    Entry* = TableRef[string, string]
    Entries* = Table[int, Entry]

    Collection* = object
        entries: Entries
        includes: seq[string]
            ## A sequence of column names to include in results

    KvCallbackBool = proc(k, v: string): bool {.nimcall.}

#
# Entry API
#
macro get*(entry: untyped, key: untyped): untyped =
    result = newNimNode(nnkBracketExpr)
    result.add entry
    result.add key

method get*(entry: Entry): Entry {.base.} =
    result = entry

method columns*(entry: Entry): seq[string] {.base.} =
    ## Returns a sequence of strings containing all columns (keys) in `Entry`
    for k in entry.keys(): result.add k

method values*(entry: Entry): seq[string] {.base.} =
    ## Returns a sequence of strings containing the all values in `Entry`
    for v in entry.values(): result.add v

#
# Collection API
#
method get*(c: Collection): Entries {.base.} =
    ## Returns all entires in `Collection`
    if c.includes.len == 0:
        return c.entries
    var i = 0
    for k, entry in c.entries.pairs():
        for colKey, colVal in entry:
            if colKey notin c.includes:
                continue
            result[i] = newTable[string, string]()
            result[i][colKey] = colVal
        inc i

method add*(c: var Collection, i: int, columns: seq[tuple[key, value: string]]) {.base.} =
    ## Add a new `Entry` in the current `Collection`
    c.entries[i] = newTable[string, string]()
    for col in columns:
        c.entries[i][col.key] = col.value

method isEmpty*(c: Collection): bool {.base.} =
    ## Returns `true` if the collection is empty
    ## (has no results), otherwise returns `false`
    result = c.entries.len == 0

method isNotEmpty*(c: Collection): bool {.base.} =
    ## Returns `true` if the collection is not empty, otherwise `false`
    result = c.entries.len != 0

proc exists*[A](entry: A): bool =
    ## Determine if given entry exists (not nil)
    result = entry != nil

method count*(c: Collection): int {.base.} = 
    ## A public alias method of `len` in order to retrieve
    ## the total number of entries in the collection
    result = c.entries.len

method countBy*(c: Collection, input: string) {.base.} =
    ## Count all entries in a Collection by a custom criteria
    ## TODO

method first*(c: Collection, callback: KvCallbackBool): string {.base.} =
    ## The `first` method returns any first element
    ## in the collection that match in given callback
    runnableExamples:
        let entry = collection.first() do(k, v: string) -> bool:
            return v == "test@example.com"
    for key, entry in c.entries.pairs():
        for colKey, colVal in entry.pairs():
            if callback(colKey, colVal):
                return colVal

method firstWhere*(c: Collection, key, val: string): Entry {.base.} =
    ## Returns the first `Entry` in the `Collection`
    ## with the given key/value pair
    for k, entry in c.entries.pairs():
        if entry.hasKey(key):
            if entry[key] == val:
                return entry

method firstWhere*(c: Collection, callback: KvCallbackBool): Entry {.base.} =
    ## Returns the first `Entry` in the `Collection`
    ## based on given `callback`
    for key, entry in c.entries.pairs():
        for colKey, colVal in entry.pairs():
            if callback(colKey, colVal):
                return entry

method only*(c: var Collection, columns: openarray[string]): Collection {.base.} =
    ## Returns the items in the `Collection` with the specified keys only
    for col in columns:
        add c.includes, col
    result = c
