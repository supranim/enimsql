# Enimsql is an object-driven ORM for PostgreSQL.
# Built with Nim's powerful Macros.
# 

import std/tables
import std/macros except name

import std/jsonutils
import std/json

from std/strutils import `%`, indent, join, toLowerAscii, endsWith

type
    Comparators* = enum
        EQ = "="
        GT = ">"
        LT = "<"
        GTE = ">="
        LTE = "<="
        NEQ = "<>"
        BETWEEN = "BETWEEN"
        LIKE = "LIKE"
        IN = "IN"

    Conditionals* = enum
        AND = "AND"
        OR = "OR"
        NOT = "NOT"

    Order* = enum
        ASC = "ASC"
        DESC = "DESC"

    StatementType = enum
        SelectStmt = "SELECT"
        DeleteStmt = "DELETE"
        UpdateStmt = "UPDATE"
        UpdateAllStmt = "UPDATE"

    CompFilter* = tuple[colName: string, op: Comparators, value: string]
    KeyValueTuple* = tuple[colName, newValue: string]

    Syntax = ref object
        case stmtType: StatementType
            of DeleteStmt: discard
            of SelectStmt:
                selectStmt: seq[string]
            of UpdateStmt, UpdateAllStmt:
                updateSetStmt: seq[KeyValueTuple]

        whereStmt: seq[CompFilter]
        countWhere: int
        fromStmt: string

    AbstractModel* = object of RootObj
        metaTableName: string
        metaModelName: string
        sql: Syntax

    ModelColumns = Table[string, string]
    
    Models = object
        storage: Table[string, ModelColumns]

    EnimsqlError = ref object of CatchableError
    DatabaseDefect = object of Defect

var Model* = Models()
var modelsIdent {.compileTime.}: seq[string]

# dumpAstGen:
#     type
#         MyModel* = ref object of AbstractModel
#             test*: string
#             aha*: ok

template checkObjectIntegrity(modelIdent: typedesc[ref object]) =
    static:
        if $modelIdent notin modelsIdent:
            raise EnimsqlError(msg: "Unknown objects cannot be used as models.")

template checkModelColumns(modelIdent: string, columns:varargs[string]) =
    let modelStruct = Model.storage[modelIdent]
    for colId in columns:
        if not modelStruct.hasKey(colId):
            raise EnimsqlError(msg: "Unknown column name \"$1\" for model \"$2\"" % [colId, modelIdent])

template checkModelColumns(modelIdent: string, columns:varargs[KeyValueTuple]) =
    let modelStruct = Model.storage[modelIdent]
    for col in columns:
        if not modelStruct.hasKey(col.colName):
            raise EnimsqlError(msg: "Unknown column name \"$1\" for model \"$2\"" % [col.colName, modelIdent])

template checkDuplicates(colName, modelName: string, refCol: var seq[string]) =
    if colName in refCol:
        raise newException(DatabaseDefect,
            "Duplicated column name \"$1\" for \"$2\" model." % [colName, modelName])

proc getModelName(id: string): string =
    ## Retrieve the name of the table based on Model's name,
    ## converted to lowercase. Gramatically, the name of the
    ## model must be set in a singular form.
    ## Enimsql will automatically set the database table
    ## names in plural form. Names that ends with
    ## "s", "es", "sh", "ch", "x" or "z" will append to "es"
    var esSuffix = @["s", "es", "sh", "ch", "x", "z"]
    var modelName = id.toLowerAscii()
    for esSfx in esSuffix:
        if modelName.endsWith(esSfx):
            modelName = "$1es" % [modelName]
            return modelName
    result = "$1s" % [modelName]

# proc get*[M: typedesc[object]](model: M, id: string): string =
#     result = Model.storage[id]

proc initTable[M](model: typedesc[ref M], stmtType: StatementType): ref M =
    ## Initialize a ``ref object`` for current ``Model``
    result = new model
    result.sql = new Syntax
    result.sql.stmtType = stmtType
    result.metaModelName = $model
    result.metaTableName = getModelName($model)

proc exists[M](model: ref M, id: string): ref M =
    ## Test the existence of any record in a subquery
    static: checkObjectIntegrity(model)

proc select*[M](model: typedesc[ref M], columns: varargs[string]): ref M =
    ## Select specific columns from current model
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
    ## Safe procedure for updating records in a ``Model`` followed by a ``WHERE`` statement.
    ## For updating all records use ``updateAll`` proc.
    static: checkObjectIntegrity(model)
    if cols.len != 0:
        checkModelColumns($model, cols)
    result = model.initTable(UpdateStmt)
    var refCol: seq[string]
    for col in cols:
        checkDuplicates(col.colName, result.metaModelName, refCol)
        result.sql.updateSetStmt.add(col)

proc updateAll*[M](model: typedesc[ref M], cols: varargs[KeyValueTuple]): ref M =
    ## Update all records in a ``Model`` with given columns and values.
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
    ## Handle ``WHERE`` statements with filtering support.
    ## All ``Comparators`` are supported.
    for filter in filters:
        model.sql.whereStmt.add filter
        inc model.sql.countWhere
    result = model

proc whereIn*[M](model: ref M, column: string, values:openarray[string]): ref M =
    ## https://www.w3schools.com/sql/sql_in.asp
    ## Handle ``WHERE`` IN operator
    for value in values:
        model.sql.whereIn.add value
    result = model

proc whereNotIn*[M](model: ref M, column: string, values:openarray[string]): ref M =
    ## https://www.w3schools.com/sql/sql_in.asp
    ## TODO validate col name
    for value in values:
        model.sql.whereNotIn.add value
    result = model

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
            add syntax, indent("'" & model.sql.updateSetStmt[i].newValue & "'", 1)
            if i != updateStmtLen:
                add syntax, ","

    if model.sql.whereStmt.len != 0:
        # if model.sql.countWhere == 1:
        add syntax, indent("WHERE", 1)
        for whereStmt in model.sql.whereStmt:
            add syntax, indent(whereStmt.colName, 1)
            add syntax, indent($whereStmt.op, 1)
            add syntax, indent("'" & whereStmt.value & "'", 1)
            if model.sql.countWhere > 1:
                add syntax, indent($AND, 1)
            dec model.sql.countWhere
    else:
        if model.sql.stmtType == UpdateStmt:
            raise newException(DatabaseDefect,
                "Missing \"WHERE\" statement. Use `updateAll` procedure for updating all records in the table.")
    echo syntax
    # result = $(toJson(model))

macro model*(modelId: static string, fields: untyped) =
    ## Creates a new Model and store in the ``ModelRepository`` table
    if modelId in modelsIdent:
        raise EnimsqlError(msg: "A model with name \"$1\" already exists." % [modelId])
    fields.expectKind nnkStmtList
    var metaCols: ModelColumns
    var colFields = nnkRecList.newTree()
    for field in fields:
        if field.kind == nnkCall:
            # Handle private fields
            if field[0].kind == nnkIdent:
                field[1].expectKind nnkStmtList
                let fieldId = field[0].strVal
                let fieldType = field[1][0].strVal
                # echo fieldId & " " & fieldType
                metaCols[fieldId] = fieldType
                colFields.add(
                    nnkIdentDefs.newTree(
                        nnkPostfix.newTree(
                            ident "*",
                            ident fieldId
                        ),
                        ident fieldType,
                        newEmptyNode()
                    )
                )

            elif field[0].kind == nnkPragmaExpr:
                let fieldId = field[0][0].strVal
                let fieldType = field[1][0].strVal
                let fieldPragmas = field[0][1]
                for fieldPragma in fieldPragmas:
                    echo fieldPragma.strVal

                # echo fieldId & " " & fieldType
                metaCols[fieldId] = fieldType
                colFields.add(
                    nnkIdentDefs.newTree(
                        nnkPostfix.newTree(
                            ident "*",
                            ident fieldId
                        ),
                        ident fieldType,
                        newEmptyNode()
                    )
                )

    modelsIdent.add(modelId)
    result = newStmtList()
    result.add(
        nnkTypeSection.newTree(
            nnkTypeDef.newTree(
                nnkPostfix.newTree(
                    ident "*",
                    ident modelId
                ),
                newEmptyNode(),
                nnkRefTy.newTree(
                    nnkObjectTy.newTree(
                        newEmptyNode(),
                        nnkOfInherit.newTree(
                            ident "AbstractModel"
                        ),
                        colFields
                    )
                )
            )
        )
    )

    result.add quote do:
        Model.storage[`modelId`] = `metaCols`