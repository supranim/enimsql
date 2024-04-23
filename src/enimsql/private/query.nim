import std/[tables, macros, strutils, sequtils]

from pkg/db_connector/db_postgres import SQLQuery

import ./datatype, ../collection
export datatype, collection

type
  NodeType* = enum
    ntCreate
    ntTruncate
    ntDrop
    ntInsert
    ntUpsert
    ntSelect
    ntUpdate
    ntUpdateAll
    ntWhere
    ntWhereLike
    ntWhereExistsStmt
    ntInc
    ntDec
    ntSet
    ntReturn
    ntFrom
    ntInfix
    ntComp
    ntField

  SQLOperator* = enum
    EQ = "="
    LT = "<"
    LTE = "<="
    GT = ">"
    GTE = ">="
    NE = "<>"
    BETWEEN = "BETWEEN"
    LIKE = "LIKE"
    IN = "IN"

  Conditionals* = enum
    None
    AND = "AND"
    OR = "OR"
    NOT = "NOT"

  Order* = enum
    ASC = "ASC"
    DESC = "DESC"

  SQLColumn* = ref object
    cName*: string
    cType*: DataType
    cTypeArgs*: seq[string]
    cDefault*: SQLValue
    cConstraints*: seq[Constraints]
    cReference*: Reference

  Constraints* = enum
    notnull = "NOT NULL"
    nullable = "NULL"
    unique = "UNIQUE"
    pk = "PRIMARY KEY"    
    fk = "FOREIGN KEY"
    check = "CHECK"
    default = "DEFAULT"
    createIndex = "CREATE INDEX"

  Reference* = ref object
    model*, colName*: string

  # KeyOpValue* = tuple[colName, op: SQLOperator, colValue: Value]
  # KeyValue* = tuple[colName: string, colValue: Value]
  QueryBuilder* = (Model, Query)
  Query* = ref object
    case nt*: NodeType
    of ntCreate:
      createColumns*: seq[SQLColumn]
    of ntSelect:
      selectColumns*: seq[string]
      selectTable*: string
      selectCondition*: Query # ntWhere
      selectOrder*: seq[(string, Order)]
    of ntInsert, ntUpsert:
      insertFields*: OrderedTable[string, string]
      insertReturn*: Query # ntReturn node
    of ntInfix:
      infixOp: SQLOperator
      infixLeft, infixRight: string
    of ntWhere:
      whereBranches*: seq[Query] # ntInfix
    of ntUpdate, ntUpdateAll:
      updateFields: seq[(SQLColumn, string)]
      updateCondition*: Query
    of ntDrop:
      discard
    of ntTruncate:
      truncateColumns*: seq[string]
    of ntReturn:
      returnColName*, returnColAlias*: string
    else: discard

  Model* = tuple[
    tName: string,
    tColumns: OrderedTableRef[string, SQLColumn]
  ]

  SchemaTable* = OrderedTableRef[string, Model]

  AbstractModel* = ref object of RootObj
    modelName: string

  Schema* = OrderedTableRef[string, SQLColumn]
  SchemaBuilder* = proc(m: Schema)
  EnimsqlModelDefect* = object of CatchableError
  EnimsqlQueryDefect* = object of CatchableError

var StaticSchema* {.compileTime.} = SchemaTable()
var Models* = SchemaTable()

when not defined release:
  import std/[json, jsonutils]

  proc `$`*(node: Query): string =
    result = pretty(node.toJson, 2)

proc `$`*(x: SqlQuery): string = x.string

proc getTableName*(id: string): string =
  add result, id[0].toLowerAscii
  for c in id[1..^1]:
    if c.isUpperAscii:
      add result, "_"
      add result, c.toLowerAscii
    else:
      add result, c

proc getDefaultValue*(col: SQLColumn): string =
  ## Returns default value of `sqlv`
  if col.cDefault != nil:
    result = col.cDefault.value

proc newCreateStmt*: Query  = Query(nt: ntCreate)
proc newDropStmt*:   Query  = Query(nt: ntDrop)
proc newClearStmt*:  Query  = Query(nt: ntTruncate)
proc newInsertStmt*: Query  = Query(nt: ntInsert)
proc newUpsertStmt*: Query  = Query(nt: ntUpsert)
proc newWhereStmt*:  Query  = Query(nt: ntWhere)
proc newSelectStmt*: Query  = Query(nt: ntSelect)
proc newUpdateStmt*: Query  = Query(nt: ntUpdate)
proc newUpdateAllStmt*: Query  = Query(nt: ntUpdateAll)

proc newInfixExpr*(lhs, rhs: string, op: SQLOperator): Query =
  result = Query(nt: ntInfix)
  result.infixLeft = lhs
  result.infixRight= rhs
  result.infixOp = op

proc newValue*(x: NimNode, dt: DataType): SQLValue =
  ## Compile-time procedure for creating a default SQLValue
  # todo validation
  case x.kind
  of nnkIntLit:
    result = SQLValue(dt: Int, value: $(x.intVal))
  of nnkStrLit:
    case dt
    of Text:
      result = SQLValue(dt: Text, value: x.strVal)
    else: discard
  of nnkIdent:
    if x.strVal in ["false", "true"]:
      result = SQLValue(dt: Boolean, value: x.strVal)
    else: discard # todo
  else: discard

type
  DBDriver* = enum
    driverUnknown
    driverPostgres
    driverSQLite

var
  stmtPgsql {.compileTime.} = {
    "create": "CREATE TABLE IF NOT EXISTS $1 ($2);",
    "truncate": "DELETE$1FROM $2;",
    "drop": "DROP TABLE IF EXISTS $1;",
    "select": "SELECT",
    "insert": "INSERT INTO $1",
    "where": "WHERE",
    "update": "UPDATE $1 ",
    "set": "SET $1",
    "orderby": "ORDER BY $1",
    "returning": "RETURNING $1"
  }.toTable
  stmtSqlite {.compileTime.} = {
    "create": "CREATE TABLE IF NOT EXISTS $1 ($2)",
    "truncate": "DELETE$1FROM $2;",
    "drop": "DROP TABLE IF EXISTS $1;",
    "select": "SELECT",
    "insert": "INSERT INTO $1",
    "where": "WHERE",
    "update": "UPDATE $1 ",
    "set": "SET $1",
    "orderby": "ORDER BY $1;",
    "returning": "" # todo
  }.toTable

proc getDriver*(): DBDriver {.compileTime.} =
  ## Retrieve default Database Driver
  driverPostgres

proc q*(key: string): string {.compileTime.} =
  result =
    case getDriver():
      of driverPostgres:
        stmtPgsql[key]
      else:
        stmtSqlite[key]

proc sql*(node: Query, k: string): string =
  ## Transform given SQL Query to stringified SQL
  case node.nt:
  of ntCreate:
    var fields: seq[string]
    for col in node.createColumns:
      if col.cReference != nil:
        # CONSTRAINT fk_author FOREIGN KEY(author_id) REFERENCES author(id)
        if Constraints.notnull in col.cConstraints:
          add fields,
            col.cName & indent($DataType.Int, 1) & indent($(Constraints.notnull), 1)
        else:
          add fields,
            col.cName & indent($DataType.Int, 1)
        var field = "CONSTRAINT"
        add field, indent("fk_" & col.cName & "_" & col.cReference.model, 1)
        add field, indent($(col.cConstraints[0]), 1)
        add field, "(" & col.cName & ")"
        add field, indent("REFERENCES", 1)
        add field, indent(col.cReference.model & "(" & col.cReference.colName & ")", 1)
        add fields, field
      elif col.cConstraints.len > 0:
        var field = col.cName & indent($col.cType, 1)
        for constr in col.cConstraints:
          case constr
          of Constraints.default:
            add field,
              indent($(Constraints.default), 1) &
                indent(col.getDefaultValue(), 1)
          else:
            add field, indent($(constr), 1)
        add fields, field
      else:
        var colNameType = col.cName & indent($col.cType, 1)
        if col.cType in {Varchar, Char}:
          add colNameType, "("
          add colNameType, col.cTypeArgs.join(",")
          add colNameType, ")"
        add fields, colNameType
    result = q("create") % [k, fields.join(", ")]
  of ntSelect:
    result = q("select")
    if node.selectColumns.len == 0:
      add result, indent("*", 1)
    else:
      add result, node.selectColumns.mapIt(indent(it, 1)).join(",")
    add result, indent("FROM", 1)
    add result, indent(node.selectTable, 1)
    if node.selectCondition != nil:
      add result, sql(node.selectCondition, k)
    if node.selectOrder.len > 0:
      add result, indent(q("orderby") %
        join(node.selectOrder.mapIt(it[0] & indent($(it[1]), 1)), ","), 1)
  of ntWhere:
    for branch in node.whereBranches:
      add result, q("where").indent(1)
      var val: string
      when nimvm:
        val = 
          case StaticSchema[k].tColumns[branch.infixLeft].cType
          of Boolean, Int, Numeric, Money, Serial:
            branch.infixRight
          else:
            "'" & branch.infixRight & "'"
      else:
        val = 
          case Models[k].tColumns[branch.infixLeft].cType
          of Boolean, Int, Numeric, Money, Serial:
            branch.infixRight
          else:
            "'" & branch.infixRight & "'"
      add result, indent(branch.infixLeft, 1)
      add result, indent($branch.infixOp, 1)
      add result, indent(val, 1)
  of ntUpdate, ntUpdateAll:
    result = q("update") % k
    var updates: seq[string]
    for f in node.updateFields:
      var val =
        case f[0].cType
        of Boolean, Int, Numeric, Money, Serial:
          f[1]
        else:
          "'" & f[1] & "'"
      add updates, f[0].cName & " = " & val
    add result, q("set") % updates.join(", ")
    case node.nt
    of ntUpdate:
      if likely(node.updateCondition != nil):
        add result, sql(node.updateCondition, k)
    else: discard # ntUpdateAll
  of ntDrop:
    result = q("drop") % k
  of ntTruncate:
    if node.truncateColumns.len == 0:
      result = q("truncate") % [indent("", 1), k]
    else:
      result = q("truncate") % [node.truncateColumns.join(",").indent(1), k]
  of ntInsert, ntUpsert:
    result = q("insert") % k
    var i = 0
    let total =
      if node.insertFields.len == 0: 0
      else: node.insertFields.len - 1
    var cols, values = indent("(", 1)
    for k, v in node.insertFields:
      add cols, k
      add values, "?"
      if i != total:
        add cols, "," & spaces(1)
        add values, "," & spaces(1)
      inc i
    add cols, indent(")", 0)
    add values, indent(")", 0)
    add result, cols
    add result, indent("VALUES", 1)
    add result, values
    # case node.nt
    # of ntUpsert:
    #   add result, "ON CONFLICT($1)" % "id"
    # else: discard
    setLen(cols, 0)
    setLen(values, 0)
    # if node.insertReturn != nil:
      # add result, sql(node.insertReturn, k)
  of ntReturn:
    result = indent(q("returning") % [node.returnColName], 1)
  else: discard


#
# Runtime
#
template checkConstraints(constr: openarray[Constraints], stmt: typed) {.dirty.} =
  for x in constr:
    if unlikely(x in col.cConstraints):
      raise newException(EnimsqlModelDefect,
        "Invalid constraints")
  stmt

template checkModelIdent(x) {.dirty.} =
  if unlikely(models.hasKey(x)):
    raise newException(EnimsqlModelDefect,
      "Duplicate model `" & x & "`")

template checkModelExists(x) {.dirty.} =
  if unlikely(not models.hasKey(x)):
    raise newException(EnimsqlModelDefect,
      "Unknown model `" & x & "`")

proc create*(models: SchemaTable,
    modelName: string, callbackBuilder: SchemaBuilder): SQLQuery =
  checkModelIdent(modelName)
  var schemaTable = Schema()
  callbackBuilder(schemaTable)
  var createStmt: Query = newCreateStmt()
  let tableName = modelName.getTableName
  for k, col in schemaTable:
    add createStmt.createColumns, col
  if createStmt.createColumns.len != 0:
    result = SQLQuery sql(createStmt, tableName)
  models[modelName] = (tableName, schemaTable)

proc add*(schema: Schema, name: string,
    coltype = DataType.Text): SQLColumn {.discardable.} =
  ## Add a new field to a runtime Model 
  if likely(not schema.hasKey(name)):
    result = SQLColumn(cName: name)
    result.ctype = coltype
    schema[name] = result
  else:
    raise newException(EnimsqlModelDefect,
      "Duplicate column `" & name & "`")

proc unique*(col: SQLColumn): SQLColumn {.discardable.} =
  ## Set `col` SQLColumn as `UNIQUE`
  if likely(Constraints.unique notin col.cConstraints):
    add col.cConstraints, Constraints.unique
    result = col
  else:
    raise newException(EnimsqlModelDefect,
      "Duplicate constraint `" & $(Constraints.unique) & "`")

proc primaryKey*(col: SQLColumn): SQLColumn {.discardable.} =
  ## Set `col` SQLColumn as `PRIMARY KEY`
  if likely(Constraints.pk notin col.cConstraints):
    checkConstraints [Constraints.unique]:
      add col.cConstraints, Constraints.pk
      return col
    # raise newException(EnimsqlModelDefect,
      # "Constraints conflict `" & $(Constraints.unique) & "` and `" & $(Constraints.pk) & "`")
  else:
    raise newException(EnimsqlModelDefect,
      "Duplicate constraint `" & $(Constraints.pk) & "`")

proc pk*(col: SQLColumn): SQLColumn {.discardable.} =
  ## An alias of `primaryKey`
  primaryKey(col)

proc default*(col: SQLColumn, value: SQLValue): SQLColumn {.discardable.} =
  ## Set a default `SQLValue`
  if likely(col.cDefault == nil):
    if col.cType == value.dt:
      col.cDefault = value
      add col.cConstraints, Constraints.default
      return col
    else:
      raise newException(EnimsqlModelDefect,
        "Type mismatch `" & col.cName & "` is type of `" & $(col.cType) & "`. Got `" & $(value.dt) & "`")
  raise newException(EnimsqlModelDefect,
    "Column `" & col.cName & "` already has a DEFAULT bound to it")

proc null*[S: SQLColumn](col: S): S {.discardable.} =
  checkConstraints [Constraints.nullable, Constraints.notnull]:
    add col.cConstraints, Constraints.nullable
    result = col

proc notnull*[S: SQLColumn](col: S): S {.discardable.} =
  checkConstraints [Constraints.nullable, Constraints.notnull]:
    add col.cConstraints, Constraints.notnull
    result = col

#
# Runtime Query Builder
#
proc table*(models: SchemaTable, modelName: string): Model =
  checkModelExists(modelName)
  return models[modelName]

template checkColumn(k: string, stmt) =
  if likely(result[0].tColumns.hasKey(k)):
    stmt
  else:
    raise newException(EnimsqlQueryDefect,
      "Column `" & k & "` does not exist")

proc select*(model: Model, cols: varargs[string]): QueryBuilder =
  result = (model, newSelectStmt())
  add result[1].selectTable, model.tName
  for col in cols:
    checkColumn col:
      if unlikely(col == "*"):
        raise newException(EnimsqlModelDefect,
          "Invalid `*` selector. Leave `cols` empty for selecting all columns")
      add result[1].selectColumns, col

proc where*(q: QueryBuilder, key: string,
    op: SQLOperator, val: string): QueryBuilder {.discardable.} =
  ## Use `where` proc to add "WHERE" clauses to the query
  result = q
  checkColumn key:
    var whereStmt = newWhereStmt()
    add whereStmt.whereBranches, newInfixExpr(key, val, op)
    case q[1].nt
    of ntSelect:
      q[1].selectCondition = whereStmt
    of ntUpdate:
      q[1].updateCondition = whereStmt
    else: 
      raise newException(EnimsqlQueryDefect,
        "Invalid use of where statement for " & $q[1].nt)

proc where*(q: QueryBuilder, key, val: string): QueryBuilder {.discardable.} =
  result = q.where(key, EQ, val)

proc orWhere*(q: QueryBuilder, handle: proc(q: QueryBuilder)): QueryBuilder =
  ## Use the `orWhere` proc to join a clause to the
  ## query using the `or` operator
  handle(q)
  result = q

proc update*(model: Model,
    pairs: varargs[(string, string)]): QueryBuilder =
  result = (model, newUpdateStmt())
  ## The `update` should be used to update existing
  ## records. This proc requires a `where` statement
  for pair in pairs:
    checkColumn pair[0]:
      add result[1].updateFields, (result[0].tColumns[pair[0]], pair[1])

proc update*(model: Model, key, val: string): QueryBuilder =
  result = (model, newUpdateStmt())
  ## The `update` should be used to update existing
  ## records. This proc requires a `where` statement
  checkColumn key:
    add result[1].updateFields, (result[0].tColumns[key], val)

proc updateAll*(model: Model,
    pairs: varargs[(string, string)]): QueryBuilder =
  ## Create an `UPDATE` query to update all existing records
  result = (model, newUpdateAllStmt())
  for pair in pairs:
    checkColumn pair[0]:
      add result[1].updateFields, (result[0].tColumns[pair[0]], pair[1])

proc insert*(model: Model, pairs: varargs[(string, string)]): QueryBuilder =
  ## Create an `INSERT` statement
  result = (model, newInsertStmt())
  for pair in pairs:
    checkColumn pair[0]:
      result[1].insertFields[pair[0]] = pair[1]

proc insert*(model: Model, entry: OrderedTable[string, string]): QueryBuilder =
  ## Create an `INSERT` statement
  result = (model, newInsertStmt())
  for k, v in entry:
    checkColumn k:
      discard
  result[1].insertFields = entry

proc orderBy*(q: QueryBuilder, key: string, order: Order = Order.ASC): QueryBuilder =
  ## Add `orderBy` clause to the current `QueryBuilder`
  assert q[1].nt == ntSelect
  result = q
  checkColumn key:
    add q[1].selectOrder, (key, order)

template getAll*(q: QueryBuilder): untyped =
  ## Execute the query and returns a `Collection`
  ## instance with the available results
  var rows = getAllRows(dbcon,
    SQLQuery(sql(q[1], q[0].tName)))
  var results = initCollection[SQLValue]()
  if rows.len > 0:
    if q[1].selectColumns.len > 0:
      for row in rows:
        var e = Entry[SQLValue]()
        for i in 0..row.high:
          e[q[1].selectColumns[i]] = newSQLText(row[i])
        add results, e
    else:
      let keys = q[0].tColumns.keys.toSeq()
      for row in rows:
        var e = Entry[SQLValue]()
        for i in 0..row.high:
          e[keys[i]] = newSqlValue(q[0].tColumns[keys[i]].cType, row[i])
        add results, e
  results

macro initModel*(T: typedesc, x: seq[string]): untyped =
  var callNode = ident("new" & $T)
  result = newStmtList()
  add result, quote do:
    `callNode`(`x`)

macro `@`*(x: untyped): untyped =
  ## Convert expression to pairs of `column_key: some value`
  ## This macro is similar with `%*` from `std/json`
  case x.kind
  of nnkTableConstr:
    var x = x
    for i in 0..<x.len:
      x[i].expectKind nnkExprColonExpr
      case x[i][1].kind
      of nnkIntLit:
        x[i][1] = newLit($(x[i][1].intVal))
      of nnkFloatLit:
        x[i][1] = newLit($(x[i][1].floatVal))
      of nnkIdent:
        if x[i][1].eqIdent"true" or x[i][1].eqIdent "false":
          x[i][1] = newLit(parseBool(x[i][1].strVal))
      else: discard
    return newCall(ident"toOrderedTable", x)
  else: error("Invalid expression, expected curly braces")

template getAll*(q: QueryBuilder, T: typedesc): untyped =
  ## Execute the query and returns a collection of objects `T`.
  ## This works only for a `Model` defined at compile-time
  let results = getAllRows(dbcon,
    SQLQuery(sql(q[1], q[0].tName)))
  var collections: seq[T]
  for res in results:
    add collections, initModel(T, res)
  collections

template exec*(q: QueryBuilder): untyped =
  ## Use it inside a `withDB` context to execute a query
  case q[1].nt
  of ntUpdate:
    assert q[1].updateCondition != nil
    dbcon.exec(SQLQuery sql(q[1], q[0].tName))
  of ntInsert:
    dbcon.exec(SQLQuery sql(q[1], q[0].tName), q[1].insertFields.values.toSeq)
  else: discard # todo other final checks before executing the query

template execGet*(q: QueryBuilder, pk = "id"): untyped =
  ## Use it inside a `withDB` context to execute an `INSERT` query.
  ## Use a different `pk` name if your primary key is not named `id`.
  assert q[1].nt == ntInsert
  dbcon.tryInsert(SQLQuery sql(q[1], q[0].tName), pk,
    q[1].insertFields.values.toSeq)

template exec*(q: SQLQuery): untyped =
  ## Use it inside a `withDB` context to execute a query
  dbcon.exec(q)

template tryExec*(q: SQLQuery): untyped =
  ## Use it inside a `withDB` context to try execute a query
  dbcon.tryExec(q)
