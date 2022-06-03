# A simple ORM for poets
#
# (c) 2021 Enimsql is released under MIT License
#          George Lemon | Made by Humans from OpenPeep
#          https://supranim.com   |    https://github.com/supranim/enimsql

import std/tables
import std/macros except name

import std/jsonutils
import std/json

from std/strutils import `%`, indent, join, toLowerAscii, endsWith

include ./meta

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

proc exists[M](model: ref M, id: string): ref M =
    ## Test the existence of any record in a subquery
    static: checkObjectIntegrity(model)

proc select*[M](model: typedesc[ref M], columns: varargs[string]): ref M =
    ## Create a `SELECT` statement returning only rows with specified columns
    runnableExamples:
        User.select("username", "email_address").exec()

    static: checkObjectIntegrity(model)
    if columns.len != 0:
        checkModelColumns($model, columns)
    result = model.initTable(SelectStmt)
    if columns.len == 0:
        result.sql.selectStmt = @["*"]
    else:
        for col in columns:
            # TODO validate column names
            result.sql.selectStmt.add(col)

proc update*[M](model: typedesc[ref M], cols: varargs[KeyValueTuple]): ref M =
    ## Create an `UPDATE` statement. Once executed,
    ## returns either `true` or `false`.
    ##
    ## This is a safe proc for updating records in a `Model`, and
    ## requires a `WHERE` statement.
    ##
    ## For updating all records use `updateAll` proc.
    static: checkObjectIntegrity(model)
    if cols.len != 0:
        checkModelColumns($model, cols)
    result = model.initTable(UpdateStmt)
    var refCol: seq[string]
    for col in cols:
        checkDuplicates(col.colName, result.metaModelName, refCol)
        result.sql.updateSetStmt.add(col)

proc updateAll*[M](model: typedesc[ref M], cols: varargs[KeyValueTuple]): ref M =
    ## Update all records in a `Model` with given columns and values.
    static: checkObjectIntegrity(model)
    if cols.len != 0:
        checkModelColumns($model, cols)
    result = model.initTable(UpdateAllStmt)
    var refCol: seq[string]
    for col in cols:
        checkDuplicates(col.colName, result.metaModelName, refCol)
        result.sql.updateSetStmt.add(col)
        refCol.add col.colName

proc delete*[M](model: typedesc[ref M]): ref M =
    ## Delete specific records in a model.
    static: checkObjectIntegrity(model)
    result = model.initTable(DeleteStmt)

proc where*[M](model: ref M, filters: varargs[CompFilter]): ref M =
    ## Handle `WHERE` statements with filtering support.
    ## All `Comparators` are supported.
    for filter in filters:
        model.sql.whereStmt.add filter
        inc model.sql.countWhere
    result = model

proc whereIn*[M](model: ref M, column: string, values:openarray[string]): ref M =
    ## Handle a `WHERE` statement followed by an `IN` operator
    for value in values:
        model.sql.whereIn.add value
    result = model

proc whereNotIn*[M](model: ref M, column: string, values:openarray[string]): ref M =
    ## Handle a `WHERE` statement followed by an `NOT` operator
    ## TODO validate col name
    for value in values:
        model.sql.whereNotIn.add value
    result = model

proc whereLike*[M](model: ref M, column: string, valueLike: string): ref M =
    ## `a%`       Finds any values that start with "a"
    ## `%a`       Finds any values that end with "a"
    ## `%or%`     Finds any values that have "or" in any position
    ## `_r%`      Finds any values that have "r" in the second position
    ## `a_%`      Finds any values that start with "a" and are at least 2 characters in length
    ## `a__%`     Finds any values that start with "a" and are at least 3 characters in length
    ## `a%o`      Finds any values that start with "a" and ends with "o"
    result = model
    checkModelColumns(result.metaModelName, column)
    result.sql.whereLikeStmt.add (column, valueLike)
    inc result.sql.countWhere

proc exec*[M](model: ref M): string =
    ## Execute the current SQL statement
    var syntax: string
    case model.sql.stmtType:
    of DeleteStmt:
        syntax = $DeleteStmt
        add syntax, indent("FROM", 1) & indent(model.metaTableName, 1)
    of SelectStmt:
        syntax = $SelectStmt
        if model.sql.selectStmt.len == 1:
            add syntax, indent(model.sql.selectStmt[0], 1)
        else:
            add syntax, indent(join(model.sql.selectStmt, ", "), 1)
        add syntax, indent("FROM", 1) & indent(model.metaTableName, 1)
    of UpdateStmt, UpdateAllStmt:
        syntax = $UpdateStmt
        add syntax, indent(model.metaTableName, 1)
        add syntax, indent("SET", 1)
        let updateStmtLen = model.sql.updateSetStmt.len - 1
        for i in 0 .. updateStmtLen:
            add syntax, indent(model.sql.updateSetStmt[i].colName, 1)
            add syntax, indent($EQ, 1)
            add syntax, indent("'" & model.sql.updateSetStmt[i].colValue & "'", 1)
            if i != updateStmtLen:
                add syntax, ","
    else: discard

    if model.sql.whereStmt.len != 0:
        add syntax, indent($WhereStmt, 1)
        for whereStmt in model.sql.whereStmt:
            add syntax, indent(whereStmt.colName, 1)
            add syntax, indent($whereStmt.op, 1)
            add syntax, indent("'" & whereStmt.value & "'", 1)
            if model.sql.countWhere > 1:
                add syntax, indent($AND, 1)
            dec model.sql.countWhere
    elif model.sql.whereLikeStmt.len != 0:
        add syntax, indent($WhereStmt, 1)
        for whereLike in model.sql.whereLikeStmt:
            add syntax, indent($WhereLikeStmt % [whereLike.colName, whereLike.valueLike], 1)
            if model.sql.countWhere > 1:
                add syntax, indent($AND, 1)
            dec model.sql.countWhere
    else:
        if model.sql.stmtType == UpdateStmt:
            raise newException(DatabaseDefect,
                "Missing \"WHERE\" statement. Use `updateAll` procedure for updating all records in the table.")
    echo syntax
    # result = $(toJson(model))
    model.sql.countWhere = 0

include ./model
