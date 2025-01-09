To-Do / roadmap / proposals
===========================
(*roughly* in order of importance / new-ness)

### Require expressions spanning multiple lines to be enclosed in brackets (like Kotlin)
- Before:

      a = 10
- After:
  
      a = (10
          + 20)
- Alternatively, only allow single newline within expression
  - Before:
    
        a = 10
        
            + 20
  - After:
    
        a = 10
            + 20
  - Need to work out how (line) comments interact with this. Probably easiest
    to still count an empty line with line comment as two newlines.

### First-class operators
- Expression `+` is just a function `(l, r) => l + r`
- Probably will need to enclose in parentheses most of the time, to prevent it
  being parsed as an operator application.

### Auto-vectorized operators
- `(1, 2) + (4, 8) == (5, 10)`
- `a, b = (1, 2) + (4, 8)` === `a, b = 1 + 4, 2 + 8`
- `a, b += 4, 8` === `a, b = a + 4, b + 8` === `a, b = (a, b) + (4, 8)`

### Auto-define operators on functions
Example with unary operator:

    even x => x % 2 == 0
    odd = !even   -- odd x => !even(x)
    print(odd(7)) --> true
    
    -- Filtering only odd values:
    stream.filter(x => !even(x))
    stream.filter(!even)

Example with binary operator:

    double x => x * 2
    succ x => x + 1
    f = double - succ -- f x => double x - succ x
    print(f 10)       --> 9

### Function shorthand for "methods"
- `(.f) == (x => x.f)`, `(.f)(x) == x.f()`

Example:
    
    (.isEven)(7) == 7.isEven()
    
    stream.filter(x => x.isEven())
    stream.filter(.isEven)

Combined with auto-defined operators for functions:

    stream.filter(x => !x.isEven())
    stream.filter(!.isEven)

How to work with binary functions, without partial application?
- `stream.map(x => x + 10)`
- `stream.map(.+ 10)` would not work (as that would be `stream.map(10.+())`)

### Allow keywords and operators as keys
- Operators for indexing: `a.+`, `a.++`, `a.//` (equivalent to `a."//"`)
- Operators for defining: `{ // (l, r) => ... }` (equivalent to
  `{ "//" = (l, r) => ... }`)
- Keywords for indexing: `a.if`, `a.var`, `a.return` (equivalent to `a."return"`)
- Keywords for defining: `{ if = ... }` (equivalent to `{ "if" = ... }`)
  - Probably not, this may be hard to parse for computer and human.
    - `{ const var = 10 }`? (constant called `var`)
    - `{ var x => ... }`??? (function called `var` taking parameter `x`)

### Implementation problems with variable sized groups
- Sources: groups, return (-> function calls), yield/break
- Destinations: function arguments, assignments, list contents

### Sequence to Stream operator
- prefix `!`, like Icon?
- prefix `$`, as a sort of `S`?

### Function binding syntax (UFCS operator)
- Ability to (re-)define receiver for bound methods
- `a.b::c.d` creates function `c.d` with `a.b` as receiver (`this`)
  - Call like `a.b::c.d(...)`
- Useful for "extending" standard libraries
  - Example: suppose I want to add a `map` function to objects: `obj::ObjExtensions.map(x => x + 1)` or `obj::map(x => x + 1)` instead of `ObjExtensions.map(obj, x => x + 1)`
- https://github.com/tc39/proposal-bind-operator

### Set `this` on all functions
- "global" functions and functions in current scope get current block as `this`
- or, they get the function itself as `this`
- or, the current `this` is propagated

### Separator for if/for/while condition and body
- Words (Lua):     `if condition then body`,  `for var in val do body`,  `for var in val do { body }`
  - cons: long/wordy, 2 extra keywords, different keywords for `if` and `for`/`while`
- Colon (Python):  `if condition: body`,      `for var in val: body`,    `for var in val: { body }`
  - cons: looks like python so makes you forget `{}`, `:` and `{}` looks superfluous
- Comma (Jammy):   `if condition, body`,      `for var in val, body`,    `for var in val, { body }`
  - cons: confusing in lists, `,` and `{}` looks superfluous
- Parentheses (C): `if (condition) body`,     `for (var in val) body`,   `for (var in val) { body }`
  - cons: not spaceous / many punctuation chars, parentheses suddenly part of syntax

### Variable definition in `if`
- Also for `while`? Not for `for`
- Definition only valid in scope of if-branch
  
      if var x = fn(): {
          print x
      } else {
          print "something else"
      }

### Constants
- Function assignment shorthand (as opposed to definition)
  - Now, `a.f() => 42` is no longer valid, only `a.f := () => 42`
- Maybe allow same-level shadowing?
  - could be hard to implement or confusing to use
- Warning on unused variables, to prevent errors when accidentally shadowing
  instead of mutating (i.e. using `=` instead of `:=`)
  
      var x = 0
      if x > 10: { x = 42 }
      -- x is still 0
- Values should also be const by default? Otherwise this is weird:
  
      obj = { x = 10 }
      obj.y = 20 -- possible
      obj.x = 30 -- not possible, x is const
- Shorthand notation for mutable blocks: (`a` and `b` are `var` here)
  
      obj = var {
          a = 10
          b = 20
      }

### Immutable values
- Value that cannot change, as opposed to variable that cannot be reassigned
- Immutable value means that every containing field is immutable
  and that no new fields can be added
  - override `_Set` method to prevent adding fields
- Potential problem with native (C-side) code: should be impossible to change
  value/pointer via C
- Primitives like Bool, Int, Float, String are immutable by default
- Options for constant variable `a` holding immutable value `{}`:
  - add `readonly` (C#) / `sealed` (C#) / `immutable` / `immut` modifier:  
    `const immutable a = {}`  or  `const readonly a = {}`
  - allow using `const` for values: (confusing)  
    `const a = const {}`
  - extend `const` to also apply to values: (confusing for JS/Java users)  
    `const a = {}`
  - use `freeze` function: (like JS)  
    `const a = freeze {}`
- Enforce for thread-safety: can only share immutable values
- No reassignment by default? -> only use `const` for immutability
  and `mut`/`var` for reassignable
- Probably: (like JS) no syntax for immutable values, maybe freeze function.
  Immutability checking (for threads) needs to be a function as well

### (Value) equality/equivalence vs (reference) identity
- `==` / `!=` for equality, `===` / `!==` for identity
  - pro: `===` looks like `==`
  - like Kotlin, JS also has these operators (with different semantics though)
- `==` / `!=` for equality, `eq` / `neq` for identity
  - pro: clearer distinction between overloadable/non-overloadable operators
    (all keyword operators are non-overloadable)
  - for negated identity: `neq`, `ne` or `!eq` (Kotlin style)?
- `.eq` / `.neq` function for equality, `==` / `!=` for identity
  - pro: simple, just a function call (no syntax needed!)
  - con: `==` should be overloadable (it is a 2-character operator)

### Function to return string representation of code: inspect, ?
- `print "hello"`            --> hello
- `print("hello".inspect())` --> "hello"

### Default parameters
- What to do when caller explicitly passes nil?
  - python will use nil/None, not default value
  - having separate nil and nothing can help

### Named parameters by `(<arg> = <exp>)`
- Following C# valid-ness, valid when one of:
  - First all positional parameters, then all named parameters
  - Named parameters in correct place?
- problem: group is not a data structure
  - possible solution: make group (ephemeral) data structure (introduce "tuples")

### Disallow assignment to `nil`?
- Making it `const` does not fix: shadowing
- Linter cannot catch everything: `a = nil; (a) = 42` will assign to nil
- Also `true` and `false`?

### Error handling
- try as method on functions: `fn.try(args)` like Lua's pcall
- http://joeduffyblog.com/2016/02/07/the-error-model/
- http://lua-users.org/wiki/FinalizedExceptions
- Errors like Lua for bugs / unrecoverable programmer errors
- Return values for recoverable errors
  - On success: `return nil, value, ...`
  - On failure: `return Error("description")`
  - `err, val1, val2 = fn()`
- Error value is falsy, possible idiom using `else` or `or`
  - `print(fn() else "failure")`
  - `x = fn() else "default value"`

### Pattern matching
- match function, function parameter overloading, match operator `~~`?
- match against values, number of values, lists, blocks, types, (destructuring), ...
  - default implementation of match operator `~~` is equality, `within` for ranges, ...
- problem: now need to execute match operator functions to decide which function to call
  - solution: no match operator, so not overloadable
- problem: `true` and `false` are variables, so `(true) -> ...` always matches
- value:                `42 -> ...`
- variable:             `x -> ...`
- multiple variables:   `(x, y) -> ...`
- all variables:        `(...x) -> ...`
- var with rest:        `(x, ...y, z) -> ...`
- variable as value:    `\(x) -> ...`
- lists:                `[x, y] -> ...`
- blocks:               `{ x, y } -> ...`
- blocks with values    `{ x = 10 } -> ...`
- blocks with renaming? `{ x = a } -> ...` (don't know if this or swapped: `a = x`)
- types?                `(x: String) -> ...`
- composite structures: `[{x1, y1}, {x2, y2}] -> ...`,  `[10, x] -> ...`,  `[\(x)] -> ...`

### Coroutines
Specify yielding coroutine or yield location? To allow using coroutine yielding
for both async stuff and more local stream stuff.
- Option 1: specify coroutine to yield from
  - code running that coroutine will resume
- Option 2: specify coroutine to yield to
  - that coroutine will resume
- Different from symmetric coroutines because stack stays intact? Yield point
  needs to be on the call stack.
- Similar to Wren's `Fiber.transfer` function: https://wren.io/concurrency.html#transferring-control
  - different because Wren allows transfer between any coroutine

Example using Lua coroutine function names:

    -- "Scheduler" code
    main = Coroutine.running()
    
    -- User code
    co = Coroutine(() => {
        generator = Coroutine(() => {
          yield(10) --> yields to for loop
          -- Option 1 equivalent:
          Coroutine.running().yield(10)
          -- Other option 1 equivalent:
          generator.yield(10)
          -- Option 2 equivalent:
          co.yield(10)
          
          -- Yields to main coroutine, "through" for loop coroutine
          co.yield("sleep")   -- option 1
          main.yield("sleep") -- option 2
          
          yield(20) --> yields to for loop
        })
        -- for loop resumes coroutine for each element
        for x in generator: print x
    })
    
    -- "Scheduler" code
    val = co.resume() --> prints 10
    -- val == "sleep"
    co.resume() --> prints 20

### Allow single vararg anywhere in function signature
- Important to allow only *one* vararg
- Like ipv6 shorthand notation :)
- only:     `f(...rest) => ()`
- at end:   `f(a, ...rest) => ()`
- at start: `f(...rest, a) => ()`
- between:  `f(a, ...rest, b) => ()`

### Naming convention
- `camelCase` (Lua, Java, Kotlin): requires typing shift  
  `defineProtoNativeFn()`
- `lowercase` (Lua): requires no extra typing, but can become harder to read  
  `defineprotonativefn()`
- `snake_case` (Rust, C, Python): requires typing both shift and `-`  
  `define_proto_native_fn()`
- `kebab-case` (Lisp): only requires typing `-`, require spaces around infix operators, vscode does not recognise as single word  
  `define-proto-native-fn()`

### Monads/functors and haskell-like do-notation / gleam-like use?
- https://discord.com/channels/530598289813536771/530604512017121290/954101398243520644
- https://github.com/airstruck/knife/blob/master/readme/chain.md
- https://gleam.run/news/v0.25-introducing-use-expressions/
- https://yuescript.org/doc/#backcalls
- https://idris2.readthedocs.io/en/latest/tutorial/interfaces.html#notation
- Functor: `(Promise<A>, A -> B)          -> Promise<B>`
- Monad:   `(Promise<A>, A -> Promise<B>) -> Promise<B>`
- For things like Javascript's Promise (which is not always a monad) or Maybe
  With the example from MDN:
  
      fetch("https://github.com")
          .then(response => response.json())
          .then(data => print(data))
  With pipe operator:
  
      fetch("https://github.com")
          |> response => response.json()
          |> data => print(data)
  With pipe operator and holes:
  
      fetch("https://github.com")
          |> _.json()
          |> print(_)
  In callback style:
  
      fetch("https://github.com", response => {
          response.json(data => {
              print(data)
          })
      })
  With do-notation:
  
      response <- fetch("https://github.com")
      data <- response.json()
      print(data)
  With use-notation:
  
      use response <- fetch("https://github.com")
      data = response.json()
      print(data)
  
  Pro of use-notation: can be used without value (example from Gleam website)
  
      use <- defer(() => print "Goodbye")
      print "Hello"

### Problems with using Block/Object as a map
1. indexing will yield value from prototype if not present in map
2. setting certain keys overrides functionality
- solution 1: don't search prototype for indexing by expression
  - `a = {}`, `a.x` will still search prototype, `a."x"` will not
  - con: inconsistent, possibly confusing, does not solve problem 2
- solution 2: add Map data structure
  - `a = Map()`, `a.set("x", 42)`, `a.get "x"`
  - con: more verbose / non-native syntax (requires function calls)
- solution 3: make Block/Object have Map methods
  - `a = {}`, `a.get "x"`
  - con: same as solution 2, does not solve problem 2
- solution 4 (radical!): Use symbols for operator overrides instead of strings
  - operators use symbols `a.(Symbol "+")` for addition override
  - con: only partly solves problem 1 (by default, proto is Block/Object, and
    no string keys there then)
- solution 5: combine 4 and 2
  - `a = Map()`, `a.x = 42`, `a.x`
  - Map with getter/setter override, only searches prototype for symbol keys
  - con: does not solve problem 1 when used for storing symbol keys,
    need to use methods again then
- solution 6: Use symbols for everything instead of strings (also variables)
  - `a = {}`, `a."x" = 42`, `a."x"`
  - more radical version of solution 4
    - symbol indexing: `a.x`
    - string indexing: `a."x"`
  - more standard OOP-like separation of code and data

### `with` statement?
Turn `a.x(); a.y(); a.z()`  into  `with a: { x(); y(); z() }`

### Spread syntax/operator for normal objects/blocks  

    a = { x = 10 }
    b = { ...a; y = 20 }
    
    b == { x = 10; y = 20 }

### Symbols
- can be used for value-less things: enum elements, sentinels, ...  
  `Colours = { RED = :red; GREEN = :green; BLUE = :blue }`,  `Colours.RED == :red`  
  or  
  `Colours = Enum(:red, :green, :blue)`,  `Colours.RED == :red`  
  instead of  
  `Colours = { RED = 1; GREEN = 2; BLUE = 3 }`,  `Colours.RED == 1`
- syntax: `:symbol` seems common: `a.:+`, `a.:x`
- make standard indexing use symbols instead of strings: `a.x` indexes `a`
  with symbol `x`
- should symbols be global by name?
  - Unique: Javascript
  - Global: Ruby, Scala?, Dart
  - what makes global-by-name symbols different from strings?
    essentially creates a separate string domain

### Semi-tuples?
- Don't like *tuples*; what do you need them for?, less generic because
  hard-coded data structure
- Potentially more resource-heavy / wasteful?
- Evaluating semi-tuple still results in content (otherwise can't do `(1+2)*3`)
  - Therefore, these are not normal tuples
  - Cannot compose: `((a, b), (c, d))`  is  `(a, b, c, d)`  is  `a, b, c, d`
- Supports named fields: `(x = 10, y = 20)`  
  `y, x from (x = 10, y = 20)`  
  `return (x = 10, y = 20)`  
  `fn (x = 10, y = 20)`
- Problem: when using this for named return values, named fields should still
  "unpack" like normal values, order of named fields needs to be preserved  
  `fn() => { x, y = 10, 20; return x, y }; a, b = fn()`  
  `a, b = (x = 10, y = 20)`  should be equal to  `a, b = (10, 20)`

### Multiple values for nothing-ness: nil, null, unit, void, nothing, none?
- Usage: empty indices in lists while iterating (atm iteration stops at nil)
  - otherwise, iteration could skip empty (not present!) indices,
    use iteration with range to not-skip
- Usage: removing variables from objects (setting to nil does not remove atm)
  - otherwise, remove when set to nil
- One *value* instance of singleton class
  - set to this value: variable has this value
  - behaves just like value, is kept in lists  
    `[10, nil, 20].length == 3`,  `for x in () => { yield 10; yield nil; yield 20 }` loops 3 times
- One *keyword* with no corresponding value
  - set to this keyword: remove reference
  - behave like nothing was present, removed in lists, stops iteration  
    `[10, nil, 20] == [10, 20]`,  `for x in () => { yield 10; yield nil; yield 20 }` loops once
- Attempting to use keyword kind as value yields value kind? (keyword kind == value kind is true)
  - Otherwise, using `==` on keyword kind results in error as `a == b` gets
    transformed into `a."=="(b)` and keyword kind does not have `==` field
- How to check if a variable is nil or nothing? Is it really necessary?
  - Using reference identity, `nothing eq nil` is `false`

### Imperative function (only side effects, returns nothing):
- with explicit return: `() => { ...; return }`
- with `do` function: `() => do { ... }`  
  `do(_) => nil`

### Array programming
- Arithmetic operators for lists are defined as a map on that list: `a + b == a.map((x,y) => x + y)`
- Need other operator for concatenation: `++` like haskell,
  `..` like lua is already taken by the range operator

### Getter functions (without parameter list), `=> body`
- Ambiguous, what is `x => body`?
  - anonymous function with single parameter
  - getter function named `x`

### Parallelism: optional locking of Blocks?
- maybe as a macro that marks the block as parallel-accessible?
- only allowed to access parallel-accessible Blocks of other threads, will auto-lock
- problem: needs "ownership": of which thread is the Block
- maybe better to have one type of container for parallel access
- automatically make block parallel-accessible somehow

### Stream-based programming / Flow-Based Programming (FBP)
- Lazy streams: important! so pull, not push
- With operator `||>` or maybe replace operator `|>`
- Using coroutines, yielding and iterators  
  
      evenInts = []
      i = 0
      for x in generateIntegers: {
          i = i+1
          if i >= 10: break
          if x % 2 == 0: evenInts.push(x)
      }
  can then be rewritten to
  
      evenInts = generateIntegers ||> filter(x => x % 2 == 0) ||> limit(10)
          ||> reduce((a, x) => a.push(x), [])
- other example: `first10words = stdin ||> groupByWords ||> limit(10) ||> []`
- Operators to create / extend streams (= coroutines?):
  - Like Icon (co-expressions), which has `"a" | "an" | "the"`
  - Stream concatenation (+ appending?): `s ++ "the"` (for `s` a stream)

### Indexing and setting to index as methods _Get and _Set?

### Blocks as ordered associative arrays?
- keys are sorted by their addition time
- what happens when deleting (setting to nil) and re-inserting a key?

### Properties in objects for memory optimisation
- Stored at prototype-defined memory indices instead of in hash-table
- https://v8.dev/blog/fast-properties
- Like Python's slots (explicit) or automatically-defined (implicit)

### Shorthand field names
- `{a, b}`  is  `{a = a; b = b}`
- https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Object_initializer#property_definitions
- Use comma or semicolon? Probably semicolon
- Clashes with expression-as-statement
  - Solution: only allow for identifiers as other types are not really interesting anyway
- `{ :a; :b }`,  `{ const :a, :b }`,  `{ var :a, :b }`
  - con: can no longer use `:` for symbols
  - con: may not be clear that this defines `a` and `b`
- `{ =a; =b }`,  `{ const =a, =b }`,  `{ var =a, =b }`

### Statements as expressions?
- New style: `var a = if x > 10: "greater" elseif x == 10: "equal" else: "smaller"`
- In Lua style: `var a = x > 10 and "greater" or (x == 10 and "equal" or "smaller")`
- `break` with value, could also allow for multi-level break? i.e. `break break`  
  `value = for x in [1,2,3,4,5]: if x % 2 && x % 3: break x`
- https://news.ycombinator.com/item?id=8827843
- https://news.ycombinator.com/item?id=8828230
- Maybe make assignment an expression
  - Pro: terse `a = b = c` (needs to be right-associative for this: `a = (b = c)`)
  - Con: cryptic "code-golf" things
  - Con: possible mistakes like `while x = 1`

### Types
- structural
- operations on types? for more safe typing (algebraic data type like?)
  - or, and, not
- constraints on values, for even more safe typing
  - natural numbers, hex numbers, numbers 0..1, ascii values A..Z
  - https://github.com/Microsoft/TypeScript/issues/15480
  - maybe better to keep this to documentation or assert
- Structural typing is problem for native types
  - Int should be subtype of Float (any int is also a float)
  - Float should not be sybtype of Int, but structure might not differentiate
    - solution: probably methods will differentiate
  - Solution: only use structural subtyping for non-native / non-external types?
- Generic types
- Types == values, using standard operators `|`, `->`
  - Problem: needs multiple-value operators for `(Int, Int) -> Int`

### Mixins or traits (deriving?) 
- Difference:
  - traits can define preconditions (methods that need to be present)
  - mixins make linear chain (a -> B -> C), traits are flattened (A -> (B, C))
- Automatic? i.e. can use `!=`, `>` automatically on class defining only `==` and `<=`
- https://blog.10pines.com/2014/10/14/mixins-or-traits/
- https://stackoverflow.com/a/23124968

### Annotations with `@annotation`, `@annotation()` or `@annotation = value`
- Used for:
  - adding metadata like documentation, deprecation (removed at compile-time,
    used by Java, Wren and Rust annotations/attributes)
  - adding functionality to a value like sealing, adding methods
    (used by Typescript and Python decorators)
- Java's annotations: https://docs.oracle.com/javase/tutorial/java/annotations/basics.html
- Wren's attributes: https://wren.io/classes.html#attributes
- Rust's attributes: https://doc.rust-lang.org/reference/attributes.html
- Typescript's decorators: https://www.typescriptlang.org/docs/handbook/decorators.html
- Python's decorators: https://peps.python.org/pep-0318/

### Enums
- Boolean should be an enum with 2 values? true and false are the only 2 instances of Bool
- Maybe like Java?
- Enum instance (true, false, colours) is const instance with no values,
  enum "class" itself should be const as well (but do not enforce)

### Emoji comments
- `🙂 comment 🙃`
- `👉 comment 👈`
- `❗ comment`
