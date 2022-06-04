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
- Where Clauses

### Where Clause(s) 
You may use the query builder's `where` proc to add `WHERE` clauses to the query.
The most basic call to the `where` proc requires a `varargs` of `KeyOperatorValue` tuple with three arguments.
1. The first argument is the name of the column.
2. The second argument is an operator, which can be any of the database's supported operators.
3. The third argument is the value to compare against the column's value.
```nim
User.select().where(("email", EQ, "john.doe@example.com"))
```

When chaining together calls to the query builder's `where` method, the `WHERE` clauses will be joined together using the `AND`
operator. Alternatively, since `where` proc accepts a `varargs` of `KeyOperatorValue` tuple, you can call `where` proc once providing `KeyOperatorValue` tuple multiple times.
```nim
User.select().where(
    ("email", NEQ, "john.doe@example.com"),
    ("city", EQ, "Milan")
)
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

_The example above will produce the following SQL_
```sql
SELECT * FROM users
         WHERE
            email <> 'john.doe@example.com' AND city = 'Milan'
            OR (
                email <> 'john.doe@example.com' AND city = 'Torino'
            )
```

```nim
import ./model/user
```

#### Select & Where
```nim
# Create a simple query selecting all columns
# SELECT * FROM users WHERE email = 'john.doe@example.com'
let users = await User.select().where(("email", EQ, "john.doe@example.com")).exec()

# Create a query and select only `name`, and `email`
# SELECT name, email FROM users WHERE email <> 'john.doe@example.com'
let users = await User.select("name", "email")
                      .where(("email", NEQ, "john.doe@example.com"))
                      .exec()
```

#### Update
Enimsql provides safe procedures for updating records. `update`, which requires to be followed by a `where` statement, and `updateAll`,
which updates all records in a table for given `key`, `value`.

```nim 
# UPDATE users SET updated_at = 12345 WHERE email = 'john.doe@example.com'
let updateStatus = await User.update(("updated_at", now()))
                             .where(("email", EQ, "john.doe@example.com"))
                             .exec()
if updateStatus:
    echo "Your profile has been successfully updated"
else:
    echo "Could not update your profile, try again"

# Example using `updateAll` for updating all records
# UPDATE users SET updated_at = 12345
let updateStatus = await User.updateAll(("updated_at", now())).exec()
```

## Collection Results
Enimsql returns results wrapped in a Collection `Table` that contains `Model` objects representation of each row.

```nim
if users.hasResults():
    for user in users:
        echo user.get("name")
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