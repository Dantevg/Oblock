
--------------------------------------------------------------------------------
#                                   Bytecode                                   #
--------------------------------------------------------------------------------

Notes / ideas
-------------
I'm not having much of a clue what I'm doing here, it might also be a bit
premature to think about the bytecode before the syntax and semantics are clear.

Special type coding for integers? Con: implementation becomes less generic
- ?? nothing?
- 00 block
- 01 function
- 10 unsigned long int (62-bit)
- 11 long int (62-bit)

Datatypes / values
------------------

2 (3?) basic datatypes
- Nothing?
- Block / instance / class / prototype
  - Variable-length code for class?
  - number of elements (size)
  - optionally instance contents
- Function
  - list of parameters (with names and default values) and return values
  - class

What to do for values of native types (`fn.["()"]` and `number.value`)?
- make them return themself? `fn.["()"] == fn` and `number.value == number`?
  - would make sure every value is of "Block" / "Object" basic datatype,
    no datatype storage needed (saves a couple bits, don't know if necessary)
  - store actual value in some kind of metadata?
- extra (3rd?) basic type: native/internal blob, storing value?
  - con: possibly extra indirection
- no number.value, `fn.["()"]` is other (native) function with `["()"]` set
  to itself, like javascript function.call: `fn.["()"].["()"]` == `fn.["()"]`
  - store actual value in some kind of metadata / userdata?



--------------------------------------------------------------------------------
#                               Interpreter / VM                               #
--------------------------------------------------------------------------------
https://craftinginterpreters.com/contents.html

Ideas
-----
- For functions returning closures, somehow store the returned function inside
  the outer function to prevent re-creating functions every time

Variables / fields
------------------
Some way to not have to allocate for simple ("primitive") types (int, float,
bool, nil)

- modifiers: private, const, static
- type? possible data duplication, type is also stored in value
- data or pointer, plus something to indicate which of the two
  - idea: allocate object members directly after object header,
    relative pointers would improve locality and allow for smaller header size
    (relative offset can be int or even short, in steps of base size = 2*long?)

Value representation optimisations
----------------------------------
- NaN boxing / pointer tagging:
  - https://www.npopov.com/2012/02/02/Pointer-magic-for-efficient-dynamic-value-representations.html
  - https://bernsteinbear.com/pl-resources/#pointer-tagging-and-nan-boxing
  - https://sean.cm/a/nan-boxing
  - https://frama-c.com/2013/05/09/A-63-bit-floating-point-type-for-64-bit-OCaml.html
  - optimise for pointer case, not for float case
  - NaN boxing pros: no need to allocate float
  - pointer tagging pros: larger int, more room for user-defined types
- pointer compression: https://v8.dev/blog/pointer-compression
  - most pointers still fit in 32 bits
  - most programs need < 4 GB of memory
  - doubt the memory savings are worth the hassle (maybe much later)

8-byte / 64-bit memory layout:

	|----7---|----6---|----5---|----4---| |----3---|----2---|----1---|----0---|
	 63    56 55    48 47    40 39    32   31    24 23    16 15     8 7      0

	. : unused bit			b : boolean
	x : any					f : float distinguisher
	p : pointer				s : sign
	t : type				e : exponent
	i : integer				m : mantissa

### Unoptimised value (just a pointer)
Type			| Layout
----------------|---------------------------------------------------------------
pointer			| `pppppppp pppppppp pppppppp pppppppp pppppppp pppppppp pppppppp pppppppp`

### NaN boxing (using signalling NaN because that never occurs normally)
Type			| Layout
----------------|---------------------------------------------------------------
general			| `ffffffff fffffttt xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx`
float (64 bits)	| `seeeeeee eeeemmmm mmmmmmmm mmmmmmmm mmmmmmmm mmmmmmmm mmmmmmmm mmmmmmmm`
pointer			| `.1111111 11110010 pppppppp pppppppp pppppppp pppppppp pppppppp pppppppp`
int (50 bits)	| `01111111 111101ii iiiiiiii iiiiiiii iiiiiiii iiiiiiii iiiiiiii iiiiiiii`
other (50 bits)	| `11111111 111101xx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx`

### Pointer tagging
Type			| Layout
----------------|---------------------------------------------------------------
general			| `xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxttt`
float (32 bits)	| `seeeeeee emmmmmmm mmmmmmmm mmmmmmmm ........ ........ ........ .....010`
pointer			| `pppppppp pppppppp pppppppp pppppppp pppppppp pppppppp pppppppp ppppp000`
int (63 bits)	| `iiiiiiii iiiiiiii iiiiiiii iiiiiiii iiiiiiii iiiiiiii iiiiiiii iiiiiii1`
other (56 bits)	| `xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxx100`



--------------------------------------------------------------------------------
#                                     API                                      #
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
#                               Standard library                               #
--------------------------------------------------------------------------------
https://en.wikipedia.org/wiki/Abstract_data_type#Examples

Naming: module / package / library ?
- module: Lua, Python, ...
- package: Java, Python, Go, Scala, ...
- library: Javascript, C, ...

Probably: (inspired by Java/Python, in order from small to large)
- module: single file
- package: collection of files (directory/folder)
  - grouping similar functionality
  - needs main file/module
- collection/bundle: collection of packages
  - packages not necessarily offering similar functionality
  - more about downloading, should be indistinguishable in code?

2 Collections/bundles for language:
- Base/core/[langname] collection: only essentials, always present / no need to
  import (for embedding, like Lua)
  - Nil, Bool, Int, Float, ASCIIString, Math/Random, List, ...?
- Extended collection: more extensive, optional (for stand-alone usage, like Java/Python)
  - ideas: UnicodeString / UTF8String, Debug, OS/IO/FS, Date, Regex, Socket,
    JSON, encoding/decoding, data structures (Set, Bag, Map, Stack, Queue, ...),
    Thread, BigInt/BigNum, ...

- ASCII string and Unicode/UTF8 string separate?
  - maybe Unicode string in base lib, ASCII string in std lib?
    - pro: need unicode support for lexing/parsing anyway so why not provide string
    - con: possibly more resource intensive (string indexing complexity, storage etc)

- Modulo int type for automatic calculations modulo n, as a generalisation of
  wrapping int overflow operations

- Iterator type with default stream-like functions (map, filter, ...)
  - https://github.com/tc39/proposal-iterator-helpers
  - Get these functions by extending `Iterator` (or `Stream`?)
