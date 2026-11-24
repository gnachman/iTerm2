<{["SELECT" <!, "DISTINCT", "ALL"> 'result-column'*","],
  ["FROM" <'table-or-subquery'*",", 'join-clause'>]?,
  ["WHERE" 'expr']?,
  ["GROUP" "BY" 'expr'*"," <!, ["HAVING" 'expr']>]?},
 ["VALUES" ["(" 'expr'*"," ")"]*","]>
