[`expr_macro_rules` "macro_rules" "!" 'ident' "(" 'macro_rule'*! ")" ";"]
[`macro_rule` "(" 'matcher'*! ")" "=>" "(" 'transcriber'*! ";"]
[`matcher` <["(" 'matcher'*! ")"], ["[" 'matcher'*! "]"],
            ["{" 'matcher'*! "}"], ["$" 'ident' ":" 'ident'],
            ["$" "(" 'matcher'*! ")" 'sep_token'? <"*", "+">],
            'non_special_token'>]
[`transcriber` <["(" 'transcriber' ")"], ["[" 'transcriber' "]"],
                ["{" 'transcriber' "}"], ["$" 'ident'],
                ["$" "(" 'transcriber'*! ")" 'sep_token'? <"*", "+">],
                'non_special_token'>]
