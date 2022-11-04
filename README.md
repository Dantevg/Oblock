# Oblock language
Oblock is a prototype-based object-oriented language about generalisation.

## Features
Inspired by [Lua] and [Io], I sought to further reduce the number of different
concepts in a language by (over)generalising features together. These are
Oblock's main features / selling points:
- **Blocks are objects**  
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
  differently at the moment)
  ```lua
  a = [16, x = 42, 32]
  print(a.1, a.x) --> 16, 42
  ```
	If you were wondering, this is what led to the name (object + block = Oblock).
- **Prototypal OOP**  
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
  ```
- **A grain of FP**  
  ```lua
  map = fn => list => {
      new = []
      for x in list: {
          new.append(fn x)
      }
      return new
  }
  
  l = map (x => x+1) [10, 20, 30]
  print l --> [11, 21, 31]
  ```

It is currently still very much in development and the design is not yet final.

[Lua]: https://www.lua.org/
[Io]: https://iolanguage.org/
