# A simple ORM for poets
#
# (c) 2021 Enimsql is released under MIT License
#          George Lemon | Made by Humans from OpenPeep
#          https://supranim.com   |    https://github.com/supranim/enimsql

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

    DataType* = enum
        BigInt = "int8"
        BigSerial = "serial18"
        Bit = "bit"
        BitVarying = "varbit[]"
        Boolean = "bool"
        Box = "box"
        Bytea = "bytea"
        Char = "char[]"
        Varchar = "varchar[]"
        Cidr = "cidr"
        Circle = "circle"
        Date = "date"
        DoublePrecision = "float8"
        Inet = "inet"
        Int = "int"
        Int4 = "int4"
        Interval = "interval"
        Json = "json"
        Jsonb = "jsonb"
        Line = "line"
        Lseg = "lseg"
        Macaddr = "macaddr"
        Macaddr8 = "macaddr8"
        Money = "money"
        Numeric = "numeric"
        Path = "path"
        PGLsn = "pg_lsn"
        PGSnapshot = "pg_snapshot"
        Point = "point"
        Polygon = "polygon"
        Real = "float4"
        SmallInt = "int2"
        SmallSerial = "serial2"
        Serial = "serial4"
        Text = "text"
        Time = "time[]"
        Timezone = "timez"
        Timestamp = "timestamp"
        TimestampZ = "timestampz"
        TsQuery = "tsquery"
        TsVector = "tsvector"

    Constraints* = enum
        ## SQL constraints are used to specify rules for data in a table
        NotNull = "NOT NULL"
            ## Ensures that a column cannot have a NULL value
        Unique = "Unique"
            ## Ensures that all values in a column are different
        PrimaryKey = "PRIMARY KEY"
            ## A combination of a NOT NULL and UNIQUE. Uniquely identifies each row in a table
        ForeignKey = "FOREIGN KEY"
            ## Prevents actions that would destroy links between tables
        Check = "CHECK"
            ## Ensures that the values in a column satisfies a specific condition
        Default = "DEFAULT"
            ## Sets a default value for a column if no value is specified
        CreateIndex = "CREATE INDEX"
            ## Used to create and retrieve data from the database very quickly

    StatementType = enum
        SelectStmt = "SELECT"
        DeleteStmt = "DELETE"
        UpdateStmt = "UPDATE"
        UpdateAllStmt = "UPDATE"
        InsertStmt = "INSERT INTO $1 ($2) VALUES ($3);"
        WhereStmt = "WHERE"
        WhereLikeStmt = "$1 LIKE '$2'"
        WhereExistsStmt = "$1 EXISTS ($2)"
        IncrementStmt = "$1 = $1 + $2"
        DecrementStmt = "$1 = $1 - $2"

    KeyOperatorValue* = tuple[colName: string, op: Comparators, value: string]
    KeyValueTuple* = tuple[colName, colValue: string]
    SqlQuery = string

    Syntax = object
        case stmtType: StatementType
            of DeleteStmt: discard
            of SelectStmt:
                selectStmt: seq[string]
            of UpdateStmt, UpdateAllStmt:
                updateSetStmt: seq[KeyValueTuple]
            of InsertStmt:
                insertStmt: seq[KeyValueTuple]
            of IncrementStmt:
                incrementStmt: tuple[columnName: string, offset: int]
            of DecrementStmt:
                decrementStmt: tuple[columnName: string, offset: int]
            else: discard

        whereStmt: seq[KeyOperatorValue]
        whereLikeStmt: seq[tuple[colName, valueLike: string]]
        whereSubqueryStmt: seq[Syntax]
        countWhere: int

    AbstractModel* = object of RootObj
        ## An abstract object of `RootObj` to be extended by all models
        metaTableName: string
            # Holds the table name (lowercased and pluralized)
        metaModelName: string
            # Holds the model name
        sql: Syntax
            # Holds the current SQL Syntax

    ModelColumns = Table[string, string]
    
    Models = object
        storage: Table[string, ModelColumns]

    EnimsqlError = ref object of CatchableError
    DatabaseDefect = object of Defect

var Model* = Models()       ## A singleton instance of Models object
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

template checkDuplicates(colName, modelName: string, refCol: seq[string]) =
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
    result.sql = Syntax(stmtType: stmtType)
    result.metaModelName = $model
    result.metaTableName = getModelName($model)

proc escapeValue(str: string): string {.inline.} =
    result = escape(str, prefix = "'", suffix = "'")