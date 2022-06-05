<p align="center">
    <img src="https://raw.githubusercontent.com/supranim/enimsql/main/.github/supranim-enimsql.png" height="65px" alt="Supranim Rate Limiter"><br>
    (WIP) A simple ORM for poets<br>Provides a safe & fluent interface for writing SQL queries.
</p>

## Key features
- [x] Fluent Interface (Method chaining)
- [x] Powered by Nim's Macros System 👑
- [x] Async Pool with [Treeform's PG library](https://github.com/treeform/pg)
- [x] Built-in Validation using String-based Filters
- [x] Pluralize Model names for SQLs

## Examples

Create a new model using macros:
```nim
import std/times
import enimsql

export enimsql

model "User":
    name: string
    email: string
    country: string
    city: string
    password: string
    created_at: DateTime
    updated_at: DateTime
```

## Queries
- Select Statements
- Where Clauses
- Update Statements

### Select Statements
You may not always want to select all columns from a database table. Using the `select` proc, you can create a custom `SELECT` clause by specifying
column names you want to include in your results. `select` proc is accept a parameter of type `varargs[string]`.

```nim
# Retrieve all records from `users` table and return only `name`, `email` and `country`
User.select("name", "email", "country").exec()
```

The `selectDistinct` proc allows you to force the query to return distinct results.
```nim
User.selectDistinct()
```

If you already have a query builder instance and you wish to add a column to its existing `SELECT` clause, you may use the `addSelect` proc:
```nim
var query = User.select("name")
let users = query.addSelect("email").exec()
```

### Where Clause(s) 
You may use the query builder's `where` proc to add `WHERE` clauses to the query.
The most basic call to the `where` proc requires a `varargs` of `KeyOperatorValue` tuple with three arguments.
1. The first argument is the name of the column.
2. The second argument is an operator, which can be any of the database's supported operators.
3. The third argument is the value to compare against the column's value.
```nim
User.select().where(("email", EQ, "john.doe@example.com"))
```

When chaining together calls to the query builder's `where` procedure, the `WHERE` clauses will be joined together using the `AND`
operator. Alternatively, since `where` proc accepts a `varargs` of `KeyOperatorValue` tuple, you can call `where` procedure and provide multiple `KeyOperatorValue` tuple.
```nim
User.select().where(
    ("email", NEQ, "john.doe@example.com"),
    ("city", EQ, "Milan")
)
```
_The example above will produce the following SQL:_
```sql
SELECT * FROM users
        WHERE email <> 'john.doe@example.com',
              city = 'Milan'
```

However, you may use the `orWhere` proc to join a clause to the query using the `OR` operator.
```nim
User.select().where(
                ("email", NEQ, "john.doe@example.com"),
                ("city", EQ, "Milan"))
             .orWhere(
                ("email", NEQ, "john.doe@example.com"),
                ("city", EQ "Torino"))
```

_The example above will produce the following SQL:_
```sql
SELECT * FROM users
         WHERE
            email <> 'john.doe@example.com' AND city = 'Milan'
            OR (
                email <> 'john.doe@example.com' AND city = 'Torino'
            )
```

### Where Not Clauses
The `whereNot` and `orWhereNot` procs may be used to negate a given group of query constraints.
For example, the following query excludes products that are on clearance or which have a price that is less than ten:
```nim
User.select().whereNot()
```

### Update Statements
In addition to inserting records into the database, the query builder can also update existing records using the `update` proc.
The `update` proc is a safe way for updating records because it requires a `WHERE` clause. To update all records in a table with same values use `updateAll`.
```nim
User.update(("email", "new.john.doe@example.com"))
    .where(("email", EQ, "john.doe@example.com"))
    .exec()
```

```nim
User.updateAll(("updated_at", now())).exec()
```

### Joins
The query builder may also be used to add `JOIN` clauses to your queries. To perform a basic `INNER JOIN`, you may use the `join` procedure on a query builder instance.

```nim
import ./order, ./contacts

let users = User.join(Contact)
```

# Roadmap
- [ ] Do the do

### ❤ Contributions
Help with ideas, bugfixing, contribute with code or [donate via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C) 🥰

### 👑 Discover Nim language
<strong>What's Nim?</strong> Nim is a statically typed compiled systems programming language. It combines successful concepts from mature languages like Python, Ada and Modula. [Find out more about Nim language](https://nim-lang.org/)

<strong>Why Nim?</strong> Performance, fast compilation and C-like freedom. We want to keep code clean, readable, concise, and close to our intention. Also a very good language to learn in 2022.

### 🎩 License
Enimsql is Open Source Software released under `MIT` license. [Developed by Humans from OpenPeep](https://github.com/openpeep).<br>
Copyright &copy; 2022 OpenPeep & Contributors &mdash; All rights reserved.

<a href="https://hetzner.cloud/?ref=Hm0mYGM9NxZ4"><img src="https://openpeep.ro/banners/openpeep-footer.png" width="100%"></a>