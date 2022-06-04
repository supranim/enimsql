<p align="center">
    <img src="https://raw.githubusercontent.com/supranim/enimsql/main/.github/supranim-enimsql.png" height="65px" alt="Supranim Rate Limiter"><br>
    A simple ORM for poets<br>Work in progress
</p>

Enimsql provides a fluent interface
## Key features
- [x] Fluent Interface (Method chaining)
- [x] Powered by Nim's Macros System 👑
- [x] Async Pool with [Treeform's PG library](https://github.com/treeform/pg)
- [x] Built-in Validation using String-based Filters

## Examples

Create a new model using macros:
```nim
import std/times
import enimsql
export enimsql

model "User":
    name: string
    email: string
    password: string
    created_at: DateTime
    updated_at: DateTime
```

Create your first query with Enimsql
```nim
import ./model/user

# Create a simple query selecting all columns
# SELECT * FROM users WHERE email = 'john.doe@example.com'
let users = waitFor User.select().where(("email", EQ, "john.doe@example.com")).exec()

# Create a query and select only `name`, and `email`
# SELECT name, email FROM users WHERE email <> 'john.doe@example.com'
let users = waitFor User.select("name", "email")
                        .where(("email", NEQ, "john.doe@examples.com"))
                        .exec()

```

## Collection Results

Once executed will return a Collection `Table` containing `User` objects representation of each row.

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