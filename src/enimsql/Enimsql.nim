from os import getEnv

import db_postgres, tables, strutils, typetraits, json
import macros

import ./Model
export Model

# Enimsql is a fast string-based query for PostgreSQL databases.
# 
# Documentation: https://github.com/georgelemon/eminsql
# Copyright (c) George Lemon <georgelemon@protonmail.com>
# Released under MIT license

const ENIMSQL_SELECT = "SELECT $1 "
const ENIMSQL_SELECT_ALL = "SELECT $1 FROM $2"

const ENIMSQL_WHERE =  "FROM $4 WHERE $1 $2 $3 "
const ENIMSQL_WHERE_LIKE = "FROM $3 WHERE $1 LIKE '$2'"
const ENIMSQL_WHERE_NOT = "FROM $3 WHERE $1 NOT '$2'"
const ENIMSQL_WHERE_NOT_LIKE = "FROM $3 WHERE $1 NOT LIKE '$2'"

const ENIMSQL_INSERT_SINGLE = "INSERT INTO $1"
const ENIMSQL_INSERT_SINGLE_COLUMNS = " ($1) "
const ENIMSQL_INSERT_SINGLE_VALUES = "VALUES ($1)"

const QUERY_GET_ALL_EXCEPT = "SELECT * FROM $1 WHERE $2 != $3"
const QUERY_GET_ALL_EXCEPT_ONE = "SELECT * FROM $1 WHERE $2 != $3"
const ENIMSQL_DELETE = "DELETE "
const ENIMSQL_ORDERBY = "ORDER BY $1"

const CREATE_TABLE = "CREATE TABLE $1 ($2)"
const DROP_TABLE = "DROP TABLE $1 IF EXIST"

var DBInstance: DbConn

type
    Document = object
        results: Table[string, string]

proc connection(): DbConn =
    ## Opens a database connection.
    ## Raises EDb if the connection could not be established.
    ## Clients can also use Postgres keyword/value connection strings to connect
    open(os.getEnv("DB_HOST"),
        os.getEnv("DB_USER"),
        os.getEnv("DB_PASS"),
        os.getEnv("DB_NAME"))

proc db(): DbConn =
    ## Retrieve database connection instance
    return connection()

proc table[T: Model](self: T): string =
    ## Retrieve the name of the table based on Model's name, converted to lowercase.
    ## Gramatically, the name of the model must be set in a singular form
    ## Enimsql will automatically set the database table names in plural form.
    ## Names that ends with "s", "es", "sh", "ch", "x" or "z" will append to "es"
    var esSuffix = @["s", "es", "sh", "ch", "x", "z"]
    var modelName = toLowerAscii($self.type.name)
    for esSfx in esSuffix:
        if modelName.endsWith(esSfx):
            modelName = "$1es" % [modelName]
            return modelName
    return "$1s" % [modelName]

proc execQuery(self: Model): seq[Table[string, string]] =
    ## SQL Query for retrieving all available records from a specific table
    ## The actual SQL Query executer that grabs all records related to given SQL query
    ## and store in a sequence table as collection.
    ## If no results found a DbError will raise in console and return an empty collection
    var
        columns: db_postgres.DbColumns
        collection: seq[Table[string, string]]
    DBInstance = db()

    try:
        for row in instantRows(DBInstance, columns, sql(self.sql)):
            # stack.length = columns.len
            var items = initTable[string, string]()
            for key, col in columns:
                if row[key].len == 0: continue
                items[col.name] = row[key]
            collection.add(items)
    except DbError as error:
        echo error.msg

    echo collection
    return collection

proc exec*(self: Model): seq =
    ## Procedure for executing the current SQL
    var results = self.execQuery()
    DBInstance.close()
    return results

macro getFromDocument(key: static string): untyped = 
    nnkStmtList.newTree(
        nnkReturnStmt.newTree(
            nnkBracketExpr.newTree(
                nnkDotExpr.newTree(
                    newIdentNode("doc"),
                    newIdentNode("results")
                ),
                newLit(key)
            )
        )
    )

proc get*[T: Document](doc: var T): seq[Table[string, string]] =
    return doc.results

proc get*[T: Document](doc: var T, key: string): string = 
    key.getFromDocument()

proc createTable*[T: Model](self: T): bool =
    ## Create a new table based on selected Model
    self.sql = CREATE_TABLE % [self.TableName]
    DBInstance = db()
    DBInstance.sql(self.sql)
    DBInstance.close()
    return true

proc dropTable*[T: Model](self: T): bool =
    ## Drop a table if exists based on selected Model
    self.sql = DROP_TABLE % [self.TableName]
    DBInstance = db()
    DBInstance.sql(self.sql)
    DBInstance.close()
    return true

proc select*[T: Model](self: T, columns: varargs[string]): Model =
    ## Procedure for declaring an 'SELECT' SQL statement.
    ## Accepts one or many columns via varargs to be used for selection
    var cols = if columns.len == 0: "*" else: strutils.join(columns, ",")
    self.TableName = self.table()
    # if not selectAll:
    self.sql = ENIMSQL_SELECT % [cols]
    # else:
    #     self.sql = ENIMSQL_SELECT_ALL % [cols, self.TableName]
    return self

proc selectAll*[T: Model](self: T, columns: varargs[string]): Model =
    return self.select()

proc where*[T: Model](self: T, colValue: string, expectValue: string, operator: string="="): Model =
    ## Procedure for creating an 'WHERE' SQL statement.
    ## 'colValue' represents the current value of the specified column
    ## 'expectValue' is the representation of the expected value
    ## 'operator' is the SQL operator used for the 'WHERE' declaration
    if self.TableName.len == 0:
        self.TableName = self.table()

    self.sql &= ENIMSQL_WHERE % [colValue, operator, "'" & $expectValue & "'", self.TableName]
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


proc whereNot*[T: Model](self: T, colValue: string, expectValue: string): seq =
    ## Procedure for creating an 'WHERE NOT' SQL statement.
    ## 'colValue' represents the current value of the specified column
    ## 'expectValue' is the representation of the expected value
    self.sql &= ENIMSQL_WHERE_NOT % [colValue, $expectValue, self.TableName]
    return self.execQuery()

proc whereNotLike*[T: Model](self: T, colValue: string, expectValue: string): seq =
    ## Procedure for creating an 'WHERE NOT LIKE' SQL statement.
    ## 'colValue' represents the current value of the specified column
    ## 'expectValue' is the representation of the expected value
    self.sql &= ENIMSQL_WHERE_NOT_LIKE % [colValue, $expectvalue, self.TableName]
    return self.execQuery()


# In addition to retrieving all of the records matching a given query,
# you may also retrieve single records using the 'find', 'first', or 'firstWhere' procedures.
proc find*[T: Model](self: T, pkValue: string): Model =
    ## Retrieve a record based on primary key.
    ## Models that do not provide a custom pk name will automatically have "id" as primary key.
    return self


proc first*(self: Model, id: int): Model =
    ## Retrieve the first model matching the query constraints
    return self


proc firstWhere*[T: Model](self: T, id: int): Model =
    ## Retrieve the first model matching the query constraints
    return self


## INSERT Statements
proc insert*[T: Model](self: T, item:JsonNode, shouldGetEntryId:bool=false): any =
    ## Procedure for inserting a single row. This insert proc will produce the following SQL:
    ## INSERT INTO {table_name} (column, column2) VALUES ('val', 'val2')
    self.TableName = self.table()
    self.sql = ENIMSQL_INSERT_SINGLE % self.TableName
    DBInstance = db()
    var keySeq = newSeq[string]()
    var valSeq = newSeq[string]()

    for field in item.pairs():
        # Store column names in a new sequence
        keySeq.add($field.key)
        # Store values in a new sequence and prepare it with db quote
        valSeq.add(db_postgres.dbQuote(field.val.getStr()))

    self.sql &= ENIMSQL_INSERT_SINGLE_COLUMNS % [keySeq.join(", ")]
    self.sql &= ENIMSQL_INSERT_SINGLE_VALUES % [valSeq.join(", ")]
    if shouldGetEntryId:
        ## Native insertID() proc supports RETURNING only when the primary key is named "id".
        ## TODO add support for custom named primary keys appending RETURNING {pk_column_name} to the query
        var getEntryId = DBInstance.insertID(sql(self.sql))
        DBInstance.close()
        return getEntryId
    # The exec() procedure returns 0 for success operations and -1 for fails
    DBInstance.exec(sql(self.sql))
    DBInstance.close()


proc insertGet*[T: Model](self: T, item:JsonNode): int64 =
    ## Insert a single row and returns the generated ID of the row.
    return self.insert(item, true)


proc insertBulk*[T: Model](self: T, collection:JsonNode, shouldGetEntryIds:bool=false): string =
    ## Insert huge amounts of data in bulk using COPY statement
    ## https://www.cybertec-postgresql.com/en/postgresql-bulk-loading-huge-amounts-of-data/
    ## TODO change this proc to use COPY instead of BEGIN/COMMIT
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


proc insertBulkGetIds*[T: Model](self: T, collection:JsonNode): string = 
    ## Insert huge amounts of data in bulk using COPY statement.
    ## And return a sequence with all entry IDs
    self.insertBulk()


# SQL Procedures for creating getter SQL queries
proc getAllExceptOne*[T: Model](self: T, lookupColumn:string, lookupValue:string): seq =
    ## Produce an SQL query to retrieve all records except one.
    self.TableName = self.table()
    self.sql = QUERY_GET_ALL_EXCEPT_ONE % [self.TableName, lookupColumn, lookupValue]
    return self.execQuery()


proc getAllExcept*[T: Model](self: Model, exception:varargs[string]): Model =
    ## Produce an SQL query to retrieve all records except one or many
    # self.sql = QUERY_GET_ALL_EXCEPT % [self.tableName, exception]
    return self

proc getRandom*[T: Model](self: T): Model =
    ## Produce an SQL query to retrieve a random record
    return self

proc getOne*[T: Model](self: T): Row =
    ## Retrieves a single row from query results.
    ## If the query doesn't return any rows, this proc will return
    ## a Row sequence with empty strings for each column
    self.TableName = self.table()
    self.select()
    var results = db().getRow(sql("SELECT * FROM "&self.TableName))
    DBInstance.close()
    return results


# DANGER ZONE
proc raw*[T: Model](self: T, query:string, values:varargs[string]): any =
    ## Procedure for executing RAW SQL Queries
    discard


proc delete*[T: Model](self: T): bool =
    # Simple proc for executing a DELETE statement
    # TODO implement response based on results.
    # Right now tryExec returns true/false based on query execution
    return db().tryExec(sql(ENIMSQL_DELETE & self.sql))
