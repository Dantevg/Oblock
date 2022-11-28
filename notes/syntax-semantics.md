
--------------------------------------------------------------------------------
#                                    Syntax                                    #
--------------------------------------------------------------------------------

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
- index operator: `.`
  - `a.b` is syntax sugar for `a."b"`
    - this means that `.` is not an operator, but fixed in the syntax (meh, but necessary)
  - when used in an expression, they are binary operators, called on the left
    operand with the right operand as argument
  - when used in a variable definition, they are ternary operators, called
    just like in an expression context, but also with the value as second argument

Statements and expressions
--------------------------
Blocks, classes and function bodies are all the same
In general, newlines are ignored and seen as whitespace (like Lua), except for
function calls.

List / array syntax using `[]` . These are all equal:

	[10, 20, a = b, 30]
	[
		10
		20
		a = b
		30
	]
	List.clone {
		1 = 10
		2 = 20
		a = b
		3 = 30
	}

Inheritance:
- `Point = Vector.clone { }` (with `clone` member function)

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
