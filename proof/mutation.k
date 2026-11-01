requires "semantics.k"
module RUN2-SGLANG06-MUTATION
  imports MPY
  claim [original-must-admit]:
    <k> Assign(Name("token_capacity"), Name("capacity"))
        Assign(Name("max_new_tokens"), BinOp("-", BinOp("-", BinOp("-", Name("token_capacity"), Name("paged_input")), Name("page_size")), Int(1)))
        If(Compare(Name("requested"), CmpOp("<", Name("max_new_tokens"))), (Assign(Name("max_new_tokens"), Name("requested")) .Stmts), ( .Stmts))
        If(Compare(Name("max_new_tokens"), CmpOp("<", Int(0))), (Assign(Name("max_new_tokens"), Int(0)) .Stmts), ( .Stmts))
        Assign(Name("min_free_tokens"), BinOp("-", BinOp("-", Name("capacity"), BinOp("+", Name("paged_input"), Name("page_size"))), Name("max_new_tokens")))
        Assign(Name("blocked"), Compare(Name("min_free_tokens"), CmpOp("<=", Name("reserve")))) .Stmts => .K </k>
    <env> 0 </env>
    <scopes> (0 |-> scope("capacity" |-> 600 "paged_input" |-> 560 "page_size" |-> 1 "reserve" |-> 1 "requested" |-> 1000, parent(-1))) (-1 |-> builtinsScope)
          => (0 |-> scope("capacity" |-> 600 "paged_input" |-> 560 "page_size" |-> 1 "reserve" |-> 1 "requested" |-> 1000 "token_capacity" |-> 600 "max_new_tokens" |-> 38 "min_free_tokens" |-> 1 "blocked" |-> false, parent(-1))) (-1 |-> builtinsScope) </scopes>
    <scopeLoc> 1 </scopeLoc>
    <heap> .Map </heap>
    <heapLoc> 0 </heapLoc>
    <stack> .List </stack>
    <ret> noRet </ret>
    <exc> NoExc </exc>
    <exit-code> 0 </exit-code>
    requires true
    
endmodule
