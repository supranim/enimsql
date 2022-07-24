# A simple ORM for poets.
# This is a very simple implemntation of
# asynchronous PostgreSQL pool api for Nim.
# 
#       Originally written by Treeform
#       https://github.com/treeform/pg
#
# (c) 2021 Enimsql is released under MIT License
#          George Lemon | Made by Humans from OpenPeep
#          https://supranim.com   |    https://github.com/supranim/enimsql

import std/asyncdispatch
import ./collection

include std/db_postgres

# from std/os import getEnv
# from ./meta import modelsIdent, AbstractModel

export asyncdispatch

type
    ## db pool
    AsyncPool* = ref object
        conns: seq[DbConn]
        busy: seq[bool]

    ## Exception to catch on errors
    PGError* = object of CatchableError

var Database*: DbConn

method newConnection*(db: var DbConn, host, user, pass, name: string) {.base.} =
    ## Create a single connection with default PostgreSQL API 
    Database = open(host, user, pass, name)
    assert Database.status == CONNECTION_OK

proc newConnection*(connection, user, password, database: string, num: int): AsyncPool =
    ## Creates new AsyncPool of `num` connections
    result = AsyncPool()
    for i in 0..<num:
        let conn = open(connection, user, password, database)
        assert conn.status == CONNECTION_OK
        result.conns.add conn
        result.busy.add false

method getStatus*(db: var DBConn): bool {.base.} =
    result = db.status == CONNECTION_OK

proc checkError(db: DbConn) =
    ## Raises a DbError exception.
    var message = pqErrorMessage(db)
    if message.len > 0:
        raise newException(PGError, $message)

proc setRowModel(res: PPGresult, r: var Row, line, cols: int32) =
    for col in 0'i32..cols-1:
        setLen(r[col], 0)
        let x = pqgetvalue(res, line, col)
        if x.isNil: r[col] = ""
        else:       add(r[col], x)

proc rows*(db: DbConn, query: SqlQuery, args: seq[string]): Future[seq[Row]] {.async.} =
    ## Runs the SQL getting results.
    assert db.status == CONNECTION_OK
    let success = pqsendQuery(db, cstring(dbFormat(query, args)))
    if success != 1: dbError(db) # never seen to fail when async
    while true:
        let success = pqconsumeInput(db)
        if success != 1: dbError(db) # never seen to fail when async
        if pqisBusy(db) == 1:
            await sleepAsync(1)
            continue
        var pqresutl = pqgetResult(db)
        if pqresutl == nil:
            # Check if its a real error or just end of results
            db.checkError()
            return
        var cols = pqnfields(pqresutl)
        var row = newRow(cols)
        for i in 0'i32..pqNtuples(pqresutl)-1:
            setRow(pqresutl, row, i, cols)
            result.add row
        pqclear(pqresutl)

method rows*(db: DbConn, sqlStr: string): Future[Collection] {.base, async.} =
    assert db.status == CONNECTION_OK
    let success = pqsendQuery(db, cstring(dbFormat(sql(sqlStr))))
    if success != 1: dbError(db)
    var QueryCollection = Collection()
    while true:
        let success = pqconsumeInput(db)
        if success != 1: dbError(db)
        if pqisBusy(db) == 1:
            await sleepAsync(1)
            continue

        var pqresutl = pqgetResult(db)
        if pqresutl == nil: # Check if its a real error or just end of results
            db.checkError()
            break
        
        var columns: DbColumns
        setColumnInfo(columns, pqresutl, pqnfields(pqresutl))

        var cols = pqnfields(pqresutl)
        var rows = newRow(cols)
        for i in 0'i32..pqNtuples(pqresutl)-1:
            setRow(pqresutl, rows, i, cols)
            var rowColKeyVal: seq[tuple[key, value: string]]
            for ii, row in rows.pairs():
                rowColKeyVal.add (columns[ii].name, row)
            QueryCollection.add(i, rowColKeyVal)
        pqclear(pqresutl)
    result = QueryCollection

proc getFreeConnIdx(pool: AsyncPool): Future[int] {.async.} =
    ## Wait for a free connection and return it.
    while true:
        for conIdx in 0..<pool.conns.len:
            if not pool.busy[conIdx]:
                pool.busy[conIdx] = true
                return conIdx
        await sleepAsync(100)

proc returnConn(pool: AsyncPool, conIdx: int) =
    ## Make the connection as free after using it and getting results.
    pool.busy[conIdx] = false

proc rows*(pool: AsyncPool, query: SqlQuery, args: seq[string]): Future[seq[Row]] {.async.} =
    ## Runs the SQL getting results.
    let conIdx = await pool.getFreeConnIdx()
    result = await rows(pool.conns[conIdx], query, args)
    pool.returnConn(conIdx)

proc exec*(pool: AsyncPool, query: SqlQuery, args: seq[string]) {.async.} =
    ## Runs the SQL without results.
    let conIdx = await pool.getFreeConnIdx()
    discard await rows(pool.conns[conIdx], query, args)
    pool.returnConn(conIdx)