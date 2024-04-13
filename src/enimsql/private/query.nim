import std/[tables, macros, strutils, sequtils]

from pkg/db_connector/db_postgres import SQLQuery

import ./datatype
export datatype

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

  SQLValue* = ref object
    dt*: DataType
    value*: string

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

  Node* = ref object
    case nt*: NodeType
    of ntCreate:
      createColumns*: seq[SQLColumn]
    of ntSelect:
      selectColumns*: seq[string]
      selectTable*: string
      selectCondition*: Node # ntWhere
    of ntInsert, ntUpsert:
      insertFields*: OrderedTable[string, SQLValue]
      insertReturn*: Node # ntReturn node
    of ntInfix:
      infixOp: SQLOperator
      infixLeft, infixRight: string
    of ntWhere:
      whereBranches*: seq[Node] # ntInfix
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

  proc `$`*(node: Node): string =
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

proc newCreateStmt*: Node =
  result = Node(nt: ntCreate)

proc newDropStmt*: Node =
  result = Node(nt: ntDrop)

proc newClearStmt*: Node =
  result = Node(nt: ntTruncate)

proc newInsertStmt*: Node =
  result = Node(nt: ntInsert)

proc newUpsertStmt*: Node =
  result = Node(nt: ntUpsert)

proc newWhereStmt*: Node =
  result = Node(nt: ntWhere)

proc newSelectStmt*: Node =
  result = Node(nt: ntSelect)

proc newInfixExpr*(lhs, rhs: string, op: SQLOperator): Node =
  result = Node(nt: ntInfix)
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
    "returning": "RETURNING $1"
  }.toTable
  stmtSqlite {.compileTime.} = {
    "create": "CREATE TABLE IF NOT EXISTS $1 ($2)",
    "truncate": "DELETE$1FROM $2;",
    "drop": "DROP TABLE IF EXISTS $1;",
    "select": "SELECT",
    "insert": "INSERT INTO $1",
    "where": "WHERE",
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

proc sql*(node: Node, k: string): string =
  ## Transform given SQL Node to stringified SQL
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
        # echo col.cName
        # echo col.colDataTypeArg.repr
        # if col.colDataTypeArg.kind != nnkNilLit:
        #   field = field % [$(col.colDataTypeArg)]
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
  of ntWhere:
    for branch in node.whereBranches:
      add result, q("where").indent(1)
      var val: string
      when nimvm:
        val = 
          case StaticSchema[k].tColumns[branch.infixLeft].cType
          of Text, Varchar, Char:
            "'" & branch.infixRight & "'"
          else:
            branch.infixRight
      else:
        val = 
          case Models[k].tColumns[branch.infixLeft].cType
          of Text, Varchar, Char:
            "'" & branch.infixRight & "'"
          else:
            branch.infixRight
      add result, indent(branch.infixLeft, 1)
      add result, indent($branch.infixOp, 1)
      add result, indent(val, 1)
  of ntDrop:
    result = q("drop") % [k]
  of ntTruncate:
    if node.truncateColumns.len == 0:
      result = q("truncate") % [indent("", 1), k]
    else:
      result = q("truncate") % [node.truncateColumns.join(",").indent(1), k]
  of ntInsert, ntUpsert:
    result = q("insert") % [k]
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
  var createStmt: Node = newCreateStmt()
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

proc select*(model: Model, cols: varargs[string]): (Model, Node) =
  var selectStmt = newSelectStmt()
  add selectStmt.selectTable, model.tName
  for col in cols:
    if likely(model.tColumns.hasKey(col)):
      if unlikely(col == "*"):
        raise newException(EnimsqlModelDefect,
          "Invalid `*` selector. Leave `cols` empty for selecting all columns")
      add selectStmt.selectColumns, col
    else:
      raise newException(EnimsqlQueryDefect, "Column `" & col & "` does not exist")
  return (model, selectStmt)

proc where*(model: (Model, Node), key: string,
    op: SQLOperator, val: string): (Model, Node) =
  var whereStmt = newWhereStmt()
  if likely(model[0].tColumns.hasKey(key)):
    add whereStmt.whereBranches, newInfixExpr(key, val, op)
    model[1].selectCondition = whereStmt
    result = model
  else:
    raise newException(EnimsqlQueryDefect, "Column `" & key & "` does not exist")

template getAll*(model: (Model, Node)): untyped =
  var rows = dbcon.getAllRows(SQLQuery(sql(model[1], model[0].tName)))
  rows

macro initModel*(T: typedesc, x: seq[string]): untyped =
  var callNode = ident("new" & $T)
  # echo callNode.repr
  result = newStmtList()
  add result, quote do:
    `callNode`(`x`)

template getAll*(model: (Model, Node), T: typedesc): untyped =
  let results = dbcon.getAllRows(SQLQuery(sql(model[1], model[0].tName)))
  var collections: seq[T]
  for res in results:
    add collections, initModel(T, res)
  collections

template exec*(q: SQLQuery): untyped =
  dbcon.exec(q)

template tryExec*(q: SQLQuery): untyped =
  dbcon.tryExec(q)