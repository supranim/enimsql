import enimsql/query
export query

when isMainModule:
    model "User":
        name: string
        email: string

    let sql = User.update(("email", "new@example.com"))
                  .where(("email", EQ, "test@example.com")).getRaw()
    echo sql