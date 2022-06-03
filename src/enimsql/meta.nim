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
        WhereStmt = "WHERE"
        WhereLikeStmt = "$1 LIKE '$2'"

    CompFilter* = tuple[colName: string, op: Comparators, value: string]
    KeyValueTuple* = tuple[colName, colValue: string]

    Syntax = ref object
        case stmtType: StatementType
            of DeleteStmt: discard
            of SelectStmt:
                selectStmt: seq[string]
            of UpdateStmt, UpdateAllStmt:
                updateSetStmt: seq[KeyValueTuple]
            else: discard

        whereStmt: seq[CompFilter]
        whereLikeStmt: seq[tuple[colName, valueLike: string]]
        countWhere: int

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
    ## Initialize a `ref object` for current `Model`
    result = new model
    result.sql = new Syntax
    result.sql.stmtType = stmtType
    result.metaModelName = $model
    result.metaTableName = getModelName($model)