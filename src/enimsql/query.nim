# A simple ORM for poets
#
# (c) 2021 Enimsql is released under MIT License
#          Made by Humans from OpenPeep
#          https://supranim.com

import std/asyncdispatch
import std/macros except name

from std/strutils import `%`, indent, join
from ./database import Database, exec, sql, close, rows

import ./collection

include ./meta
include ./private/statements

export collection, asyncdispatch

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

proc select*[M](model: typedesc[ref M], cols: varargs[string]): ref M =
    ## Create a `SELECT` statement returning only rows with specified columns
    # runnableExamples:
    #     User.select("username", "email_address").exec()
    static: checkObjectIntegrity(model)
    if cols.len != 0:
        checkModelColumns($model, cols)
    result = model.initTable(SelectStmt)
    if cols.len == 0:
        result.sql.selectStmt = @["*"]
    else:
        for col in cols:
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
        refCol.add col.colName # prevent duplicates

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
        refCol.add col.colName # prevent duplicates

proc insert*[M](model: typedesc[ref M], cols: varargs[KeyValueTuple]): ref M =
    ## Insert a new record in a table
    static: checkObjectIntegrity(model)
    if cols.len != 0:
        checkModelColumns($model, cols)
    result = model.initTable(InsertStmt)
    var refCol: seq[string]
    for col in cols:
        checkDuplicates(col.colName, result.metaModelName, refCol)
        result.sql.insertStmt.add(col)
        refCol.add col.colName # prevent duplicates

proc delete*[M](model: typedesc[ref M]): ref M =
    ## Delete specific records in a model.
    static: checkObjectIntegrity(model)
    result = model.initTable(DeleteStmt)

proc where*[M](model: ref M, filters: varargs[KeyOperatorValue]): ref M =
    ## Handle `WHERE` statements allowing `KeyOperatorValue` filters.
    if filters.len == 0:
        raise newException(DatabaseDefect, "Missing filters for WHERE clause")
    for filter in filters:
        model.sql.whereStmt.add filter
        inc model.sql.countWhere
    result = model

proc where*[M](model: typedesc[ref M], filters: varargs[KeyOperatorValue]): ref M =
    ## Handle `WHERE` statements allowing `KeyOperatorValue` filters.
    ## This procedure initialize the model object. Useful if you want
    ## to create a `SELECT *` SQL statement and want to skip calling `select()` proc.
    static: checkObjectIntegrity(model)
    result = model.initTable(SelectStmt)
    checkModelColumns(result.metaModelName, filters)
    result.sql.selectStmt = @["*"]
    discard where(result, filters)

proc whereIn*[M](model: ref M, column: string, values:openarray[string]): ref M =
    ## Create a `WHERE` clause by filtering results using `IN` operator
    ## ```sql
    ## SELECT * FROM users WHERE country IN ('Bulgaria', 'Romania', 'Hungary');
    ## ```
    for value in values:
        model.sql.whereIn.add value
    result = model

proc whereIn*[M, S](model: ref M, secModels: typedesc[ref S]): ref M =
    echo $secModels

proc whereNotIn*[M](model: ref M, column: string, values:openarray[string]): ref M =
    ## Create a `WHERE` clause by filtering results using `NOT` operator
    ## ```sql
    ## SELECT * FROM users WHERE country NOT IN ('Germany', 'France', 'UK');
    ## ```
    for value in values:
        model.sql.whereNotIn.add value
    result = model

proc whereLike*[M](model: ref M, column: string, valueLike: string): ref M =
    ## `a%`       Finds any values that start with "a"
    ##
    ## `%a`       Finds any values that end with "a"
    ##
    ## `%or%`     Finds any values that have "or" in any position
    ##
    ## `_r%`      Finds any values that have "r" in the second position
    ##
    ## `a_%`      Finds any values that start with "a" and are at least 2 characters in length
    ##
    ## `a__%`     Finds any values that start with "a" and are at least 3 characters in length
    ##
    ## `a%o`      Finds any values that start with "a" and ends with "o"
    result = model
    checkModelColumns(result.metaModelName, column)
    result.sql.whereLikeStmt.add (column, valueLike)
    inc result.sql.countWhere

proc whereExists*[M, S](model: ref M, secondModel: typedesc[ref S], cols: varargs[KeyOperatorValue]): ref M =
    ## A subquery procedure for testing the existence of any record.
    # if cols.len != 0:
    #     checkModelColumns(model.metaModelName, cols)
    result = model

proc increment*[M](model: typedesc[ref M], column: string, offset = 1): ref M =
    ## Increment the int value of a given column
    static: checkObjectIntegrity(model)
    checkModelColumns($model, column)
    result = model.initTable(IncrementStmt)
    result.sql.incrementStmt = (column, offset)

proc decrement*[M](model: typedesc[ref M], column: string, offset = 1): ref M =
    ## Decrement the int value of a given column
    static: checkObjectIntegrity(model)
    checkModelColumns($model, column)
    result = model.initTable(DecrementStmt)
    result.sql.decrementStmt = (column, offset)

template execSql[M](model: ref M): untyped =
    case model.sql.stmtType:
    of DeleteStmt:                newDeleteStmt
    of SelectStmt:                newSelectStmt
    of UpdateStmt, UpdateAllStmt: newUpdateStmt
    of InsertStmt:                newInsertStmt
    of IncrementStmt:             newIncrementStmt
    of DecrementStmt:             newDecrementStmt
    else: discard

    if model.sql.whereStmt.len != 0:
        syntax &= indent($WhereStmt, 1)
        for whereStmt in model.sql.whereStmt:
            syntax &= indent(whereStmt.colName, 1)
            syntax &= indent($whereStmt.op, 1)
            syntax &= indent(escapeValue whereStmt.value, 1)
            if model.sql.countWhere > 1:
                syntax &= indent($AND, 1)
            dec model.sql.countWhere
    elif model.sql.whereLikeStmt.len != 0:
        syntax &= indent($WhereStmt, 1)
        for whereLike in model.sql.whereLikeStmt:
            syntax &= indent($WhereLikeStmt % [whereLike.colName, whereLike.valueLike], 1)
            if model.sql.countWhere > 1:
                syntax &= indent($AND, 1)
            dec model.sql.countWhere
    elif model.sql.whereSubqueryStmt.len != 0:
        syntax &= indent($WhereExistsStmt % [model.metaTableName], 1)
    else:
        if model.sql.stmtType == UpdateStmt:
            raise newException(DatabaseDefect,
                "Missing \"WHERE\" statement. Use `updateAll` procedure for updating all records in the table.")
    model.sql.countWhere = 0
    syntax

proc getRaw*[M](model: ref M): string =
    ## Compose the SQL Query and return the stringified version of the SQL.
    var syntax: SqlQuery
    result = execSql(model)

proc get*[M](model: ref M): Future[Collection] {.async.} =
    ## Executes the query from given model and returns a
    ## `Collection` table with available results.
    # exec(Database, sql(model.getRaw()))
    result = await rows(Database, model.getRaw())
    close Database

include ./model

proc newDatabase*[D: Models](database: D, dbName: string) =
    ## Creates a new database

proc dropDatabase*[D: Models](database: D, dbName: string) =
    ## Drop an existing database

proc newTable*[D: Models](database: D, tableName: string) =
    ## Create a new table in a database

proc dropTable*[D: Models](database: D, tableName: string) = 
    ## Drop an existing table from a database

proc alterTable*[D: Models](database: D, tableName: string) =
    ## Modify columns in an existing table
    