# Oblock
Oblock is a prototype-based object-oriented language about generalisation.

## Features
Inspired by [Lua] and [Io], Oblock seeks to further reduce the number of
different concepts in a language by (over)generalising features together. These
are Oblock's main features / selling points:

### Blocks are objects
This unifies the creation of objects and the assignment of variables. Now you
can perform computations when creating objects!
```lua
a = {
    x = 21
    y = 2*x
}
print(a.y) --> 42
```
List literals are also blocks: (although assignment syntax works a little
differently)
```lua
a = [16, x = 42, (if true: -x), 32]
print(a.1, a.x) --> 16, 42
print(a) --> [16, -42, 32]
```
If you were wondering, this is what led to the name (object + block = Oblock).

### Prototypal OOP
Also notice the easy operator overloading by just assigning a function to the
string field `"+"`.
```lua
Vector = {
    "+" that => this.clone {
        x = this.x + that.x
        y = this.y + that.y
    }
}

v = Vector.clone {
    x = 10
    y = 20
}

print(v + v) --> { x = 20; y = 40 }
```

### A grain of FP
Definitions are constant by default and are separate from assignments. Use
`var` to define a new variable and `:=` to assign to an existing one.
```lua
map = fn => list => {
    new = []
    for x in list: new.append(fn x)
    return new
}

l = map (x => x+1) [10, 20, 30]
print l --> [11, 21, 31]
```

## Examples
### Reading input
```lua
IO = import "Io"
for word in IO.stdin.splitAt " ": print(word.toString().length)
```

For more examples of Oblock, have a look at the files in the
[`src/test/`](src/test/) directory.

## Installation
You can give Oblock a spin:
1. Clone the repository (`git clone https://github.com/Dantevg/Oblock`)
2. Install Lua if you haven't already
3. From the [`src/lua/`](src/lua/) directory, run `./oblock.lua` and type away!

### VS Code language extension
There is a VS Code extension that provides syntax highlighting. You can find it
here: https://github.com/Dantevg/Oblock-vscode. It's not yet on the marketplace,
but you can install it manually by downloading the latest version from the
[releases page](https://github.com/Dantevg/Oblock-vscode/releases) and running
`code --install-extension  oblock-language-0.0.3.vsix`.

## REPL
To enable the REPL, run Oblock with the `--interactive` or `-i` parameter. Each
line is interpreted as an expression. To assign variables at the top-level, you
can wrap assignments in parentheses:
```
> (hey := "hello")
> hey
hello
```

## Status and roadmap
Oblock is currently still very much in development and the design is not yet
final. Most basic features are complete, but the language is missing some key
features. These are the features that are still to come, roughly in order:
- I/O with streams
- proper module system
- standard library
- error handling
- coroutines
- parallelism

The [`notes/`](notes/) directory contains some files with notes. Please keep in
mind that most of those files are old and I haven't updated them in a while.
[`notes.md`](notes/notes.md) is the most active notes file, but that also still
has some old ideas and out-of-date information the further down you go.
These notes were also primarily meant for my later self (this repo was private
until very recent, depending on when you read this), so some may not even make
sense to you. They may also show you how much I don't know what I'm doing, but
oh well!

[Lua]: https://www.lua.org/
[Io]: https://iolanguage.org/
