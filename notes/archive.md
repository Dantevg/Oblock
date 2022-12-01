These notes came from `syntax-semantics.md`, but they are no longer applicable
because I scrapped the idea or implemented it.

- Named return values, symmetric to named arguments using `from`
  - Probably not. Doubt usefulness, only for few special cases
- Unary '+' for absolute value (as suggested in the /r/ProgrammingLanguages Discord)
  - No, use `.abs()` instead
- Destructuring / import with `from`
  - maybe renaming with `as`?
  - `*` to include all
  - Two use-cases:
    - modules: `* from require "mymodule"` will import everything from "mymodule"
    - traits: `{ * from MyTrait }`
      - does not really work for traits (e.g. checking for trait preconditions)
  - `a = { x = 10; y = 20 }`  
    `b = { z = 30 }`  
    `c = { x, z as y from a, b; w = 40 }`  
    c is `{x=10, y=30, w=40}`
- Function arguments as sequence instead of repeated application?
  - `a b c` is now `a(b(c))`, then `a(b,c)`
  - As replacement for partial application in functional languages
  - Real repeated application can then be done as `(a b) c`,
    possibly with `$` operator like in Haskell? `a b $ c`
  - con: multiple ways of doing the same thing: (imperative style and functional style)
    - definition: `add a b => a + b`  and  `add(a, b) => a + b`
    - call: `add 10 20`  and  `add(10, 20)`
- Comment syntax:
  - C-like: `//` and `/* */`
  - Lua-like: `--` and `--[[ ]]` works well in combination with long/raw strings
  - Custom: `--` and `(: :)` less internally consistent, but happy faces!
  - Might not be needed: strings as statements as comments (but does not work
    within expressions: lists)
- Modifiers as single characters?
  - private `-x := 42`
  - public `+x := 42`
  - var and const? static and proto/instance?
  - Problem: clash with operators  
    `print a`  
    `+x := 10`  
    is `print(a+x) := 10`
- Passing single block as parameter
  - "Immediately-invoked function"
  - Allows positional arguments and named arguments
  - Automatically "destructured" to function call
  - Problem: what to do when you want to pass a single block parameter? (syntax)
  - Solution: maybe use list/array syntax (which may use `()` already, how convenient!)
  - Problem again: list syntax is syntax sugar for block extending List, still same problem
- Nullary operator. Doubt usefulness, only for few special cases
  - ??? like in scala (is it an operator or expression?)
- Macros, for "precompiler" / "compile-time" expansion
  - combine with annotations, using `@`?
    - TypeScript's and Python's annotations seem nice, though not "compile-time"
  - *do it well or don't do it*
  - hygienic, AST based, somehow definable in code without meta-language
    - need some way to jump from logic in macro defining to generated code
      - metalua has `+{}` and `-{}`, maybe use `@+{}` and `@-{}`?
    - problem: need to interpret code before compilation?
  - compile-time constants: `@macro(a, 20); print(@a + 10)`  to  `print(20 + 10)`
    - this can also be done automagically, maybe behind flag (side-effects)
  - string interpolation: `a = @str("hello, {name}!")`  to  `a = "hello, "+name+"!"`
  - number formats: `a = @octal(777)`  to  `a = 511`
  - data structures: `a = @enum(RED, GREEN, BLUE)`  to  `a = { RED = 1; GREEN = 2; BLUE = 3 }`
  - code repetition: `@macro(returnOnNil, (expr) => @+{ var x, err = @-{expr}; if x: yield x else return err })`  
    `a = @returnOnNil(fn())` to `a = { var x, err = fn(); if x: yield x else return err }`
- Lists using block syntax again?
  - block saves expressions separated by comma or newline until semicolon or expression
  - in the following examples, results of fn1 and fn2 are stored, of fn3 and fn4 not
  - function calls as expression statements: (not stored in list)  
    `{; fn3(); fn4() }`
  - function calls as expressions: (stored in list)  
    `{ fn1(), fn2() }`
  - both expressions and statements, separated by semicolon:  
    `{ fn1(), fn2(); fn3(); fn4() }`
  - both, separated by statement present:
    
    	{
    		fn1()
    		fn2()
    		x := 10
    		fn3()
    	}
  - not stored again:
    
    	{;
    		fn3()
    		fn4()
    	}
- Type cast operator? to let nil/null and false both evaluate falsy
  - No type casting, but instead `.toInt`, `.toBoolean` methods or use `Int()`, `Bool()` constructors
  - Type casting with different syntax: `<>` maybe?
    - Problem: clashes with comparison operators (see below)
  - Type casting with 'as' keyword: `5.2 as Int`
  - Problem: should not be able to make custom types falsy.
- Pure functions as optimisation?
- allow custom wrap operators? like `<>` would be nice, or `||`
  - disallow defining of predefined wrap operators as unary or binary operators!
  - problem: interfering with allowing single-param function call without parentheses:  
      `a | b | c`  
      as 2x binary operator: `(a | b) | c`  
      as wrap operator and function call: `a |b| c  (which is  a(|b|)(c) or a(|b|(c)))`
    - possible (bad) solution: require no space present inside "brackets"
      - problem for strings: " airy string "
    - other solution: disallow function call without brackets (but I want to have this!)
    - better solution: set wrap operator precedence(?) such that this is not a problem (really low?)
      - con: you will often need to use brackets around every wrap operator: `a (|b|) c`
  - maybe best to disallow custom wrap operators but have a few default unassigned
  - problem: does the wrap operator apply on only the content or also the expression before?
    - `a[b]` should call `[]` from a with b as argument: `a.[](b)`
      - definition of `[]` method should be defined in class of a
    - `a [b]` should call `[]` with b as argument and pass that as argument to a: `a([](b))`
      - definition of `[]` method should be defined in its own operator class
        (see operators as first-class citizens ^)
- Keyword for binary actual data layout in const classes like Int (8 bytes for long long)?
  - Maybe define class instance size in bytes for const classes: sizeof(struct MyClass) in C?
    - should you need to define size for foreign/external classes *within* the language?
      maybe makes creating classes too much work: when changing internal size, need to recalculate "by hand"
