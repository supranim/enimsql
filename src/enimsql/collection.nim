import std/tables
import ./private/datatype

import pkg/jsony

type
  Entry*[T] = OrderedTable[string, T]
  Collection*[T] = ref object
    entries: seq[Entry[T]]

proc initCollection*[T]: Collection[T] =
  new(result)

#
# Collection
#
proc add*[T](col: Collection[T], entry: Entry[T]) =
  ## Add a new `Entry` to `Collection`
  col.entries.add(entry)

proc `[]`*[T](col: Collection[T], offset: int): Entry[T] =
  ## Get an `Entry` from `Collection` by position
  result = col.entries[offset]

proc offset*[T](col: Collection[T], offset: int): T =
  ## Get an `Entry` from `Collection` by `offset`
  result = col.entries[offset]

proc len*[T](col: Collection[T]): int =
  result = col.entries.len

proc isEmpty*[T](col: Collection[T]): bool =
  result = col.entries.len == 0

iterator items*[T](col: Collection[T]): Entry[T] =
  ## Iterate over a `Collection`
  for entry in col.entries:
    yield entry

proc `$`*(col: Collection[SQLValue]): string =
  ## Convert `Collection` to JSON
  result = col.toJson()

proc `$`*[T](entry: Entry[T]): string =
  ## Convert `Collection` to JSON
  result = entry.toJson()

#
# Entry
#
proc get*[T](entry: Entry[T], key: string): T =
  result = entry[key]

proc `[]`*[T](entry: var Entry[T], key: string, val: T) =
  entry[key] = val