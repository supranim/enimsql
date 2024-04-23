import std/[macros, tables, strutils,
  sequtils, enumutils, macrocache]

import ./private/query
export query

from pkg/db_connector/db_postgres import SQLQuery, sql
export sql

when not defined release:
  import std/[json, jsonutils]
  proc `$`*(model: AbstractModel): string =
    pretty(model.toJson(), 2)

#
# Compile-time API
#

# Forward declaration
proc checkModelExists*(id: NimNode) {.compileTime.}
proc checkColumn*(model: NimNode, name: string): bool {.compileTime.}

proc newSQLColumn(n: NimNode, colName: string, pragmas: NimNode = nil): SQLColumn {.compileTime.} =
  ## Compile-time procedure for converting `NimTypeKind` to Enimsql `DataType`
  # https://nim-lang.org/docs/macros.html#NimTypeKind
  # https://www.postgresql.org/docs/current/datatype.html
  result = SQLColumn(cName: colName)
  if n.kind == nnkDotExpr:
    checkModelExists(n[0])
    if n[0].checkColumn($n[1]):
      add result.cConstraints, Constraints.fk
      n[0] = ident(StaticSchema[$n[0]].tName)
      result.cReference = Reference(model: $n[0], colName: $n[1])
    else:
      error("Unknown column `" & $n[1] & "` (Model: " & $n[0] & ")", n[1])
  else:
    if n.kind notin {nnkIdent, nnkCall, nnkAsgn}:
      raise newException(EnimsqlModelDefect,
        "Cannot convert `NimTypeKind` to `DataType`: $1" % [$n.kind])
    var
      nimType: NimTypeKind
      dataTypeIdent: string
    try:
      case n.kind
      of nnkIdent:
        dataTypeIdent = n.strVal.toLowerAscii
        result.cType = parseEnum[DataType](dataTypeIdent)
      of nnkCall:
        dataTypeIdent = n[0].strVal.toLowerAscii
        result.cType = parseEnum[DataType](dataTypeIdent)
        case n[1].kind
        of nnkIntLit:
          add result.cTypeArgs, $(n[1].intVal)
        of nnkStrLit:
          add result.cTypeArgs, n[1].strVal
        else: discard # todo
      of nnkAsgn:
        # define columns with a `DEFAULT` value
        dataTypeIdent = n[0].strVal.toLowerAscii
        result.cType = parseEnum[DataType](dataTypeIdent)
        result.cDefault = newValue(n[1], result.cType)
        add result.cConstraints, Constraints.default
      else: discard
    except ValueError:
      raise newException(EnimsqlModelDefect,
        "Unknown DataType: $1" % [dataTypeIdent])
  for p in pragmas:
    for f in Constraints:
      if f.symbolName == p.strVal:
        let constr = Constraints(f.symbolRank)
        add result.cConstraints, constr

let attemptAccessNil {.compileTime.} = "Attempt to access field `$1` of a nil model"

macro newModel*(id, fields: untyped) =
  if StaticSchema.hasKey(id.strVal):
    raise newException(EnimsqlModelDefect, "Model \"$1\" already exists." % [id.strVal])
  expectKind fields, nnkStmtList
  result = newStmtList()
  var
    objFieldDefs = newNimNode nnkIdentDefs
    staticSchemaTable = newOrderedTable[string, SQLColumn]()
  for f in fields:
    case f.kind
    of nnkCall:
      case f[0].kind
      of nnkIdent:
        expectKind f[1], nnkStmtList
        add objFieldDefs, f[0]
        # add objFieldDefs, nnkPostfix.newTree(ident"*", f[0])
        staticSchemaTable[f[0].strVal] = newSQLColumn(f[1][0], $f[0])
      of nnkPragmaExpr:
        # add objFieldDefs, nnkPostfix.newTree(ident"*", f[0][0])
        add objFieldDefs, f[0][0]
        staticSchemaTable[f[0][0].strVal] = newSQLColumn(f[1][0], $f[0][0], f[0][1])
      else: discard
    else: discard
  add objFieldDefs, ident"SQLValue"
  add objFieldDefs, newEmptyNode()
  var runtimeObjFields = newNimNode nnkRecList
  add runtimeObjFields, objFieldDefs
  add result,
    nnkTypeSection.newTree(
      nnkTypeDef.newTree(
        nnkPostfix.newTree(ident "*", id),
        newEmptyNode(),
        # nnkPragma.newTree(ident"getters"),
        nnkObjectTy.newTree(
          newEmptyNode(),
          nnkOfInherit.newTree(
            ident "AbstractModel"
          ),
          runtimeObjFields
        )
      )
    )
  # get all columns and generate
  # read-only procs for each of them
  for colId in runtimeObjFields[0][0..^3]:
    var i = 0
    var procName: string
    let colName = colId.strVal
    while i <= colName.high:
      case colName[i]
      of '_':
        inc i
        while true:
          case colName[i]
          of '_':
            inc i
          else: break
        add procName, colName[i].toUpperAscii
      else:
        add procName, colName[i]
      inc i
    procName = "get" & capitalizeAscii(procName)
    add result,
      newProc(
        nnkPostfix.newTree(ident"*", ident(procName)),
        params = [
          ident"SQLValue",
          nnkIdentDefs.newTree(ident"m", id, newEmptyNode())
        ],
        body = newStmtList().add(
          newCommentStmtNode("Returns `" & colName & "` from `" & $(id) & "` model"),
          # returnSqlValueNode
          nnkReturnStmt.newTree(newDotExpr(ident"m", ident(colName)))
        )
      )
  var bodyInitModel = newStmtList()
  add bodyInitModel, newCommentStmtNode("Create a new `" & $(id) & "` object")
  var i = 0
  for mfield in runtimeObjFields[0][0..^3]:
    add bodyInitModel,
      newAssignment(
        newDotExpr(
          ident"result",
          mfield
        ),
        newCall(
          ident("newSQL" & symbolName(staticSchemaTable[mfield.strVal].cType)),
          nnkBracketExpr.newTree(
            ident"x",
            newLit(i)
          )
        )
      )
    inc i
  add result,
    newProc(
      nnkPostfix.newTree(ident"*", ident("new" & id.strVal)),
      params = [
        id,
        nnkIdentDefs.newTree(
          ident"x",
          nnkBracketExpr.newTree(
            ident"varargs",
            ident"string"
          ),
          newEmptyNode()
        )
      ],
      body = bodyInitModel
    )

  let table = getTableName(id.strVal)
  StaticSchema[id.strVal] = (table, staticSchemaTable)
  let id = genSym(nskVar, "schema")
  add result, quote do:
    var `id` = Schema()
  for k, v in staticSchemaTable:
    add result, quote do:
      block:
        `id`[`k`] = `v`
  add result, quote do:
    block:
      Models[`table`] = (`table`, `id`)

# const beforeActionTable = CacheTable"BeforeActionTable"
# template before*(body: untyped) =
#   macro initBefore(id: static string, x: untyped) =
#     var startupBody =
#       newCall(ident"withDB", newStmtList().add(x))
#     beforeActionTable[id] = newStmtList().add(startupBody)
#   initBefore(instantiationInfo().filename, body)

# macro runBefore*() =
#   result = newStmtList()
#   for x, z in beforeActionTable:
#     add result, z

proc checkModelExists*(id: NimNode) {.compileTime.} = 
  ## Compile-time proc to determine if a Model exists for given `id`
  if id.kind in {nnkIdent, nnkSym}:
    if not StaticSchema.hasKey($id):
      raise newException(EnimsqlModelDefect,
        "Model `$1` was not registered properly" % [$id])
  else: raise newException(EnimsqlModelDefect, "Invalid model name, expect nnkIdent or nnkSym")

proc checkColumn*(model: NimNode, name: string): bool {.compileTime.} =
  ## Compile-time proc to check if `model` contains a specific `SQLColumn` by name
  result = StaticSchema[$model].tColumns.hasKey(name)

proc getColumn*(model: NimNode, name: string): SQLColumn {.compileTime.} =
  ## Compile-time proc to retreive a specific `SQLColumn` by name
  result = StaticSchema[$model].tColumns[name]

iterator columns*(model: NimNode): SQLColumn =
  ## Compile-time iterator to walk available
  checkModelExists(model)
  for name, col in StaticSchema[$model].tColumns:
    yield col

#
# Query - Compile-time API
#
template executeSQL(x: string, then: untyped) {.dirty.} =
  var
    execCall = newCall(ident"exec", ident"dbcon")
    sqlCall = newCall ident"sql"
  add sqlCall, newLit(x)
  add execCall, sqlCall
  if then.kind == nnkStmtList:
    execCall[0] = ident("tryExec")
    add result,
      nnkBlockStmt.newTree(
        newEmptyNode(),
        nnkStmtList.newTree(
          newLetStmt(ident"status", execCall),
          then
        )
      )

template tryExec*(sqlCommand: string, returnIdent = "status") =
  var
    callExec = newCall(ident"tryExec", ident"dbcon")
    callSql = newCall ident"sql"
  add callSql, newLit sqlCommand
  add callExec, callSql
  add result,
    nnkBlockStmt.newTree(
      newEmptyNode(),
      nnkStmtList.newTree(
        newLetStmt(ident returnIdent, callExec),
        then
      )
    )

template exec(sqlCommand: string, sqlValues: seq[NimNode] = @[]) =
  var
    callExec = newCall(ident"exec", ident"dbcon")
    callSql = newCall ident"sql"
  add callSql, newLit sqlCommand
  add callExec, callSql
  for v in sqlValues:
    add callExec, v
  add result, callExec

macro initTable*(model: untyped) =
  ## Create a table representation of `Model`
  checkModelExists(model)
  result = newStmtList()
  let table = getTableName($model)
  var createStmt: Query = newCreateStmt()
  var cols: seq[SQLColumn]
  for col in model.columns():
    add createStmt.createColumns, col
    add cols, col
  if createStmt.createColumns.len != 0:
    var
      execCall = newCall(ident"exec", ident"dbcon")
      sqlCall = newCall ident"sql"
    add sqlCall, newLit sql(createStmt, table)
    add execCall, sqlCall
    add result, execCall
  else:
    raise newException(EnimsqlModelDefect,
      "Tried to create a table using a Model without fields")

macro tryCreate*[M](model: typedesc[M], then: untyped) =
  ## Create a table based on `Model`, `then` return the
  ## status of the query as `status`
  checkModelExists(model)
  result = newStmtList()
  let table = getTableName($model)
  var createStmt: Query = newCreateStmt()
  for col in model.columns():
    add createStmt.createColumns, col
  if createStmt.createColumns.len != 0:
    var
      execCall = newCall(ident"tryExec", ident"dbcon")
      sqlCall = newCall ident"sql"
    add sqlCall, newLit sql(createStmt, table)
    add execCall, sqlCall
    add result,
      nnkBlockStmt.newTree(
        newEmptyNode(),
        nnkStmtList.newTree(
          newLetStmt(ident"status", execCall),
          then
        )
      )
  else:
    raise newException(EnimsqlModelDefect,
      "Tried to create a table using a Model without fields")

macro delete*[M](model: typedesc[M]) =
  ## Delete a table represented by `Model`
  checkModelExists(model)
  result = newStmtList()
  let table = getTableName($model)
  var dropStmt: Query = newDropStmt()
  exec sql(dropStmt, table)

macro delete*(model: untyped, then: untyped) =
  ## Delete a table represented by `Model`
  checkModelExists(model)
  result = newStmtList()
  let table = getTableName($model)
  var dropStmt: Query = newDropStmt()
  tryExec sql(dropStmt, table)

template drop*(model: untyped) =
  ## Delete a table represented by `Model`
  delete(model)

macro clear*(model: untyped, then: untyped) =
  ## Delete all data from table.
  checkModelExists(model)
  result = newStmtList()
  let table = getTableName($model)
  var clearStmt: Query = newClearStmt()
  executeSQL sql(clearStmt, table):
    then

macro insertRow*(model: untyped, row: untyped,
    then, err: untyped = nil) =
  ## Insert a new row in a table
  checkModelExists(model)
  result = newStmtList()
  let table = getTableName($model)
  var insertStmt: Query = newInsertStmt()
  for col in model.columns():
    if Constraints.pk in col.cConstraints:
      # todo support composite primary key
      insertStmt.insertReturn =
        Query(nt: ntReturn, returnColName: col.cName)
          # todo support aliasing
  var i = 0
  var values: seq[NimNode]
  for kv in row:
    expectKind(kv, nnkAsgn)
    expectKind(kv[0], nnkIdent)
    if not model.checkColumn($kv[0]):
      raise newException(EnimsqlModelDefect,
        "Unknown column `" & $row[i][0] & "` (Model: " & $model & ")")
    # insertStmt.insertFields[$kv[0]] = newValue(kv[1], model.getColumn($kv[0]).cType)
    insertStmt.insertFields[$kv[0]] = kv[1].strVal
    add values, kv[1]
  var
    callExec = newCall(ident"tryInsertID", ident"dbcon")
    callSql = newCall ident"sql"
  add callSql, newLit sql(insertStmt, table)
  add callExec, callSql
  for v in values:
    add callExec, v
  if err == nil:
    add result,
      nnkBlockStmt.newTree(
        newEmptyNode(),
        nnkStmtList.newTree(
          newLetStmt(ident "id", callExec),
          then
        )
      )
  else:
    add result,
      nnkBlockStmt.newTree(
        newEmptyNode(),
        nnkStmtList.newTree(
          nnkTryStmt.newTree(
            nnkStmtList.newTree(
              newLetStmt(ident "id", callExec),
              then
            ),
            nnkExceptBranch.newTree(
              nnkInfix.newTree(ident"as", ident"DbError", ident"e"),
              err
            )
          )
        )
      )

macro where*(model, stmt: untyped): untyped =
  checkModelExists(model)
  result = newStmtList()
  let table = getTableName($model)
  var insertStmt: Query = newWhereStmt()
  var i = 0
  var values: seq[NimNode]
  for kv in stmt:
    expectKind(kv, nnkInfix)
    expectKind(kv[1], nnkIdent) # column name
    if not model.checkColumn($kv[1]):
      raise newException(EnimsqlModelDefect,
        "Unknown column `" & $stmt[i][1] & "` (Model: " & $model & ")")

  result.add(newLit("x"))

macro generateSQLValueHandlers(sqlv: typed) =
  result = newStmtList()
  let impl = sqlv.getImpl()
  var caseBranches = newNimNode(nnkCaseStmt)
  add caseBranches, ident"dt" # `case dt:`
  for f in impl[2][1..^1]:
    let procName = "newSQL" & $f[0]
    let fName = f[0]
    # create a setter proc for each DataType field
    add result,
      newProc(
        nnkPostfix.newTree(ident"*", ident procName),
        params = [
          ident "SQLValue",
          nnkIdentDefs.newTree(
            ident"x",
            ident"string",
            newEmptyNode()
          )
        ],
        body = nnkStmtList.newTree(
          newCommentStmtNode("Create a new `SQLValue` of type `DataType." & $f[0] & "`"),
          # returnSqlValueNode
          nnkObjConstr.newTree(
            ident"SQLValue",
            nnkExprColonExpr.newTree(ident"dt", f[0]),
            nnkExprColonExpr.newTree(
              ident"value",
              ident"x"
            )
          )
        )
      )
    # add generated proc to `newSQLValue` case branch
    add caseBranches,
      nnkOfBranch.newTree(
        f[0],
        newStmtList().add(
          newCall(
            ident procName,
            ident "x" # string to DataType
          )
        )
      )
  add result,
    newProc(
      nnkPostfix.newTree(
        ident"*",
        ident"newSqlValue"
      ),
      params = [
        ident"SQLValue",
        nnkIdentDefs.newTree(
          ident"dt",
          ident"DataType",
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          ident"x",
          ident"string",
          newEmptyNode()
        )
      ],
      body = newStmtList().add(caseBranches)
    )

generateSQLValueHandlers(DataType)
