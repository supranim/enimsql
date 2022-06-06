# A simple ORM for poets
#
# (c) 2021 Enimsql is released under MIT License
#          George Lemon | Made by Humans from OpenPeep
#          https://supranim.com   |   https://github.com/supranim/enimsql

macro model*(modelId: static string, fields: untyped) =
    ## Creates a new Model and store in the `ModelRepository` table
    if modelId in modelsIdent:
        raise EnimsqlError(msg: "A model with name \"$1\" already exists." % [modelId])
    fields.expectKind nnkStmtList
    var metaCols: ModelColumns
    var colFields = nnkRecList.newTree()
    for field in fields:
        if field.kind == nnkCall:
            # Handle private fields
            if field[0].kind == nnkIdent:
                field[1].expectKind nnkStmtList
                let fieldId = field[0].strVal
                let fieldType = field[1][0].strVal
                # echo fieldId & " " & fieldType
                metaCols[fieldId] = fieldType
                colFields.add(
                    nnkIdentDefs.newTree(
                        nnkPostfix.newTree(
                            ident "*",
                            ident fieldId
                        ),
                        ident fieldType,
                        newEmptyNode()
                    )
                )

            elif field[0].kind == nnkPragmaExpr:
                let fieldId = field[0][0].strVal
                let fieldType = field[1][0].strVal
                let fieldPragmas = field[0][1]
                for fieldPragma in fieldPragmas:
                    echo fieldPragma.strVal

                # echo fieldId & " " & fieldType
                metaCols[fieldId] = fieldType
                colFields.add(
                    nnkIdentDefs.newTree(
                        nnkPostfix.newTree(
                            ident "*",
                            ident fieldId
                        ),
                        ident fieldType,
                        newEmptyNode()
                    )
                )

    modelsIdent.add(modelId)
    result = newStmtList()
    result.add(
        nnkTypeSection.newTree(
            nnkTypeDef.newTree(
                nnkPostfix.newTree(
                    ident "*",
                    ident modelId
                ),
                newEmptyNode(),
                nnkRefTy.newTree(
                    nnkObjectTy.newTree(
                        newEmptyNode(),
                        nnkOfInherit.newTree(
                            ident "AbstractModel"
                        ),
                        colFields
                    )
                )
            )
        )
    )

    result.add quote do:
        Model.storage[`modelId`] = `metaCols`