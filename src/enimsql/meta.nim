import std/[macros, tables]
import db_connector/db_postgres
export db_postgres

from std/net import Port, `$`
from std/strutils import `%`

export Port, `$`, `%`

type
  DBConnection = ref object
    address, name, user, password: string
    port: Port

  DBConnections = OrderedTableRef[string, DBConnection]
  Enimsql = ref object
    ## Database manager
    dbs: DBConnections
    maindb: DBConnection

var DB*: Enimsql

proc initDBManager*(address, name, user,
    password: string, port: Port) =
  ## Initialize a thread var database connection
  ## using `credentials` as main database
  new(DB)
  DB.maindb = DBConnection(address: address,
    name: name, user: user, password: password, port: port)

proc initdb*(name, user, password: string,
  address = "localhost", port = Port(5432)) =
  ## Initialize a thread var database connection
  ## using `credentials` as main database
  initDBManager(address, name, user, password, port)

proc `[]=`*(db: Enimsql, id: string, dbCon: DBConnection) =
  ## Add a new database to thread var `DB`
  db[id] = dbCon

proc add*(db: Enimsql, id: string, dbCon: DBConnection) {.inline.} =
  ## Add a new database to thread var `DB`
  db[id] = dbCon

#   let dbcon = open("", "", "", "host=localhost port=$1 dbname=$2" % [$(DB.maindb.port), DB.maindb.name])

macro withDB*(x: untyped): untyped =
  ## Use the current database context
  ## to run database queries
  result = newStmtList()
  var blockStmtList = newStmtList()
  add blockStmtList,
    nnkLetSection.newTree(
      nnkIdentDefs.newTree(
        ident"dbcon",
        newEmptyNode(),
        nnkCall.newTree(
          ident"open",
          newLit"",
          newLit"",
          newLit"",
          nnkInfix.newTree(
            ident"%",
            newLit"host=localhost port=$1 dbname=$2",
            nnkBracket.newTree(
              nnkPrefix.newTree(
                ident"$",
                nnkPar.newTree(
                  newDotExpr(
                    newDotExpr(ident"DB", ident"maindb"),
                    ident"port"
                  )
                )
              ),
              newDotExpr(
                newDotExpr(ident"DB", ident"maindb"),
                ident"name"
              )
            )
          )
        )
      )
    )
  add blockStmtList,
    nnkDefer.newTree(
      newStmtList().add(newCall(newDotExpr(ident"dbcon", ident"close")))
    )
  add blockStmtList, x
  add result, nnkBlockStmt.newTree(newEmptyNode(), blockStmtList)
