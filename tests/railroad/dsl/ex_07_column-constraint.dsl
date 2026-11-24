{["CONSTRAINT" "name"]?,
 <["PRIMARY" "KEY" <!, "ASC", "DESC"> 'conflict-clause' <!, "AUTOINCREMENT">],
  ["NOT" "NULL" 'conflict-clause'],
  ["UNIQUE" 'conflict-clause'],
  ["CHECK" "(" 'expr' ")"],
  ["DEFAULT" <'signed-number', 'literal-value', ["(" 'expr' ")"]>],
  ["COLLATE" "collation-name"],
  'foreign-key-clause'>}
