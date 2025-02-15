type
  SQLValue* = ref object
    dt*: DataType
    value*: string
    
  DataType* = enum
    BigInt = "int8"
    BigSerial = "serial18"
    Bit = "bit"
    BitVarying = "varbit" # $1
    Boolean = "boolean"
    Box = "box"
    Bytea = "bytea"
    Char = "char" # $1
    Varchar = "varchar" # $1
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
    Serial = "serial"
    Text = "text"
    Time = "time" # $1
    Timezone = "timez"
    Timestamp = "timestamp"
      ## https://www.postgresql.org/docs/current/datatype-datetime.html
    TimestampTz = "timestamptz"
    TsQuery = "tsquery"
    TsVector = "tsvector"
    Uuid = "uuid"
    Enum = "enum"

# Postgresql Functions
# const pgsqlFunctions = {
#   "UUID": [
#     "uuid_generate_v1",
#     "uuid_generate_v1mc",
#     "uuid_generate_v4",
#   ]
# }