[`char_lit` "\x27" 'char_body' "\x27"]
[`string_lit` <["\"" 'string_body' "\""], ["r" 'raw_string']>]
[`char_body` <'non_single_quote', ["\x5c" <"\x27", 'common_escape', 'unicode_escape'>]>]
[`string_body` <'non_double_quote', ["\x5c" <"\x22", 'common_escape', 'unicode_escape'>]>]
[`raw_string` <["\"" 'raw_string_body' "\""], ["#" 'raw_string' "#"]>]
[`common_escape` <"\x5c", "n", "r", "t", "0", ["x" 'hex_digit'*`2 times`]>]
[`unicode_escape` ["u" "{" 'hex_digit'*`6 times` "}"]]
[`hex_digit` <"a", "b", "c", "d", "e", "f",
              "A", "B", "C", "D", "E", "F",
              'dec_digit'>]
[`oct_digit` <"0", "1", "2", "3", "4", "5", "6", "7">]
[`dec_digit` <"0", 'nonzero_dec'>]
[`nonzero_dec` <"1", "2", "3", "4", "5", "6", "7", "8", "9">]
