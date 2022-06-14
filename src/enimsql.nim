import enimsql/query
export query

when isMainModule:
    model "User":
        name: string
        email: string

    echo User.where(("email", EQ, "georgelemon@protonmail.com")).exec()