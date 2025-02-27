function test_parse(production, code; v=v"1.6")
    stream = ParseStream(code, version=v)
    production(JuliaSyntax.ParseState(stream))
    t = JuliaSyntax.build_tree(GreenNode, stream, wrap_toplevel_as_kind=K"None")
    source = SourceFile(code)
    s = SyntaxNode(source, t)
    if JuliaSyntax.kind(s) == K"None"
        join([sprint(show, MIME("text/x.sexpression"), c) for c in children(s)], ' ')
    else
        sprint(show, MIME("text/x.sexpression"), s)
    end
end

# TODO:
# * Extract the following test cases from the source itself.
# * Use only the green tree to generate the S-expressions
#   (add flag annotations to heads)
tests = [
    JuliaSyntax.parse_toplevel => [
        "a \n b"     =>  "(toplevel a b)"
        "a;b \n c;d" =>  "(toplevel (toplevel a b) (toplevel c d))"
        "a \n \n"    =>  "(toplevel a)"
        ""           =>  "(toplevel)"
    ],
    JuliaSyntax.parse_block => [
        "a;b;c"   => "(block a b c)"
        "a;;;b;;" => "(block a b)"
        ";a"      => "(block a)"
        "\n a"    => "(block a)"
        "a\nb"    => "(block a b)"
    ],
    JuliaSyntax.parse_stmts => [
        "a;b;c"   => "(toplevel a b c)"
        "a;;;b;;" => "(toplevel a b)"
        """ "x" a ; "y" b """ =>
            """(toplevel (macrocall :(Core.var"@doc") "x" a) (macrocall :(Core.var"@doc") "y" b))"""
        "x y"  =>  "x (error-t y)"
    ],
    JuliaSyntax.parse_eq => [
        # parse_assignment
        "a = b"       =>  "(= a b)"
        "a .= b"      =>  "(.= a b)"
        "a += b"      =>  "(+= a b)"
        "a .+= b"     =>  "(.+= a b)"
        "a, b = c, d" =>  "(= (tuple a b) (tuple c d))"
        "x, = xs"     =>  "(= (tuple x) xs)"
        "[a ~b]"      =>  "(hcat a (call ~ b))"
        "a ~ b"       =>  "(call-i a ~ b)"
        "[a ~ b c]"   =>  "(hcat (call-i a ~ b) c)"
    ],
    JuliaSyntax.parse_pair => [
        "a => b"  =>  "(call-i a => b)"
    ],
    JuliaSyntax.parse_cond => [
        "a ? b : c"   => "(if a b c)"
        "a ?\nb : c"  => "(if a b c)"
        "a ? b :\nc"  => "(if a b c)"
        "a ? b : c:d" =>   "(if a b (call-i c : d))"
        # Following are errors but should recover
        "a? b : c"    => "(if a (error-t) b c)"
        "a ?b : c"    => "(if a (error-t) b c)"
        "a ? b: c"    => "(if a b (error-t) c)"
        "a ? b :c"    => "(if a b (error-t) c)"
        "a ? b c"     => "(if a b (error-t) c)"
    ],
    JuliaSyntax.parse_arrow => [
        "x → y"     =>  "(call-i x → y)"
        "x <--> y"  =>  "(call-i x <--> y)"
        "x --> y"   =>  "(--> x y)"
        "x .--> y"  =>  "(call-i x .--> y)"
        "x -->₁ y"  =>  "(call-i x -->₁ y)"
    ],
    JuliaSyntax.parse_or => [
        "x || y || z" => "(|| x (|| y z))"
        ((v=v"1.6",), "x .|| y") => "(error (.|| x y))"
        ((v=v"1.7",), "x .|| y") => "(.|| x y)"
    ],
    JuliaSyntax.parse_and => [
        "x && y && z" => "(&& x (&& y z))"
        ((v=v"1.6",), "x .&& y") => "(error (.&& x y))"
        ((v=v"1.7",), "x .&& y") => "(.&& x y)"
    ],
    JuliaSyntax.parse_comparison => [
        # Type comparisons are syntactic
        "x <: y"      => "(<: x y)"
        "x >: y"      => "(>: x y)"
        # Normal binary comparisons
        "x < y"       => "(call-i x < y)"
        # Comparison chains
        "x < y < z"   => "(comparison x < y < z)"
        "x == y < z"  => "(comparison x == y < z)"
    ],
    JuliaSyntax.parse_pipe_lt => [
        "x <| y <| z" => "(call-i x <| (call-i y <| z))"
    ],
    JuliaSyntax.parse_pipe_gt => [
        "x |> y |> z" => "(call-i (call-i x |> y) |> z)"
    ],
    JuliaSyntax.parse_range => [
        "1:2"       => "(call-i 1 : 2)"
        "1:2:3"     => "(call-i 1 : 2 3)"
        "a:b:c:d:e" => "(call-i (call-i a : b c) : d e)"
        "a :< b"    => "(call-i a (error : <) b)"
    ],
    JuliaSyntax.parse_range => [
        "a..b"       => "(call-i a .. b)"
        "a … b"      => "(call-i a … b)"
        "[1 :a]"     => "(hcat 1 (quote a))"
        "[1 2:3 :a]" =>  "(hcat 1 (call-i 2 : 3) (quote a))"
        "x..."     => "(... x)"
        "x:y..."   => "(... (call-i x : y))"
        "x..y..."  => "(... (call-i x .. y))"
    ],
    JuliaSyntax.parse_expr => [
        "a - b - c"  => "(call-i (call-i a - b) - c)"
        "a + b + c"  => "(call-i a + b c)"
        "a + b .+ c" => "(call-i (call-i a + b) .+ c)"
        # parse_with_chains:
        # The following is two elements of a hcat
        "[x +y]"     =>  "(hcat x (call + y))"
        "[x+y +z]"   =>  "(hcat (call-i x + y) (call + z))"
        # Conversely the following are infix calls
        "[x +₁y]"    =>  "(vect (call-i x +₁ y))"
        "[x+y+z]"    =>  "(vect (call-i x + y z))"
        "[x+y + z]"  =>  "(vect (call-i x + y z))"
        # Dotted and normal operators
        "a +₁ b +₁ c"  =>  "(call-i (call-i a +₁ b) +₁ c)"
        "a .+ b .+ c"  =>  "(call-i (call-i a .+ b) .+ c)"
    ],
    JuliaSyntax.parse_term => [
        "a * b * c"  => "(call-i a * b c)"
        # parse_unary
        "-2*x"   =>  "(call-i -2 * x)"
        ":T"     =>  "(quote T)"
        "in::T"  =>  "(:: in T)"
        "isa::T" =>  "(:: isa T)"
    ],
    JuliaSyntax.parse_juxtapose => [
        "2x"         => "(call-i 2 * x)"
        "2x"         => "(call-i 2 * x)"
        "2(x)"       => "(call-i 2 * x)"
        "(2)(3)x"    => "(call-i 2 * 3 x)"
        "(x-1)y"     => "(call-i (call-i x - 1) * y)"
        "x'y"        => "(call-i (' x) * y)"
        # errors
        "\"a\"\"b\"" => "(call-i \"a\" * (error-t) \"b\")"
        "\"a\"x"     => "(call-i \"a\" * (error-t) x)"
        # Not juxtaposition - parse_juxtapose will consume only the first token.
        "x.3"       =>  "x"
        "sqrt(2)2"  =>  "(call sqrt 2)"
        "x' y"      =>  "(' x)"
        "x 'y"      =>  "x"
        "0xenomorph" => "0x0e"
    ],
    JuliaSyntax.parse_unary => [
        "+2"       => "2"
        "-2^x"     => "(call - (call-i 2 ^ x))"
        "-2[1, 3]" => "(call - (ref 2 1 3))"
    ],
    JuliaSyntax.parse_unary_call => [
        # Standalone dotted operators are parsed as (|.| op)
        ".+"   =>  "(. +)"
        ".+\n" =>  "(. +)"
        ".+ =" =>  "(. +)"
        ".+)"  =>  "(. +)"
        ".&"   =>  "(. &)"
        # Standalone non-dotted operators
        "+)"   =>  "+"
        # Call with type parameters or non-unary prefix call
        "+{T}(x::T)"  =>  "(call (curly + T) (:: x T))"
        "*(x)"        =>  "(call * x)"
        # Prefix function calls for operators which are both binary and unary
        "+(a,b)"   =>  "(call + a b)"
        "+(a=1,)"  =>  "(call + (kw a 1))"
        "+(a...)"  =>  "(call + (... a))"
        "+(a;b,c)" =>  "(call + a (parameters b c))"
        "+(;a)"    =>  "(call + (parameters a))"
        # Whitespace not allowed before prefix function call bracket
        "+ (a,b)"  =>  "(call + (error) a b)"
        # Prefix calls have higher precedence than ^
        "+(a,b)^2"  =>  "(call-i (call + a b) ^ 2)"
        "+(a,b)(x)^2"  =>  "(call-i (call (call + a b) x) ^ 2)"
        # Unary function calls with brackets as grouping, not an arglist
        "+(a;b)"  =>  "(call + (block a b))"
        "+(a=1)"  =>  "(call + (= a 1))"
        # Unary operators have lower precedence than ^
        "+(a)^2"  =>  "(call + (call-i a ^ 2))"
        "+(a)(x,y)^2"  =>  "(call + (call-i (call a x y) ^ 2))"
        # Normal unary calls (see parse_unary)
        "+x" => "(call + x)"
        "√x" => "(call √ x)"
        "±x" => "(call ± x)"
        # Not a unary operator
        "/x"     => "(call (error /) x)"
        "+₁ x"   => "(call (error +₁) x)"
        ".<: x"  => "(call (error .<:) x)"
    ],
    JuliaSyntax.parse_factor => [
        "x^y"      =>  "(call-i x ^ y)"
        "x^y^z"    =>  "(call-i x ^ (call-i y ^ z))"
        "begin x end::T"  =>  "(:: (block x) T)"
        # parse_decl_with_initial_ex
        "a::b"     =>  "(:: a b)"
        "a->b"     =>  "(-> a b)"
        "a::b::c"  =>  "(:: (:: a b) c)"
        "a::b->c"  =>  "(-> (:: a b) c)"
    ],
    JuliaSyntax.parse_unary_subtype => [
        "<: )"    =>  "<:"
        "<: \n"   =>  "<:"
        "<: ="    =>  "<:"
        "<:{T}(x::T)"   =>  "(call (curly <: T) (:: x T))"
        "<:(x::T)"      =>  "(<: (:: x T))"
        "<: A where B"  =>  "(<: (where A B))"
        # Really for parse_where
        "x where \n {T}"  =>  "(where x T)"
        "x where {T,S}"  =>  "(where x T S)"
        "x where {T S}"  =>  "(where x (bracescat (row T S)))"
        "x where {y for y in ys}"  =>  "(where x (braces (generator y (= y ys))))"
        "x where T"  =>  "(where x T)"
        "x where \n T"  =>  "(where x T)"
        "x where T<:S"  =>  "(where x (<: T S))"
    ],
    JuliaSyntax.parse_unary_prefix => [
        "&)"   => "&"
        "\$\n" => "\$"
        "&a"   => "(& a)"
        "::a"  => "(:: a)"
        "\$a"  => "(\$ a)"
        "\$\$a"  => "(\$ (\$ a))"
    ],
    JuliaSyntax.parse_call => [
        # Mostly parse_call_chain
        "f(x)"    =>  "(call f x)"
        "\$f(x)"  =>  "(call (\$ f) x)"
        "f(a,b)"  => "(call f a b)"
        "f (a)" => "(call f (error-t) a)"
        "f(a).g(b)" => "(call (. (call f a) (quote g)) b)"
        "\$A.@x"    =>  "(macrocall (. (\$ A) (quote @x)))"
        # do
        "f() do\nend"         =>  "(do (call f) (-> (tuple) (block)))"
        "f() do ; body end"   =>  "(do (call f) (-> (tuple) (block body)))"
        "f() do x, y\n body end"  =>  "(do (call f) (-> (tuple x y) (block body)))"
        "f(x) do y body end"  =>  "(do (call f x) (-> (tuple y) (block body)))"
        # Keyword arguments depend on call vs macrocall
        "foo(a=1)"  =>  "(call foo (kw a 1))"
        "@foo(a=1)" =>  "(macrocall @foo (= a 1))"
        "@foo a b"     =>  "(macrocall @foo a b)"
        "@foo (x)"     =>  "(macrocall @foo x)"
        "@foo (x,y)"   =>  "(macrocall @foo (tuple x y))"
        "A.@foo a b"   =>  "(macrocall (. A (quote @foo)) a b)"
        "@A.foo a b"   =>  "(macrocall (. A (quote @foo)) a b)"
        "[@foo \"x\"]"   =>  "(vect (macrocall @foo \"x\"))"
        "[f (x)]"     =>  "(hcat f x)"
        "[f \"x\"]"   =>  "(hcat f \"x\")"
        # Macro names
        "@! x"  => "(macrocall @! x)"
        "@.. x" => "(macrocall @.. x)"
        "@\$ y"  => "(macrocall @\$ y)"
        # Special @doc parsing rules
        "@doc x\ny"    =>  "(macrocall @doc x y)"
        "A.@doc x\ny"  =>  "(macrocall (. A (quote @doc)) x y)"
        "@A.doc x\ny"  =>  "(macrocall (. A (quote @doc)) x y)"
        "@doc x y\nz"  =>  "(macrocall @doc x y)"
        "@doc x\n\ny"  =>  "(macrocall @doc x)"
        "@doc x\nend"  =>  "(macrocall @doc x)"
        # .' discontinued
        "f.'"    =>  "f (error-t . ')"
        # Allow `@` in macrocall only in first and last position
        "A.B.@x"    =>  "(macrocall (. (. A (quote B)) (quote @x)))"
        "@A.B.x"    =>  "(macrocall (. (. A (quote B)) (quote @x)))"
        "A.@B.x"    =>  "(macrocall (. (. A (quote B)) (error-t) (quote @x)))"
        "A.@. y"    =>  "(macrocall (. A (quote @__dot__)) y)"
        "a().@x(y)" =>  "(macrocall (error (. (call a) (quote x))) y)"
        "a().@x y"  =>  "(macrocall (error (. (call a) (quote x))) y)"
        "a().@x{y}" =>  "(macrocall (error (. (call a) (quote x))) (braces y))"
        # array indexing, typed comprehension, etc
        "a().@x[1]" => "(macrocall (ref (error (. (call a) (quote x))) 1))"
        "a[i]"  =>  "(ref a i)"
        "a [i]"  =>  "(ref a (error-t) i)"
        "a[i,j]"  =>  "(ref a i j)"
        "T[x   y]"  =>  "(typed_hcat T x y)"
        "T[x ; y]"  =>  "(typed_vcat T x y)"
        "T[a b; c d]"  =>  "(typed_vcat T (row a b) (row c d))"
        "T[x for x in xs]"  =>  "(typed_comprehension T (generator x (= x xs)))"
        ((v=v"1.8",), "T[a ; b ;; c ; d]") => "(typed_ncat-2 T (nrow-1 a b) (nrow-1 c d))"
        # Keyword params always use kw inside tuple in dot calls
        "f.(a,b)"   =>  "(. f (tuple a b))"
        "f.(a=1)"   =>  "(. f (tuple (kw a 1)))"
        "f. (x)"    =>  "(. f (error-t) (tuple x))"
        # Other dotted syntax
        "A.:+"      =>  "(. A (quote +))"
        "A.: +"     =>  "(. A (quote (error-t) +))"
        "f.\$x"     =>  "(. f (inert (\$ x)))"
        "f.\$(x+y)" =>  "(. f (inert (\$ (call-i x + y))))"
        "A.\$B.@x"  =>  "(macrocall (. (. A (inert (\$ B))) (quote @x)))"
        # Field/property syntax
        "f.x.y"  =>  "(. (. f (quote x)) (quote y))"
        "x .y"   =>  "(. x (error-t) (quote y))"
        # Adjoint
        "f'"  => "(' f)"
        "f'ᵀ" => "(call-i f 'ᵀ)"
        # Curly calls
        "@S{a,b}" => "(macrocall @S (braces a b))"
        "S{a,b}"  => "(curly S a b)"
        "S {a}"   =>  "(curly S (error-t) a)"
        # String macros
        "x\"str\""   => """(macrocall @x_str "str")"""
        "x`str`"     => """(macrocall @x_cmd "str")"""
        "x\"\""      => """(macrocall @x_str "")"""
        "x``"        => """(macrocall @x_cmd "")"""
        # Triple quoted procesing for custom strings
        "r\"\"\"\nx\"\"\""        => raw"""(macrocall @r_str "x")"""
        "r\"\"\"\n x\n y\"\"\""   => raw"""(macrocall @r_str (string-sr "x\n" "y"))"""
        "r\"\"\"\n x\\\n y\"\"\"" => raw"""(macrocall @r_str (string-sr "x\\\n" "y"))"""
        # Macro sufficies can include keywords and numbers
        "x\"s\"y"    => """(macrocall @x_str "s" "y")"""
        "x\"s\"end"  => """(macrocall @x_str "s" "end")"""
        "x\"s\"in"   => """(macrocall @x_str "s" "in")"""
        "x\"s\"2"    => """(macrocall @x_str "s" 2)"""
        "x\"s\"10.0" => """(macrocall @x_str "s" 10.0)"""
    ],
    JuliaSyntax.parse_resword => [
        # In normal_context
        "begin f() where T = x end" => "(block (= (where (call f) T) x))"
        # block
        "begin end"         =>  "(block)"
        "begin a ; b end"   =>  "(block a b)"
        "begin\na\nb\nend"  =>  "(block a b)"
        # quote
        "quote end"         =>  "(quote (block))"
        "quote body end"    =>  "(quote (block body))"
        # while
        "while cond body end"  =>  "(while cond (block body))"
        "while x < y \n a \n b \n end"  =>  "(while (call-i x < y) (block a b))"
        # for
        "for x in xs end" => "(for (= x xs) (block))"
        "for x in xs, y in ys \n a \n end" => "(for (block (= x xs) (= y ys)) (block a))"
        # let
        "let x=1\n end"    =>  "(let (= x 1) (block))"
        "let x ; end"      =>  "(let x (block))"
        "let x=1 ; end"    =>  "(let (= x 1) (block))"
        "let x::1 ; end"   =>  "(let (:: x 1) (block))"
        "let x=1,y=2 end"  =>  "(let (block (= x 1) (= y 2)) (block))"
        "let x+=1 ; end"   =>  "(let (block (+= x 1)) (block))"
        "let ; end"        =>  "(let (block) (block))"
        "let ; body end"   =>  "(let (block) (block body))"
        "let\na\nb\nend"   =>  "(let (block) (block a b))"
        # abstract type
        "abstract type A end"            =>  "(abstract A)"
        "abstract type A ; end"          =>  "(abstract A)"
        "abstract type \n\n A \n\n end"  =>  "(abstract A)"
        "abstract type A <: B end"       =>  "(abstract (<: A B))"
        "abstract type A <: B{T,S} end"  =>  "(abstract (<: A (curly B T S)))"
        "abstract type A < B end"        =>  "(abstract (call-i A < B))"
        # primitive type
        "primitive type A 32 end"   =>  "(primitive A 32)"
        "primitive type A 32 ; end" =>  "(primitive A 32)"
        "primitive type A \$N end"  =>  "(primitive A (\$ N))"
        "primitive type A <: B \n 8 \n end"  =>  "(primitive (<: A B) 8)"
        # struct
        "struct A <: B \n a::X \n end"  =>  "(struct false (<: A B) (block (:: a X)))"
        "mutable struct A end"          =>  "(struct true A (block))"
        "struct A end"    =>  "(struct false A (block))"
        "struct try end"  =>  "(struct false (error (try)) (block))"
        # return
        "return\nx"   =>  "(return nothing)"
        "return)"     =>  "(return nothing)"
        "return x"    =>  "(return x)"
        "return x,y"  =>  "(return (tuple x y))"
        # break/continue
        "break"    => "(break)"
        "continue" => "(continue)"
        # module/baremodule
        "module A end"      =>  "(module true A (block))"
        "baremodule A end"  =>  "(module false A (block))"
        "module do \n end"  =>  "(module true (error (do)) (block))"
        "module \$A end"    =>  "(module true (\$ A) (block))"
        "module A \n a \n b \n end"  =>  "(module true A (block a b))"
        """module A \n "x"\na\n end""" => """(module true A (block (macrocall :(Core.var"@doc") "x" a)))"""
        # export
        "export a"  =>  "(export a)"
        "export @a"  =>  "(export @a)"
        "export a, \n @b"  =>  "(export a @b)"
        "export +, =="  =>  "(export + ==)"
        "export \n a"  =>  "(export a)"
        "export \$a, \$(a*b)"  =>  "(export (\$ a) (\$ (call-i a * b)))"
        "export (x::T)"  =>  "(export (error (:: x T)))"
        "export outer"  =>  "(export outer)"
        "export (\$f)"  =>  "(export (\$ f))"
    ],
    JuliaSyntax.parse_if_elseif => [
        "if a xx elseif b yy else zz end" => "(if a (block xx) (elseif b (block yy) (block zz)))"
        "if end"        =>  "(if (error) (block))"
        "if \n end"     =>  "(if (error) (block))"
        "if a end"      =>  "(if a (block))"
        "if a xx end"   =>  "(if a (block xx))"
        "if a \n\n xx \n\n end"   =>  "(if a (block xx))"
        "if a xx elseif b yy end"   =>  "(if a (block xx) (elseif b (block yy)))"
        "if a xx else if b yy end"  =>  "(if a (block xx) (error-t) (elseif b (block yy)))"
        "if a xx else yy end"   =>  "(if a (block xx) (block yy))"
    ],
    JuliaSyntax.parse_const_local_global => [
        "global x"             =>  "(global x)"
        "local x"              =>  "(local x)"
        "global const x = 1"   =>  "(const (global (= x 1)))"
        "local const x = 1"    =>  "(const (local (= x 1)))"
        "const x = 1"          =>  "(const (= x 1))"
        "const global x = 1"   =>  "(const (global (= x 1)))"
        "const local x = 1"    =>  "(const (local (= x 1)))"
        "const x,y = 1,2"      =>  "(const (= (tuple x y) (tuple 1 2)))"
        ((v=v"1.8",), "const x,y")  => "(const (tuple x y))"
        "const x = 1"   =>  "(const (= x 1))"
        "global x ~ 1"  =>  "(global (call-i x ~ 1))"
        "global x += 1" =>  "(global (+= x 1))"
        "global x"    =>  "(global x)"
        "local x"     =>  "(local x)"
        "global x,y"  =>  "(global x y)"
        ((v=v"1.8",), "const x")      => "(const x)"
        ((v=v"1.8",), "const x::T")   => "(const (:: x T))"
        ((v=v"1.7",), "const x")      => "(const (error x))"
        ((v=v"1.7",), "const x .= 1") => "(const (error (.= x 1)))"
    ],
    JuliaSyntax.parse_function => [
        "macro while(ex) end"  =>  "(macro (call (error while) ex) (block))"
        "macro f()     end"    =>  "(macro (call f) (block))"
        "macro (:)(ex) end"    =>  "(macro (call : ex) (block))"
        "macro (type)(ex) end" =>  "(macro (call type ex) (block))"
        "macro \$f()    end"   =>  "(macro (call (\$ f)) (block))"
        "macro (\$f)()  end"   =>  "(macro (call (\$ f)) (block))"
        "function (x) body end"=>  "(function (tuple x) (block body))"
        "function (x,y) end"   =>  "(function (tuple x y) (block))"
        "function (x=1) end"   =>  "(function (tuple (kw x 1)) (block))"
        "function (;x=1) end"  =>  "(function (tuple (parameters (kw x 1))) (block))"
        "function (:)() end"   =>  "(function (call :) (block))"
        "function (x::T)() end"=>  "(function (call (:: x T)) (block))"
        "function (::T)() end" =>  "(function (call (:: T)) (block))"
        "function begin() end" =>  "(function (call (error begin)) (block))"
        "function f() end"     =>  "(function (call f) (block))"
        "function type() end"  =>  "(function (call type) (block))"
        "function \n f() end"  =>  "(function (call f) (block))"
        "function \$f() end"   =>  "(function (call (\$ f)) (block))"
        "function (:)() end"   =>  "(function (call :) (block))"
        "function (::Type{T})(x) end"  =>  "(function (call (:: (curly Type T)) x) (block))"
        # Function/macro definition with no methods
        "function f end"      =>  "(function f)"
        "function f \n\n end" =>  "(function f)"
        "function \$f end"    =>  "(function (\$ f))"
        "macro f end"         =>  "(macro f)"
        # Function argument list
        "function f(x,y) end"    =>  "(function (call f x y) (block))"
        "function f{T}() end"    =>  "(function (call (curly f T)) (block))"
        "function A.f()   end"   =>  "(function (call (. A (quote f))) (block))"
        "function f body end"    =>  "(function (error f) (block body))"
        "function f()::T    end" =>  "(function (:: (call f) T) (block))"
        "function f()::g(T) end" =>  "(function (:: (call f) (call g T)) (block))"
        "function f() where {T} end"  =>  "(function (where (call f) T) (block))"
        "function f() where T   end"  =>  "(function (where (call f) T) (block))"
        "function f() \n a \n b end"  =>  "(function (call f) (block a b))"
        "function f() end"       =>  "(function (call f) (block))"
        # Errors
        "function"            => "(function (error (error)) (block (error)) (error-t))"
    ],
    JuliaSyntax.parse_try => [
        "try \n x \n catch e \n y \n finally \n z end" =>
            "(try (block x) e (block y) false (block z))"
        ((v=v"1.8",), "try \n x \n catch e \n y \n else z finally \n w end") =>
            "(try (block x) e (block y) (block z) (block w))"
        "try x catch end"       =>  "(try (block x) false (block) false false)"
        "try x catch ; y end"   =>  "(try (block x) false (block y) false false)"
        "try x catch \n y end"  =>  "(try (block x) false (block y) false false)"
        "try x catch e y end"   =>  "(try (block x) e (block y) false false)"
        "try x catch \$e y end" =>  "(try (block x) (\$ e) (block y) false false)"
        "try x finally y end"   =>  "(try (block x) false false false (block y))"
        # v1.8 only
        ((v=v"1.8",), "try catch ; else end") => "(try (block) false (block) (block) false)"
        ((v=v"1.8",), "try else end") => "(try (block) false false (error (block)) false)"
        ((v=v"1.7",), "try catch ; else end")  =>  "(try (block) false (block) (error (block)) false)"
        # finally before catch :-(
        "try x finally y catch e z end"  =>  "(try-f (block x) false false false (block y) e (block z))"
    ],
    JuliaSyntax.parse_imports => [
        "import A as B: x"  => "(import (: (error (as (. A) B)) (. x)))"
        "import A, y"       => "(import (. A) (. y))"
        "import A: +, =="       => "(import (: (. A) (. +) (. ==)))"
        "import A: x, y"    => "(import (: (. A) (. x) (. y)))"
        "import A: x, B: y" => "(import (: (. A) (. x) (. B) (error-t (. y))))"
        "import A: x"       => "(import (: (. A) (. x)))"
        "using  A"          => "(using (. A))"
        "import A"          => "(import (. A))"
        # parse_import
        "import A: x, y"   =>  "(import (: (. A) (. x) (. y)))"
        "import A as B"    =>  "(import (as (. A) B))"
        "import A: x as y" =>  "(import (: (. A) (as (. x) y)))"
        "using  A: x as y" =>  "(using (: (. A) (as (. x) y)))"
        ((v=v"1.5",), "import A as B") =>  "(import (error (as (. A) B)))"
        "using A as B"     =>  "(using (error (as (. A) B)))"
        "using A, B as C"  =>  "(using (. A) (error (as (. B) C)))"
        # parse_import_path
        # When parsing import we must split initial dots into nontrivial
        # leading dots for relative paths
        "import .A"  =>  "(import (. . A))"
        "import ..A"  =>  "(import (. . . A))"
        "import ...A"  =>  "(import (. . . . A))"
        "import ....A"  =>  "(import (. . . . . A))"
        # Dots with spaces are allowed (a misfeature?)
        "import . .A"  =>  "(import (. . . A))"
        # Modules with operator symbol names
        "import .⋆"  =>  "(import (. . ⋆))"
        # Expressions allowed in import paths
        "import @x"  =>  "(import (. @x))"
        "import \$A"  =>  "(import (. (\$ A)))"
        "import \$A.@x"  =>  "(import (. (\$ A) @x))"
        "import A.B"  =>  "(import (. A B))"
        "import A.B.C"  =>  "(import (. A B C))"
        "import A.=="  =>  "(import (. A ==))"
        "import A.⋆.f" =>  "(import (. A ⋆ f))"
        "import A..."  =>  "(import (. A ..))"
        "import A; B"  =>  "(import (. A))"
    ],
    JuliaSyntax.parse_iteration_spec => [
        "i = rhs"        =>  "(= i rhs)"
        "i in rhs"       =>  "(= i rhs)"
        "i ∈ rhs"        =>  "(= i rhs)"
        "i = 1:10"       =>  "(= i (call-i 1 : 10))"
        "(i,j) in iter"  =>  "(= (tuple i j) iter)"
        "outer = rhs"       =>  "(= outer rhs)"
        "outer <| x = rhs"  =>  "(= (call-i outer <| x) rhs)"
        "outer i = rhs"     =>  "(= (outer i) rhs)"
        "outer (x,y) = rhs" =>  "(= (outer (tuple x y)) rhs)"
    ],
    JuliaSyntax.parse_paren => [
        # Tuple syntax with commas
        "()"          =>  "(tuple)"
        "(x,)"        =>  "(tuple x)"
        "(x,y)"       =>  "(tuple x y)"
        "(x=1, y=2)"  =>  "(tuple (= x 1) (= y 2))"
        # Named tuples with initial semicolon
        "(;)"         =>  "(tuple (parameters))"
        "(; a=1)"     =>  "(tuple (parameters (kw a 1)))"
        # Extra credit: nested parameters and frankentuples
        "(x...; y)"       => "(tuple (... x) (parameters y))"
        "(x...;)"         => "(tuple (... x) (parameters))"
        "(; a=1; b=2)"    => "(tuple (parameters (kw a 1) (parameters (kw b 2))))"
        "(a; b; c,d)"     => "(tuple a (parameters b (parameters c d)))"
        "(a=1, b=2; c=3)" => "(tuple (= a 1) (= b 2) (parameters (kw c 3)))"
        # Block syntax
        "(;;)"        =>  "(block)"
        "(a=1;)"      =>  "(block (= a 1))"
        "(a;b;;c)"    =>  "(block a b c)"
        "(a=1; b=2)"  =>  "(block (= a 1) (= b 2))"
        # Parentheses used for grouping
        "(a * b)"     =>  "(call-i a * b)"
        "(a=1)"       =>  "(= a 1)"
        "(x)"         =>  "x"
        "(a...)"      =>  "(... a)"
        # Generators
        "(x for a in as)"       =>  "(generator x (= a as))"
        "(x \n\n for a in as)"  =>  "(generator x (= a as))"
    ],
    JuliaSyntax.parse_atom => [
        ":foo"   => "(quote foo)"
        ": foo"  => "(quote (error-t) foo)"
        # Literal colons
        ":)"     => ":"
        ": end"  => ":"
        # plain equals
        "="      => "(error =)"
        # Identifiers
        "xx"     => "xx"
        "x₁"     => "x₁"
        # var syntax
        """var"x" """  =>  "x"
        """var"x"+"""  =>  "x"
        """var"x")"""  =>  "x"
        """var"x"("""  =>  "x"
        """var"x"end"""  =>  "x (error (end))"
        """var"x"1"""  =>  "x (error 1)"
        """var"x"y"""  =>  "x (error y)"
        # var syntax raw string unescaping
        "var\"\""          =>  ""
        "var\"\\\"\""      =>  "\""
        "var\"\\\\\\\"\""  =>  "\\\""
        "var\"\\\\x\""     =>  "\\\\x"
        # Syntactic operators
        "+="  =>  "(error +=)"
        ".+="  =>  "(error .+=)"
        # Normal operators
        "+"  =>  "+"
        "~"  =>  "~"
        # Quoted syntactic operators allowed
        ":+="  =>  "(quote +=)"
        ":.="  =>  "(quote .=)"
        # Special symbols quoted
        ":end" => "(quote end)"
        ":(end)" => "(quote (error-t))"
        ":<:"  => "(quote <:)"
        # unexpect =
        "="    => "(error =)"
        # parse_cat
        "[]"        =>  "(vect)"
        "[x,]"      =>  "(vect x)"
        "[x]"       =>  "(vect x)"
        "[x \n ]"   =>  "(vect x)"
        "[x"        =>  "(vect x (error-t))"
        "[x \n\n ]" =>  "(vect x)"
        "[x for a in as]"  =>  "(comprehension (generator x (= a as)))"
        "[x \n\n for a in as]"  =>  "(comprehension (generator x (= a as)))"
        # parse_generator
        "[x for a = as for b = bs if cond1 for c = cs if cond2]"  =>  "(comprehension (flatten x (= a as) (filter (= b bs) cond1) (filter (= c cs) cond2)))"
        "[(x)for x in xs]"  =>  "(comprehension (generator x (error-t) (= x xs)))"
        "(a for x in xs if cond)"  =>  "(generator a (filter (= x xs) cond))"
        "(xy for x in xs for y in ys)"  =>  "(flatten xy (= x xs) (= y ys))"
        "(xy for x in xs for y in ys for z in zs)"  =>  "(flatten xy (= x xs) (= y ys) (= z zs))"
        "(x for a in as)"  =>  "(generator x (= a as))"
        # parse_vect
        "[x, y]"        =>  "(vect x y)"
        "[x, y]"        =>  "(vect x y)"
        "[x,y ; z]"     =>  "(vect x y (parameters z))"
        "[x=1, y=2]"    =>  "(vect (= x 1) (= y 2))"
        "[x=1, ; y=2]"  =>  "(vect (= x 1) (parameters (= y 2)))"
        # parse_paren
        ":(=)"  =>  "(quote =)"
        ":(::)"  =>  "(quote ::)"
        "(function f \n end)" => "(function f)"
        # braces
        "{x y}"      =>  "(bracescat (row x y))"
        ((v=v"1.7",), "{x ;;; y}") =>  "(bracescat (nrow-3 x y))"
        # Macro names can be keywords
        "@end x" => "(macrocall @end x)"
        # __dot__ macro
        "@. x y" => "(macrocall @__dot__ x y)"
        # cmd strings
        "``"         =>  "(macrocall :(Core.var\"@cmd\") \"\")"
        "`cmd`"      =>  "(macrocall :(Core.var\"@cmd\") \"cmd\")"
        "```cmd```"  =>  "(macrocall :(Core.var\"@cmd\") \"cmd\")"
        # literals
        "42"   => "42"
        # closing tokens
        ")"    => "(error)"
    ],
    JuliaSyntax.parse_atom => [
        # Actually parse_array
        # Normal matrix construction syntax
        "[x y ; z w]"  =>  "(vcat (row x y) (row z w))"
        "[x y ; z w ; a b]"  =>  "(vcat (row x y) (row z w) (row a b))"
        "[x ; y ; z]"  =>  "(vcat x y z)"
        "[x;]"  =>  "(vcat x)"
        "[x y]"  =>  "(hcat x y)"
        # Mismatched rows
        "[x y ; z]"  =>  "(vcat (row x y) z)"
        # Single elements in rows
        ((v=v"1.7",), "[x ; y ;; z ]")  =>  "(ncat-2 (nrow-1 x y) z)"
        ((v=v"1.7",), "[x  y ;;; z ]")  =>  "(ncat-3 (row x y) z)"
        # Higher dimensional ncat
        # Row major
        ((v=v"1.7",), "[x y ; z w ;;; a b ; c d]")  =>
            "(ncat-3 (nrow-1 (row x y) (row z w)) (nrow-1 (row a b) (row c d)))"
        # Column major
        ((v=v"1.7",), "[x ; y ;; z ; w ;;; a ; b ;; c ; d]")  =>
            "(ncat-3 (nrow-2 (nrow-1 x y) (nrow-1 z w)) (nrow-2 (nrow-1 a b) (nrow-1 c d)))"
        # Array separators
        # Newlines before semicolons are not significant
        "[a \n ;]"  =>  "(vcat a)"
        # Newlines after semicolons are not significant
        "[a ; \n]"  =>  "(vcat a)"
        "[a ; \n\n b]"  =>  "(vcat a b)"
        ((v=v"1.7",), "[a ;; \n b]")  =>  "(ncat-2 a b)"
        # In hcat with spaces as separators, `;;` is a line
        # continuation character
        ((v=v"1.7",), "[a b ;; \n c]")  =>  "(hcat a b c)"
        ((v=v"1.7",), "[a b \n ;; c]")  =>  "(ncat-2 (row a b (error-t)) c)"
        # Can't mix spaces and multiple ;'s
        ((v=v"1.7",), "[a b ;; c]")  =>  "(ncat-2 (row a b (error-t)) c)"
        # Treat a linebreak prior to a value as a semicolon (ie, separator for
        # the first dimension) if no previous semicolons observed
        "[a \n b]"  =>  "(vcat a b)"
        # Can't mix multiple ;'s and spaces
        ((v=v"1.7",), "[a ;; b c]")  =>  "(ncat-2 a (row b (error-t) c))"
        # Empty nd arrays
        ((v=v"1.8",), "[;]")   =>  "(ncat-1)"
        ((v=v"1.8",), "[;;]")  =>  "(ncat-2)"
        ((v=v"1.8",), "[\n  ;; \n ]")  =>  "(ncat-2)"
        ((v=v"1.7",), "[;;]")  =>  "(ncat-2 (error))"
        # parse_string
        "\"a \$(x + y) b\""  =>  "(string \"a \" (call-i x + y) \" b\")"
        "\"hi\$(\"ho\")\""   =>  "(string \"hi\" (string \"ho\"))"
        "\"hi\$(\"\"\"ho\"\"\")\""  =>  "(string \"hi\" (string-s \"ho\"))"
        "\"a \$foo b\""  =>  "(string \"a \" foo \" b\")"
        "\"\$var\""      =>  "(string var)"
        "\"\$outer\""    =>  "(string outer)"
        "\"\$in\""       =>  "(string in)"
        # Triple-quoted dedenting:
        "\"\"\"\nx\"\"\""   =>  "\"x\""
        "\"\"\"\n\nx\"\"\"" =>  raw"""(string-s "\n" "x")"""
        # Various newlines (\n \r \r\n) and whitespace (' ' \t)
        "\"\"\"\n x\n y\"\"\""  =>  raw"""(string-s "x\n" "y")"""
        "\"\"\"\r x\r y\"\"\""  =>  raw"""(string-s "x\n" "y")"""
        "\"\"\"\r\n x\r\n y\"\"\""  =>  raw"""(string-s "x\n" "y")"""
        # Spaces or tabs or mixtures acceptable
        "\"\"\"\n\tx\n\ty\"\"\""  =>  raw"""(string-s "x\n" "y")"""
        "\"\"\"\n \tx\n \ty\"\"\""  =>  raw"""(string-s "x\n" "y")"""
        # Mismatched tab vs space not deindented
        # Find minimum common prefix in mismatched whitespace
        "\"\"\"\n\tx\n y\"\"\""  =>  raw"""(string-s "\tx\n" " y")"""
        "\"\"\"\n x\n  y\"\"\""  =>  raw"""(string-s "x\n" " y")"""
        "\"\"\"\n  x\n y\"\"\""  =>  raw"""(string-s " x\n" "y")"""
        "\"\"\"\n \tx\n  y\"\"\""  =>  raw"""(string-s "\tx\n" " y")"""
        "\"\"\"\n  x\n \ty\"\"\""  =>  raw"""(string-s " x\n" "\ty")"""
        # Empty lines don't affect dedenting
        "\"\"\"\n x\n\n y\"\"\""  =>  raw"""(string-s "x\n" "\n" "y")"""
        # Non-empty first line doesn't participate in deindentation
        "\"\"\" x\n y\"\"\""  =>  raw"""(string-s " x\n" "y")"""
        # Dedenting and interpolations
        "\"\"\"\n  \$a\n  \$b\"\"\""  =>  raw"""(string-s a "\n" b)"""
        "\"\"\"\n  \$a \n  \$b\"\"\""  =>  raw"""(string-s a " \n" b)"""
        "\"\"\"\n  \$a\n  \$b\n\"\"\""  =>  raw"""(string-s "  " a "\n" "  " b "\n")"""
        # Empty chunks after dedent are removed
        "\"\"\"\n \n \"\"\""  =>  "\"\\n\""
        # Newline at end of string
        "\"\"\"\n x\n y\n\"\"\""  =>  raw"""(string-s " x\n" " y\n")"""
        # Empty strings, or empty after triple quoted processing
        "\"\""              =>  "\"\""
        "\"\"\"\n  \"\"\""  =>  "\"\""
        # Missing delimiter
        "\"str"  =>  "\"str\" (error-t)"
        # String interpolations
        "\"\$x\$y\$z\""  =>  "(string x y z)"
        "\"\$(x)\""  =>  "(string x)"
        "\"\$x\""  =>  "(string x)"
        # Strings with embedded whitespace trivia
        "\"a\\\nb\""     =>  raw"""(string "a" "b")"""
        "\"a\\\rb\""     =>  raw"""(string "a" "b")"""
        "\"a\\\r\nb\""   =>  raw"""(string "a" "b")"""
        "\"a\\\n \tb\""  =>  raw"""(string "a" "b")"""
        # Strings with only a single valid string chunk
        "\"str\""  =>  "\"str\""
    ],
    JuliaSyntax.parse_docstring => [
        """ "notdoc" ]        """ => "\"notdoc\""
        """ "notdoc" \n]      """ => "\"notdoc\""
        """ "notdoc" \n\n foo """ => "\"notdoc\""
        """ "doc" \n foo      """ => """(macrocall :(Core.var"@doc") "doc" foo)"""
        """ "doc" foo         """ => """(macrocall :(Core.var"@doc") "doc" foo)"""
        """ "doc \$x" foo     """ => """(macrocall :(Core.var"@doc") (string "doc " x) foo)"""
        # Allow docstrings with embedded trailing whitespace trivia
        "\"\"\"\n doc\n \"\"\" foo"  => """(macrocall :(Core.var"@doc") "doc\\n" foo)"""
    ],
]

# Known bugs / incompatibilities
broken_tests = [
    JuliaSyntax.parse_atom => [
        """var""\"x""\""""  =>  "x"
        # Operator-named macros without spaces
        "@!x"   => "(macrocall @! x)"
        "@..x"  => "(macrocall @.. x)"
        "@.x"   => "(macrocall @__dot__ x)"
        # Invalid numeric literals, not juxtaposition
        "0b12" => "(error \"0b12\")"
        "0xex" => "(error \"0xex\")"
        # Square brackets without space in macrocall
        "@S[a,b]"  => "(macrocall S (vect a b))"
        "@S[a b]"  => "(macrocall S (hcat a b))"
        "@S[a; b]" => "(macrocall S (vcat a b))"
        "@S[a; b ;; c; d]" => "(macrocall S (ncat-2 (nrow-1 a b) (nrow-1 c d)))"
        # Bad character literals
        "'\\xff'"  => "(error '\\xff')"
        "'\\x80'"  => "(error '\\x80')"
        "'ab'"     => "(error 'ab')"
    ]
    JuliaSyntax.parse_call => [
        # kw's in ref
        "x[i=y]" => "(ref x (kw i y))"
    ]
    JuliaSyntax.parse_juxtapose => [
        # Want: "numeric constant \"10.\" cannot be implicitly multiplied because it ends with \".\""
        "10.x" => "(error (call * 10.0 x))"
    ]
]

@testset "Inline test cases" begin
    @testset "$production" for (production, test_specs) in tests
        @testset "$(repr(input))" for (input,output) in test_specs
            if !(input isa AbstractString)
                opts,input = input
            else
                opts = NamedTuple()
            end
            @test test_parse(production, input; opts...) == output
        end
    end
    @testset "Broken $production" for (production, test_specs) in broken_tests
        @testset "$(repr(input))" for (input,output) in test_specs
            if !(input isa AbstractString)
                opts,input = input
            else
                opts = NamedTuple()
            end
            @test_broken test_parse(production, input; opts...) == output
        end
    end
end

@testset "Trivia attachment" begin
    @test show_green_tree("f(a;b)") == """
         1:6      │[toplevel]
         1:6      │  [call]
         1:1      │    Identifier           ✔   "f"
         2:2      │    (                        "("
         3:3      │    Identifier           ✔   "a"
         4:5      │    [parameters]
         4:4      │      ;                      ";"
         5:5      │      Identifier         ✔   "b"
         6:6      │    )                        ")"
    """
end

@testset "Unicode normalization in tree conversion" begin
    # ɛµ normalizes to εμ
    @test test_parse(JuliaSyntax.parse_eq, "\u025B\u00B5()") == "(call \u03B5\u03BC)"
    @test test_parse(JuliaSyntax.parse_eq, "@\u025B\u00B5") == "(macrocall @\u03B5\u03BC)"
    @test test_parse(JuliaSyntax.parse_eq, "\u025B\u00B5\"\"") == "(macrocall @\u03B5\u03BC_str \"\")"
    @test test_parse(JuliaSyntax.parse_eq, "\u025B\u00B5``") == "(macrocall @\u03B5\u03BC_cmd \"\")"
    # · and · normalize to ⋅
    @test test_parse(JuliaSyntax.parse_eq, "a \u00B7 b") == "(call-i a \u22C5 b)"
    @test test_parse(JuliaSyntax.parse_eq, "a \u0387 b") == "(call-i a \u22C5 b)"
    # − normalizes to -
    @test test_parse(JuliaSyntax.parse_expr, "a \u2212 b")  == "(call-i a - b)"
    @test test_parse(JuliaSyntax.parse_eq, "a \u2212= b") == "(-= a b)"
    @test test_parse(JuliaSyntax.parse_eq, "a .\u2212= b") == "(.-= a b)"
end

