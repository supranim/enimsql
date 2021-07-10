# Enimsql (WIP)
Open Source PostgreSQL ORM for poets 👌 Written in Nim.<br>
Inspired by Illuminate Eloquent & the romanian poet, Mihai Eminescu 🤟


```python
import enimsql, times, json

# Define a model and schema for your "users" table.
# Each model must reference from the BaseModel.
# The Model name must be always set as singular
type User* = ref object of BaseModel
    token*: string
    username*: string
    name*: string
    birtdate*: DateTime
    confirmed*: bool
    token*: string

# Simple query for getting a specific user by 'username'
echo %* User().where("username", "eminescu").exec()

# Retrieve only "birthdate" and "username" values for record with "username" "georgelemon"
echo %* User().select("birthdate", "username").where("username", "eminescu").exec()

# Short-hand Getters | These procedures have a built in exec()
# Retrieve all available records from "users" table except the one with username "georgelemon"
echo %* User().getAllExceptOne("username", "eminescu")

# Creating a new user is easy. First let's check if the username is taken
if User().exists("username", "eminescu"):
    echo "Sorry, the username is taken..."
else:
    User().create(username: "enimsql", name:"Enimsql", birthdate: "January 15, 1850")
```

# Roadmap
...


## License
Enimsql is an open source library released under BSD-3 Clause License.