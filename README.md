# Enimsql (WIP)
Open Source PostgreSQL ORM for poets 👌 Written in Nim.<br>
Inspired by Illuminate Eloquent & the romanian poet, Mihai Eminescu 🤟

**Currently, Enimsql is more like a proof of concept. There are many things to implement.**

```python
import enimsql, times, json

# Define a model and schema for your "users" table.
# Each model must inherit from base "Model".
# The model name must be always set as singular
type User* = ref object of Model
    token*: string
    username*: string
    name*: string
    birtdate*: DateTime
    confirmed*: bool
    token*: string

## Create a table
# For create/dump tables will need to implement a migration system

# Simple query for getting a specific user by 'username'
echo %* User().where("username", "eminescu").exec()

# Retrieve only "birthdate" and "username" values for record with "username" "eminescu"
echo %* User().select("birthdate", "username").where("username", "eminescu").exec()

# Short-hand Getters | These procedures have a built in exec()

# Retrieve all available records from "users" table except the one with username "eminescu"
echo %* User().getAllExceptOne("username", "eminescu")

# Retrieve all available records from "users" table except the following matches
echo %* User().getAllExcept("id", @["102", "75", "350"])

# Creating a new user is easy. First let's check if the username is taken
if User().exists("username", "eminescu"):
    echo "Sorry, the username is taken..."
else:
    User().create(username: "enimsql", name:"Enimsql", birthdate: "January 15, 1850")
```

## Insert & Insert Bulk
For inserting a single row, you can use `insert()` proc, and pass data for insertion as a `JsonNode`.
This procedure will produce the `INSERT INTO` SQL statement.

```python
import json, times

Article().insert(%*{
    "title": "String Literals",
    "slug": "string-literals",
    "created": now().utc(),
    "updated": now().utc()
})

```

For inserting multiple rows or even huge amount of data we are going to use `insert()` procedure, making use of `COPY` statement which, apparently is much faster than `INSERT`.

```python
Article().insertBulk(%*[
    {
        "title": "String Literals",
        "slug": "string-literals",
        "created": now().utc(),
        "updated": now().utc()
    },
    {
        "title": "String Literals Part 2",
        "slug": "string-literals-part-2",
        "created": now().utc(),
        "updated": now().utc()
    },
    # ...
])
```

## Models
_Enimsql Model syntax is very similar to Norm, another great ORM written in Nim._

Models can relate to each with `one-to-one`, `one-to-many`, `many-to-many` relations. For example, a CartItem can have many Discounts, whereas a single Discount can be applied to many Products.

Models can also inherit from each other. For example, Customer may inherit from User.
```python
import enimsql/model

type
    User = ref object of Model
        email*: string
        password*: string
        confirmed: bool
```

From a model definition, Enimsql deduces SQL queries to create tables, insert, select, update, and delete rows. Enimsql converts Nim objects to rows, their fields to columns, and their types to SQL types and vice versa.
```python
import enimsql/model

# To create relations between models, define fields subtyped from Model
# To add a UNIQUE constraint to a field, use {.unique.} pragma.
type
    User* = ref object of Model
        email {.unique.}: string

# Inherited models are just inherited objects
    Customer* = ref object of Model
        name: string
        user: User

```

## Models & Procedures
You can extend your models with custom procedures for creating stronger fluent operations.

```python
import enimsql

type
    User = ref object of Model
        email*: string
        password*: string
        confirmed: bool

proc getByEmail*[T: User](self: T, emailInput:string): seq =
    ## A short hand procedure for retrieving an user by its email account
    return self.where("email", emailInput).first().exec()

proc getInactive*[T: User](self: T): seq =
    ## A short hand procedure for retrieving all email addresses from unconfirmed users
    return self.select("email").where("confirmed", false).exec()

# Calling custom Model procs will return a sequence with available results or none.
var users = User().getByEmail("test@example.com")
var inactiveUsers = User().getInactive()
```

# Roadmap
...

## License
Enimsql is an open source library released under BSD-3 Clause License.