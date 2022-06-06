# A simple ORM for poets
#
# (c) 2021 Enimsql is released under MIT License
#          George Lemon | Made by Humans from OpenPeep
#          https://supranim.com   |    https://github.com/supranim/enimsql

template `a%`*(str: string): untyped =
    ## Finds any values that start with given `str`
    var valueLike = "$1%" % [str]
    valueLike

template `%a`*(str: string): untyped =
    ## Finds any values that end with given `str`
    var valueLike  = "%$1" % [str]
    valueLike

template `%a%`*(str: string): untyped =
    ## Finds any values that have given `str` in any position
    var valueLike  = "%$1%" % [str]
    valueLike

template `-a%`*(str: string): untyped =
    ## Finds any values that contains given `str` in the second position.
    var valueLike  = "_$1%" % [str]
    valueLike

template `a%b`*(startStr, endStr: string): untyped =
    ## Finds any values that start with "a" and ends with "o"
    var valueLike  = "$1%$2" % [startStr, endStr]
    valueLike

template newDeleteStmt() =
    syntax = $DeleteStmt
    syntax &= indent("FROM", 1) & indent(model.metaTableName, 1)

template newSelectStmt() =
    syntax = $SelectStmt
    if model.sql.selectStmt.len == 1:
        syntax &= indent(model.sql.selectStmt[0], 1)
    else:
        syntax &= indent(join(model.sql.selectStmt, ", "), 1)
    syntax &= indent("FROM", 1) & indent(model.metaTableName, 1)

template newUpdateStmt() =
    syntax = $UpdateStmt
    syntax &= indent(model.metaTableName, 1)
    syntax &= indent("SET", 1)
    let updateStmtLen = model.sql.updateSetStmt.len - 1
    for i in 0 .. updateStmtLen:
        syntax &= indent(model.sql.updateSetStmt[i].colName, 1)
        syntax &= indent($EQ, 1)
        syntax &= indent(escapeValue model.sql.updateSetStmt[i].colValue, 1)
        if i != updateStmtLen:
            syntax &= ","

template newInsertStmt() =
    var insertCols, insertValues: seq[string]
    for entry in model.sql.insertStmt:
        insertCols.add entry.colName
        insertValues.add escapeValue entry.colValue
    syntax = $InsertStmt % [model.metaTableName, join(insertCols, ", "), join(insertValues)]

template newIncrementStmt() =
    syntax = $UpdateStmt
    syntax &= indent("SET", 1)
    syntax &= indent($IncrementStmt % [model.sql.incrementStmt.columnName, $model.sql.incrementStmt.offset], 1)

template newDecrementStmt() =
    syntax = $UpdateStmt
    syntax &= indent("SET", 1)
    syntax &= indent($DecrementStmt % [model.sql.incrementStmt.columnName, $model.sql.incrementStmt.offset], 1)