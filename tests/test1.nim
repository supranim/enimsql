import unittest
import enimsql
from std/strutils import escape

model "User":
    name: string
    email: string
    country: string
    votes: int

test "Meta table Pluralization":
    assert User.getTableName() == "users"

test "WHERE Query 1":
    let sql = User.where(("email", EQ, "test@example.com")).getRaw()
    assert sql == "SELECT * FROM users WHERE email = 'test@example.com'"

test "WHERE Query 2":
    let sql = User.where(
        ("email", EQ, "test@example.com"),
        ("name", NEQ, "Lemon")
    ).getRaw()
    assert sql == "SELECT * FROM users WHERE email = 'test@example.com' AND name <> 'Lemon'"

test "SELECT & WHERE Query 3":
    let sql = User.select("name").where(("email", EQ, "test@example.com")).getRaw()
    assert sql == "SELECT name FROM users WHERE email = 'test@example.com'"

test "UPDATE Query 4":
    let sql = User.update(("email", "new@example.com"))
                  .where(("email", EQ, "test@example.com")).getRaw()
    assert sql == "UPDATE users SET email = 'new@example.com' WHERE email = 'test@example.com'"

test "UPDATE ALL Query 5":
    let sql = User.updateAll(("votes", "1")).getRaw()
    assert sql == "UPDATE users SET votes = '1'"