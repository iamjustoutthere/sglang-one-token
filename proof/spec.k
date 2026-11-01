requires "semantics.k"
module RUN2-SGLANG06-SPEC
  imports MPY
  claim [requested-binds]:
    <k> Assign(Name("token_capacity"), BinOp("-", Name("capacity"), Name("reserve")))
        Assign(Name("max_new_tokens"), BinOp("-", BinOp("-", BinOp("-", Name("token_capacity"), Name("paged_input")), Name("page_size")), Int(1)))
        If(Compare(Name("requested"), CmpOp("<", Name("max_new_tokens"))), (Assign(Name("max_new_tokens"), Name("requested")) .Stmts), ( .Stmts))
        If(Compare(Name("max_new_tokens"), CmpOp("<", Int(0))), (Assign(Name("max_new_tokens"), Int(0)) .Stmts), ( .Stmts))
        Assign(Name("min_free_tokens"), BinOp("-", BinOp("-", Name("capacity"), BinOp("+", Name("paged_input"), Name("page_size"))), Name("max_new_tokens")))
        Assign(Name("blocked"), Compare(Name("min_free_tokens"), CmpOp("<=", Name("reserve")))) .Stmts => .K </k>
    <env> 0 </env>
    <scopes> (0 |-> scope("capacity" |-> T "paged_input" |-> I "page_size" |-> P
                  "reserve" |-> R "requested" |-> M, parent(-1))) (-1 |-> builtinsScope)
          => (0 |-> scope("capacity" |-> T "paged_input" |-> I "page_size" |-> P
                  "reserve" |-> R "requested" |-> M "token_capacity" |-> (T -Int R)
                  "max_new_tokens" |-> M "min_free_tokens" |-> (T -Int I -Int P -Int M) "blocked" |-> false, parent(-1))) (-1 |-> builtinsScope) </scopes>
    <scopeLoc> 1 </scopeLoc>
    <heap> .Map </heap>
    <heapLoc> 0 </heapLoc>
    <stack> .List </stack>
    <ret> noRet </ret>
    <exc> NoExc </exc>
    <exit-code> 0 </exit-code>
    requires I >=Int 0 andBool P >=Int 1 andBool R >=Int 1 andBool M >=Int 0
         andBool T >=Int I +Int P +Int R +Int 1
         andBool M <=Int (T -Int R -Int I -Int P -Int 1)
    
  claim [capacity-binds]:
    <k> Assign(Name("token_capacity"), BinOp("-", Name("capacity"), Name("reserve")))
        Assign(Name("max_new_tokens"), BinOp("-", BinOp("-", BinOp("-", Name("token_capacity"), Name("paged_input")), Name("page_size")), Int(1)))
        If(Compare(Name("requested"), CmpOp("<", Name("max_new_tokens"))), (Assign(Name("max_new_tokens"), Name("requested")) .Stmts), ( .Stmts))
        If(Compare(Name("max_new_tokens"), CmpOp("<", Int(0))), (Assign(Name("max_new_tokens"), Int(0)) .Stmts), ( .Stmts))
        Assign(Name("min_free_tokens"), BinOp("-", BinOp("-", Name("capacity"), BinOp("+", Name("paged_input"), Name("page_size"))), Name("max_new_tokens")))
        Assign(Name("blocked"), Compare(Name("min_free_tokens"), CmpOp("<=", Name("reserve")))) .Stmts => .K </k>
    <env> 0 </env>
    <scopes> (0 |-> scope("capacity" |-> T "paged_input" |-> I "page_size" |-> P
                  "reserve" |-> R "requested" |-> M, parent(-1))) (-1 |-> builtinsScope)
          => (0 |-> scope("capacity" |-> T "paged_input" |-> I "page_size" |-> P
                  "reserve" |-> R "requested" |-> M "token_capacity" |-> (T -Int R)
                  "max_new_tokens" |-> (T -Int R -Int I -Int P -Int 1) "min_free_tokens" |-> (T -Int I -Int P -Int (T -Int R -Int I -Int P -Int 1)) "blocked" |-> false, parent(-1))) (-1 |-> builtinsScope) </scopes>
    <scopeLoc> 1 </scopeLoc>
    <heap> .Map </heap>
    <heapLoc> 0 </heapLoc>
    <stack> .List </stack>
    <ret> noRet </ret>
    <exc> NoExc </exc>
    <exit-code> 0 </exit-code>
    requires I >=Int 0 andBool P >=Int 1 andBool R >=Int 1 andBool M >=Int 0
         andBool T >=Int I +Int P +Int R +Int 1
         andBool M >Int (T -Int R -Int I -Int P -Int 1)
    
endmodule
