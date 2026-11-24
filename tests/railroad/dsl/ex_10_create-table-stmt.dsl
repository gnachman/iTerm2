{[`create-table-stmt` "CREATE" <!, <"TEMP", "TEMPORARY">#`Table will be dropped when connection closes`> "TABLE"],
 [[["IF" "NOT" "EXISTS"]#`If table exists, do nothing`]? [[["schema-name" "."]#`...in a foreign database`]? "table-name"]#`The table's name`],
 [<["(" ['column-def'*","]#`One or more column-definitions` [!*[['table-constraint' ","]#`primary key and stuff`]]#`Zero or more table-constraints` ")" <!, ["WITHOUT" "ROWID"]>],
   ["AS" 'select-stmt']#`Create table definition and content directly from a query`>]}
