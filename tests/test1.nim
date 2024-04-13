import unittest
import db_connector/db_postgres

import enimsql

newModel Users:
  id {.pk, notnull.}: Serial
  name: Varchar(255)
  email {.unique, notnull.}: Text
  is_confirmed {.notnull.}: Boolean = false
  is_muted {.notnull.}: Boolean = false
  total_posts {.notnull, inc.}: Int = 0
  total_replies {.notnull, inc.}: Int = 0
  last_active: Date
  last_published_reply: Date
  last_published_topic: Date

# newModel Sessions:
#   id {.pk, notnull.}: Serial
#   author_id: Users.id
#   user_ip: Int
#   user_agent: Text
#   payload: Text
#   last_activity: Date

test "can init database":
  initdb("georgelemon", "georgelemon", "")
  assert DB.maindb.user == "georgelemon"
  assert DB.maindb.name == "georgelemon"
  assert DB.maindb.password.len == 0

test "runtime create table":
  let q = Models.create("sessions") do(schema: Schema):
    schema.add("id", Serial).primaryKey
    schema.add("user_ip", Int)
    schema.add("user_agent", Text)
    schema.add("payload", Text)
    schema.add("last_activity", Date)
  echo q

test "runtime check tables":
  try:
    discard Models.create("sessions") do(schema: Schema):
      schema.add("id", Serial).primaryKey
  except EnimsqlModelDefect as e:
    assert e.msg == "Duplicate model `sessions`"

  try:
    discard Models.create("users") do(schema: Schema):
      schema.add("id", Serial).primaryKey
  except EnimsqlModelDefect as e:
    assert e.msg == "Duplicate model `users`"
