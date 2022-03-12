
--------------------------------------------------------------------------------
#                                    Syntax                                    #
--------------------------------------------------------------------------------
https://wren.io/classes.html
https://luau-lang.org/

To-Do / roadmap / proposals
---------------------------
(*roughly* in order of importance)
- How to recognise an object as an instance of a class?
  - Simple: look in prototype chain
  - Advanced / more flexible: structural typing
- Immutable values
  - Value that cannot change, as opposed to variable that cannot be reassigned
  - Immutable value means that every containing field is immutable
    and that no new fields can be added
    - requires allowing changing modifiers (only var -> const, not the other way!)
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
- Syntax sugar for classes and constructors
- Use comma instead of colon for if/for/while condition/body separator (like Jammy)
- Default parameters
  - What to do when caller explicitly passes nil?
    python will use nil/None, not default value
- Named parameters by `(<arg> = <exp>)`
  - Following C# valid-ness, valid when one of:
    - First all positional parameters, then all named parameters
    - Named parameters in correct place?
  - problem: group is not a data structure
    - possible solution: make group (ephemeral) data structure (introduce "tuples")
- Named return values, symmetric to named arguments using `from`
  - Probably not. Doubt usefulness, only for few special cases
- Error handling
  - try as method on functions: `fn.try(args)` like Lua's pcall
  - http://joeduffyblog.com/2016/02/07/the-error-model/
- Pattern matching
  - match function, function parameter overloading, match operator `~~`?
  - match against values, number of values, lists, blocks, types, (destructuring), ...
    - default implementation of match operator `~~` is equality, `within` for ranges, ...
  - problem: now need to execute match operator functions to decide which function to call
- Coroutines
- Problems with using Block/Object as a map
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
- Symbols
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
- Semi-tuples?
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
- Multiple values for nothing-ness: nil, null, unit, void, nothing, none?
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
  - Attempting to use keyword kind as value yields value kind (keyword kind == value kind is true)
- Unary '+' for absolute value (as suggested in the /r/ProgrammingLanguages Discord)
- Imperative function (only side effects, returns nothing):
  - with explicit return: `() => { ...; return }`
  - with `do` function: `() => do { ... }`  
    `do(_) => nil`
- Array programming
  - Arithmetic operators for lists are defined as a map on that list: `a + b == a.map((x,y) => x + y)`
  - Need other operator for concatenation: `++` like haskell,
    `..` like lua is already taken by the range operator
- Getter functions (without parameter list), `=> body`
  - Ambiguous, what is `x => body`?
    - anonymous function with single parameter
    - getter function named `x`
- Parallelism: optional locking of Blocks?
  - maybe as a macro that marks the block as parallel-accessible?
  - only allowed to access parallel-accessible Blocks of other threads, will auto-lock
  - problem: needs "ownership": of which thread is the Block
  - maybe better to have one type of container for parallel access
- Stream-based programming / Flow-Based Programming (FBP)
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
- Indexing and setting to index as methods _Get and _Set?
- Blocks as ordered associative arrays?
  - keys are sorted by their addition time
  - what happens when deleting (setting to nil) and re-inserting a key?
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
- Compound assignment operators
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
  - Might not be needed: strings as statements as comments (but does not work within expressions: lists)
- Modifiers as single characters?
  - private `-x := 42`
  - public `+x := 42`
  - var and const? static and proto/instance?
  - Problem: clash with operators  
    `print a`  
    `+x := 10`  
    is `print(a+x) := 10`
- Shorthand field names
  - `{a, b}`  is  `{a = a; b = b}`
  - https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Object_initializer#property_definitions
  - Use comma or semicolon? Probably semicolon
  - Clashes with expression-as-statement
    - Solution: only allow for identifiers as other types are not really interesting anyway
- Passing single block as parameter
  - "Immediately-invoked function"
  - Allows positional arguments and named arguments
  - Automatically "destructured" to function call
  - Problem: what to do when you want to pass a single block parameter? (syntax)
  - Solution: maybe use list/array syntax (which may use `()` already, how convenient!)
  - Problem again: list syntax is syntax sugar for block extending List, still same problem
- Nullary operator. Doubt usefulness, only for few special cases
  - ??? like in scala (is it an operator or expression?)
- Statements as expressions?
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
- Types
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
- Mixins or traits (deriving?) (what's the difference exactly? traits seem more powerful?)
  - Automatic? i.e. can use `!=`, `>` automatically on class defining only `==` and `<=`
  - https://blog.10pines.com/2014/10/14/mixins-or-traits/
  - https://stackoverflow.com/a/23124968
- Macros, for "precompiler" / "compile-time" expansion
  - combine with annotations, using `@`?
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
- Keyword for binary actual data layout in const classes like Int (8 bytes for long long)?
  - Maybe define class instance size in bytes for const classes: sizeof(struct MyClass) in C?
    - should you need to define size for foreign/external classes *within* the language?
      maybe makes creating classes too much work: when changing internal size, need to recalculate "by hand"
- Pointers / references
- Enums
  - Boolean should be an enum with 2 values? true and false are the only 2 instances of Bool
  - Maybe like Java?
  - Enum instance (true, false, colours) is const instance with no values,
    enum "class" itself should be const as well (but do not enforce)
- Generic types? maybe later, if needed
- Ternary operator? Don't think, I like lua's and-or method
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

Operators and keywords
----------------------
- precedence
- associativity
- operators and keywords as first-class citizens? Would allow using all things as keys (and values)
  - as keys for defining operator methods
  - as values for storing and passing to functions
  - problem: how to use operators from parameters?
    - use any value as operator like haskell? not nice for readability
  - operators as classes? define operator instance methods inside operator's class
    instead of inside type's class:
    - `+ = { ()(a: Num, b: Num) => a + b }` (would need to define this method on Num class load)
    - `Num = { +(b) => this + b }`
- keywords: return, yield (maybe later, together with coroutines/continuations), break, throw?
  - External / foreign? for function definitions that get populated later on by C or as interfaces
- true, false and nil/null are not keywords, but instances of Bool and Nil/Null classes
- unary operators: `-`, `!` and other custom ones
  - postfix unary operators? like `a!` for factorial and `1..` for range from 1 to infinity
    - function application without parameters with `!` like MoonScript
- binary operators: `-`, `+` and other custom ones
- wrap operators: `{}`, `()`, `[]`, `""` (n-ary operators)
  - `()` serves multiple purposes, but in different contexts this should be ok:
    - expression: grouping
    - function call: argument list
    - function definition: parameter list
- index operators: `.` and `[]`
  - `a.b` is syntax sugar for `a["b"]`
    - this means that `.` is not an operator, but fixed in the syntax (meh, but necessary)
  - when used in an expression, they are binary operators, called on the left
    operand with the right (or enclosed) operand as argument
  - when used in a variable definition, they are ternary operators, called
    just like in an expression context, but also with the value as second argument

Statements and expressions
--------------------------
Blocks, classes and function bodies are all the same
In general, newlines are ignored and seen as whitespace (like Lua).

The following:

	a
	-b
	.c()

gets parsed as expression:

	a - b .c()
	which is
	a - (b.c())

But this:

	a
	-b
	c()

gets parsed as expression followed by statement:

	a - b c()
	which is
	a - b
	c()

This means ?

List / array syntax using `...()` or `[]` as syntax sugar. These are all equal:

	[10, 20, a = b, 30]
	[
		10
		20
		a = b
		30
	]
	extend List {
		(1) = 10
		(2) = 20
		a = b
		(3) = 30
	}

Inheritance:
- `Point = Vector { }` (call static superclass)
- `Point = extend Vector { }` (with `extend` keyword/function)
- `Point = Vector.extend { }` (with `extend` member function)
- `Point = { @extend Vector }` (with `@attribute` annotation)

Functions
---------
-   ```
	myFunction(x: Int): Int => {
		return x + 1
	}
	```
- `callback () => 10`
- `callback (x: Int): Int => x + 1`
- function calls are left associative (for fp-style currying)
  - `map increment myList`  is  `map(increment)(myList)`
- function definition statement: syntax sugar, like Lua
  - For recursive functions, otherwise with `self` or `this`? see semantics
  - `add(x, y) => x + y`  is  `var add; add = (x, y) => x + y`
  - `incr x => x + 1`     is  `var incr; incr = x => x + 1`
- overloading based on arity, otherwise argument types when present
  - problem: same index (function name) refers to multiple functions
  - possible solution: enhance function definition statement syntax
    and store the different functions inside the function Block
    (this means no overloading with lambda/fn-expression syntax)
    - with `fn(x)` and `fn(x,y)`, calling `fn(10,20)` will be equal to calling
      `fn.[[Block,Block]](10,20)`, indexed with lists of argument types
    - problem again: what about vararg functions?
- Getters by using argument-less methods, setters?
- Parentheses can be omitted if only one argument passed on the same line

Optional types
--------------
https://en.wikipedia.org/wiki/Gradual_typing
- C-style (does not work nicely with multiple return values)
	kind					| with type							| without type
	------------------------|-----------------------------------|---------------
	variable definition		| `Int a = 10`						| `var a = 10`, `a = 10`
	variable declaration	| `Int b`							| `var a`
	function definition		| `Int add(Int x, Int y) => x + y`
	function declaration	| `Int add(Int x, Int y)`			| `var add(x, y)`
	lambda definition		| `add = Int (Int x, Int y) => x + y`
	lambda declaration		| `add = Int (Int x, Int y)`

  - lambda definition / declaration might be weird depending on the "type" of a
    function (does the function have type Int? no.)

- TS / Kotlin-style
	kind					| with type							| without type
	------------------------|-----------------------------------|---------------
	variable definition		| `a: Int = 10`						| `a: Any = 10`, `a: = 10`, `a = 10`
	variable declaration	| `b: Int`							| `b: Any`, `b:`
	function definition		| `add(x: Int, y: Int): Int, Int => x + y`
	function declaration	| `add(x: Int, y: Int): Int, Int`	| `add(x, y): Any`, `add(x, y):`
	lambda definition		| `add = (x: Int, y: Int): Int, Int => x + y`
	lambda declaration		| `add = (x: Int, y: Int): Int, Int`

- Mix of both:
	kind					| with type								| without type
	------------------------|---------------------------------------|-----------
	variable definition		| `a: Int = 10`							| `a = 10`
	variable declaration	| `a: Int`								| `var a`
	function definition		| `add(x: Int, y: Int): Int, Int => x + y` | `add(x, y) => x + y`
	function declaration	| `add(x: Int, y: Int): Int, Int`		| `var add(x, y)`
	lambda definition		| `add = (x: Int, y: Int): Int, Int => x + y` | `add = (x, y) => x + y`
	lambda declaration		| `add = (x: Int, y: Int): Int, Int`	| (???)

Example
-------
	Point = { (Point is a block/class/object, but really an immediately-invoked function)
		static `()`(x, y) => { (call method for Point "class" / object)
			this.x = x
			this.y = y
		}
		`+`(p) => Point(this.x + p.x, this.y + p.y) (addition method for Point instances)
		getX => this.x ("getter method", no argument list, will be invoked on myPoint.getX)
		setX(x) => { this.x = x } (normal method, assignments are not expressions so brackets necessary)
		
		static base = { (static immediately-invoked function, block: Point.base = 11)
			x = 10
			return x + 1
		}
		static next = static.base + 1 (static "immediately-invoked function", really just a field)
		static nget => static.base + 1 (static "getter method")
		static getBase() => Point.base (static shorthand method, Point.getBase() returns 11)
	}



--------------------------------------------------------------------------------
#                                  Semantics                                   #
--------------------------------------------------------------------------------
Pure object oriented languages: smalltalk, ruby, scala

Self (this?) upvalue (keyword?)
- Only for instance (non-static) methods
- Refers to current instance
- self *and* this with different semantics? (referring to outer block vs current function?)

Static upvalue (keyword?)
- Refers to current block / class

Super upvalue (keyword?)
- Refers to superclass

Variable lookup
---------------
- Function closures
1. locals (function arguments are locals)
2. (for instance methods) instance variables of current class (implicit `self.`/`this.`)  
2.1. instance variables of superclass
3. static variables of current class (implicit `static.`)  
3.1. static variables of superclass

Operators
---------
Operators defined in the class they apply to
Using an operator is simply calling the operator method on the leftmost(?) operand
- unary operators are simple
- binary operators are less simple because their second argument might not be of a usable type
- n-ary operators (wrap operators) are weird because the content does not really
  have anything to do with the result
  - application on first type is still possible: default operator in Object / Block base class
    creates a list of itself and its arguments

Modifiers
---------
Apply to variables (not values). By default, only `public` is applied implicitly.
- private and public: variable only accessable (readable/writable) within the same class
- const (and var/variable/varying/changing/volatile?): cannot assign other value to variable
- static (and ??? instance? proto(type)? "dynamic" is weird):
  variable exists in class, instead of in its instances

Apply to values (blocks), not variables:
- fixed? final?: cannot mutate value (maybe freeze function?)

- assign to const value: error
- read private value: yield nil/null?
- write private value: error? do nothing?

Blocks can have default modifiers, which apply to all variables inside
the block that are not marked the opposite:

	Point = private {
		public getX => this.x (this method is public)
		setX(x) => { this.x = x } (this one is private)
	}

Blocks
------
Blocks serve many purposes at once:
- Objects (storing values by string keys)
- Arrays (storing values by numeric keys)
- Maps? (storing values by any type keys)
- Prototypes (objects with constructors and instance variables/methods)
- Modules (separating values between files)
- Grouping of code chunks (if, while, for etc)
- Function contents (code chunks with parameters)

"Class" (block) constructors are static call operator methods
Prototype-based classes (seem more generic) with class-based syntax

What to do with mutating/defining properties on objects/blocks?
- Should work differently than normal scope: mutation/definition in one
  because you don't always know whether a property is already present
- Option: only use mutation syntax
  - Problem: cannot set const properties (like in javascript), also not static/instance
  - Solution: allow modifiers also for mutation syntax?
  - Solution: different syntax for assigning/defining to index (nah, is less general)

Control flow
------------
- functions: return
- blocks / coroutines?: yield
- blocks: catch?
- coroutines: do? resume? dispatch? continue? calls function as coroutine, catches yields
  - maybe as method on functions `.resume()`?
- coroutines: async?
- defer?

For-loops
---------
`for x in fn` calls `fn.iterate` to get a generator function, repeatedly executes
the loop with x set to the return value of the generator, until it returns nil.

Concurrency
-----------
- Futures / Promises: http://dist-prog-book.com/chapter/2/futures.html
- Coroutines / Fibers: https://www.npmjs.com/package/fibers/v/4.0.3