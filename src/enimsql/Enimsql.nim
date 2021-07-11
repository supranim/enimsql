import ./model
import os, db_postgres, tables, sequtils, strutils, typetraits
export model

## Enimsql is a simple PostgreSQL ORM made for poets.
## Written in Nim, inspired by Illuminate Eloquent.

const ENIMSQL_SELECT = "SELECT $1 "
const ENIMSQL_WHERE =  "FROM $4 WHERE $1 $2 $3 "
const ENIMSQL_WHERE_LIKE = "FROM $3 WHERE $1 LIKE '$2'"
const ENIMSQL_INSERT_SINGLE = "INSERT INTO $1"
const ENIMSQL_INSERT_SINGLE_COLUMNS = " ($1) "
const ENIMSQL_INSERT_SINGLE_VALUES = "VALUES ($1);"
const ENIMSQL_GET_ALL_EXCEPT = "SELECT * FROM $1 WHERE $2 != $3"
const ENIMSQL_GET_ALL_EXCEPT_ONE = "SELECT * FROM $1 WHERE $2 != $3"

proc connection(): DbConn =
    ## Opens a database connection. Raises EDb if the connection could not be established.
    ## Clients can also use Postgres keyword/value connection strings to connect
    open(getEnv("DB_HOST"), getEnv("DB_USER"), getEnv("DB_PASS"), getEnv("DB_NAME"))

proc db(): DbConn =
    ## Retrieve database connection instance
    return connection()

proc table[T: Model](self: T): string =
    ## Procedure for retrieving the name of the table based on its model
    ## If the model name is camel case then the table name
    ## is converted to lowercase separated by underscore
    return self.type.name.toLowerAscii

proc execQuery(self: Model): seq =
    ## SQL Query for retrieving all available records from a specific table
    ## The actual SQL Query executer that grabs all records related to given SQL query
    ## and store in a sequence table as collection.
    ## If no results found a DbError will raise in console and return an empty collection
    var columns: db_postgres.DbColumns
    var collection = newSeq[Table[string, string]]()
    try:
        for row in db().instantRows(columns, sql(self.sql)):
            # stack.length = columns.len
            var items = initTable[string, string]()
            for key, col in columns:
                items[col.name] = row[key]
            collection.add(items)
        return collection
    except DbError as error:
        echo error.msg
        return collection

proc exec*(self: Model): seq =
    ## Procedure for executing the current SQL
    return self.execQuery()

proc select*[T: Model](self: T, columns: varargs[string]): Model =
    ## Procedure for declaring an 'SELECT' SQL statement.
    ## Accepts one or many columns via varargs to be used for selection
    var cols = if columns.len == 0: "*" else: strutils.join(columns, ",")
    self.sql = ENIMSQL_SELECT % [cols]
    self.TableName = self.table()
    return self

proc where*[T: Model](self: T, colValue: string, expectValue: string, operator: string="="): Model =
    ## Procedure for creating an 'WHERE' SQL statement.
    ## 'colValue' represents the current value of the specified column
    ## 'expectValue' is the representation of the expected value
    ## 'operator' is the SQL operator used for the 'WHERE' declaration
    self.sql &= ENIMSQL_WHERE % [colValue, operator, $expectValue, self.TableName]
    return self

proc whereLike*[T: Model](self: T, colValue: string, expectValue: string): seq =
    ## Procedure for creating an 'WHERE LIKE' SQL clause.
    ## This proc is automatically executing the SQL, so there is no need for calling exec().
    ## 'colValue' represents the current value of the specified column
    ## 'expectValue' is the representation of the expected value.
    ## a%       Finds any values that start with "a"
    ## %a       Finds any values that end with "a"
    ## %or%     Finds any values that have "or" in any position
    ## _r%      Finds any values that have "r" in the second position
    ## a_%      Finds any values that start with "a" and are at least 2 characters in length
    ## a__%     Finds any values that start with "a" and are at least 3 characters in length
    ## a%o      Finds any values that start with "a" and ends with "o"
    self.sql &= ENIMSQL_WHERE_LIKE % [colValue, $expectValue, self.TableName]
    return self.execQuery()

proc whereNot*(self: Model, colValue: string, expectValue: string): Model =
    ## Procedure for creating an 'WHERE LIKE' SQL statement.
    ## 'colValue' represents the current value of the specified column
    ## 'expectValue' is the representation of the expected value
    return self

proc whereAlike*(self: Model, colValue: string, expectValue: string): Model =
    ## Procedure for creating an 'WHERE LIKE' SQL statement.
    ## 'colValue' represents the current value of the specified column
    ## 'expectValue' is the representation of the expected value
    return self

# In addition to retrieving all of the records matching a given query,
# you may also retrieve single records using the 'find', 'first',
# or 'firstWhere' procedures. 
proc find*(self: Model, pkValue: string, pk:string=""): Model =
    ## Procedure for retrieving a record by its primary key.
    ## If a key is specified, it will replace the default primary key.
    return self

proc first*(self: Model, id: int): Model =
    ## Retrieve the first model matching the query constraints
    return self

proc firstWhere*(self: Model, id: int): Model =
    ## Retrieve the first model matching the query constraints
    return self

proc insert*[T: Model](self: T, item:JsonNode): bool =
    ## Procedure for inserting a single row. This insert proc will produce the following SQL:
    ## INSERT INTO {table_name} (column, column2) VALUES ('val', 'val2')
    self.TableName = self.table()
    self.sql = ENIMSQL_INSERT_SINGLE % self.TableName

    var keySeq = newSeq[string]()
    var valSeq = newSeq[string]()

    for field in item.pairs():
        # Store column names in a new sequence
        keySeq.add($field.key)
        # Store values in a new sequence and prepare it with db quote
        valSeq.add(db_postgres.dbQuote(field.val.getStr()))

    self.sql &= ENIMSQL_INSERT_SINGLE_COLUMNS % [keySeq.join(", ")]
    self.sql &= ENIMSQL_INSERT_SINGLE_VALUES % [valSeq.join(", ")]
    db().exec(sql(self.sql))
    return true

proc insertGet*[T: Model](self: T, item:JsonNode) =
    ## Procedure for inserting a single row and retrieving the row after insertion.
    var ok = self.insert(item)

proc insertBulk*[T: Model](self: T, collection:JsonNode): string =
    ## Procedure for inserting huge amounts of data in bulk.
    ## Since INSERT method takes a lot of time while inserting bulk data,
    ## we are going to run the bulk insertion with COPY statement.
    # https://www.cybertec-postgresql.com/en/postgresql-bulk-loading-huge-amounts-of-data/
    # https://www.w3schools.com/sql/sql_insert.asp
    self.TableName = self.table()
    self.sql = "BEGIN;\n"

    for item in collection.items():
        var keySeq = newSeq[string]()
        var valSeq = newSeq[string]()

        for field in item.pairs():
            keySeq.add($field.key)
            valSeq.add($field.val)

        self.sql &= "INSERT INTO $1" % [self.TableName]
        self.sql &= " ($1) " % [$keySeq.join(", ")]
        self.sql &= "VALUES ($1);\n" % [$valSeq.join(", ")]

    self.sql &= "COMMIT;"
    echo self.sql

# SQL Procedures serving for
# getting records except one or many

proc getAllExceptOne*[T: Model](self: T, lookupColumn:string, lookupValue:string): seq =
    ## Procedure for creating an SQL query where will retrieve all records except one.
    self.TableName = self.table()
    self.sql = "SELECT * FROM $1 WHERE $2 != $3" % [self.TableName, lookupColumn, lookupValue]
    return self.execQuery()

proc getAllExcept*(self: Model, exception:varargs[string]): Model =
    ## Procedure for creating an SQL query where will retrieve all records except one or many
    return self

proc getOne*(tableName: string): Row =
    ## retrieves a single row. If the query doesn't return any rows,
    ## this proc will return a Row with empty strings for each column
    var results = db().getRow(sql("SELECT * FROM "&tableName))
    db().close()
    return results
