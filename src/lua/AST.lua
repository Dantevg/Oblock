-- Inspired by https://craftinginterpreters.com/evaluating-expressions.html

local Interpreter = require "Interpreter"

local function evaluateAll(expressions, env)
	local values = {}
	for _, expr in ipairs(expressions) do
		for _, value in ipairs({expr:evaluate(env)}) do
			table.insert(values, value)
		end
	end
	return values
end

local AST = {}



AST.Expr = {}

AST.Expr.Unary = {}
AST.Expr.Unary.__index = AST.Expr.Unary
AST.Expr.Unary.__name = "Unary"

function AST.Expr.Unary.new(op, right)
	local self = {}
	self.op = op
	self.right = right
	return setmetatable(self, AST.Expr.Unary)
end

function AST.Expr.Unary:evaluate(env)
	local right = self.right:evaluate(env)
	local fn = right:get(self.op.lexeme)
	if type(fn) ~= "function" then
		error(string.format("no operator instance '%s' on %s value '%s'",
			self.op.lexeme, right.__name, self.right), 0)
	end
	return fn(right, env)
end

function AST.Expr.Unary:resolve(scope)
	self.right:resolve(scope)
end

function AST.Expr.Unary:__tostring()
	return string.format("(%s%s)", self.op.lexeme, self.right)
end

setmetatable(AST.Expr.Unary, {
	__call = function(_, ...) return AST.Expr.Unary.new(...) end,
})



AST.Expr.Binary = {}
AST.Expr.Binary.__index = AST.Expr.Binary
AST.Expr.Binary.__name = "Binary"

function AST.Expr.Binary.new(left, op, right)
	local self = {}
	self.left = left
	self.op = op
	self.right = right
	return setmetatable(self, AST.Expr.Binary)
end

function AST.Expr.Binary:evaluate(env)
	local left, right = self.left:evaluate(env), self.right:evaluate(env)
	local fn = left:get(self.op.lexeme)
	if type(fn) ~= "function" then
		error(string.format("no operator instance '%s' on %s value '%s'",
			self.op.lexeme, left.__name, self.left), 0)
	end
	return fn(left, env, right)
end

function AST.Expr.Binary:resolve(scope)
	self.left:resolve(scope)
	self.right:resolve(scope)
end

function AST.Expr.Binary:__tostring()
	return string.format("(%s %s %s)", self.left, self.op.lexeme, self.right)
end

setmetatable(AST.Expr.Binary, {
	__call = function(_, ...) return AST.Expr.Binary.new(...) end,
})



AST.Expr.Logical = {}
AST.Expr.Logical.__index = AST.Expr.Logical
AST.Expr.Logical.__name = "Logical"

function AST.Expr.Logical.new(left, op, right)
	local self = AST.Expr.Binary(left, op, right)
	return setmetatable(self, AST.Expr.Logical)
end

function AST.Expr.Logical:evaluate(env)
	local left = self.left:evaluate(env)
	if self.op.lexeme == "||" then
		return Interpreter.Boolean.toBoolean(env, left).value
			and left or self.right:evaluate(env)
	elseif self.op.lexeme == "&&" then
		return Interpreter.Boolean.toBoolean(env, left).value
			and self.right:evaluate(env) or left
	end
end

setmetatable(AST.Expr.Logical, {
	__call = function(_, ...) return AST.Expr.Logical.new(...) end,
	__index = AST.Expr.Binary
})



AST.Expr.Group = {}
AST.Expr.Group.__index = AST.Expr.Group
AST.Expr.Group.__name = "Group"

function AST.Expr.Group.new(expressions)
	local self = {}
	self.expressions = expressions
	return setmetatable(self, AST.Expr.Group)
end

function AST.Expr.Group:evaluate(env)
	return table.unpack(evaluateAll(self.expressions, env))
end

function AST.Expr.Group:define(env, values, modifiers)
	for i, expr in ipairs(self.expressions) do
		expr:define(env, values[i], modifiers)
	end
end

function AST.Expr.Group:assign(env, values)
	for i, expr in ipairs(self.expressions) do
		expr:assign(env, values[i])
	end
end

function AST.Expr.Group:resolve(scope)
	for _, expr in ipairs(self.expressions) do
		expr:resolve(scope)
	end
end

function AST.Expr.Group:__tostring()
	local expressions = {}
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return "("..table.concat(expressions, ", ")..")"
end

setmetatable(AST.Expr.Group, {
	__call = function(_, ...) return AST.Expr.Group.new(...) end,
})



AST.Expr.Variable = {}
AST.Expr.Variable.__index = AST.Expr.Variable
AST.Expr.Variable.__name = "Variable"

function AST.Expr.Variable.new(token)
	local self = {}
	self.token = token
	return setmetatable(self, AST.Expr.Variable)
end

function AST.Expr.Variable:evaluate(env)
	return env:get(self.token.lexeme, self.level)
end

function AST.Expr.Variable:define(env, value, modifiers)
	env:define(self.token.lexeme, value, modifiers)
end

function AST.Expr.Variable:assign(env, value)
	env:assign(self.token.lexeme, value, self.level)
end

function AST.Expr.Variable:resolve(scope)
	if self.level then error("resolving already-resolved variable", 0) end
	local level = 0
	while scope do
		if scope[self.token.lexeme] then self.level = level return end
		scope, level = scope.parent, level+1
	end
	if not self.level then error("unresolved variable "..self.token.lexeme, 0) end
end

function AST.Expr.Variable:__tostring()
	return self.token.lexeme
end

setmetatable(AST.Expr.Variable, {
	__call = function(_, ...) return AST.Expr.Variable.new(...) end,
})



AST.Expr.Index = {}
AST.Expr.Index.__index = AST.Expr.Index
AST.Expr.Index.__name = "Index"

-- b.(c).(d)  is  (b.(c)).(d)  is  Index(Index(Index(nil, b), c), d)

function AST.Expr.Index.new(base, expr)
	local self = {}
	self.base = base
	self.expr = expr
	return setmetatable(self, AST.Expr.Index)
end

local function ref(value, env)
	return value.__name == "Variable" and value.token.lexeme or value:evaluate(env)
end

function AST.Expr.Index:evaluate(env)
	return self.base:evaluate(env):get(ref(self.expr, env), self.level)
end

function AST.Expr.Index:define(env, value, modifiers)
	self.base:evaluate(env):define(ref(self.expr, env), value, modifiers)
end

function AST.Expr.Index:assign(env, value)
	self.base:evaluate(env):assign(ref(self.expr, env), value, self.level)
end

function AST.Expr.Index:resolve(scope)
	if self.level then error("resolving already-resolved variable", 0) end
	self.base:resolve(scope)
	if self.expr.__name ~= "Variable" then self.expr:resolve(scope) end
	self.level = 0
end

function AST.Expr.Index:__tostring()
	local base = tostring(self.base).."."
	return self.expr.__name == "Literal" and base..self.expr.lexeme or base..tostring(self.expr)
end

setmetatable(AST.Expr.Index, {
	__call = function(_, ...) return AST.Expr.Index.new(...) end,
})



AST.Expr.Block = {}
AST.Expr.Block.__index = AST.Expr.Block
AST.Expr.Block.__name = "Block"

function AST.Expr.Block.new(statements)
	local self = {}
	self.statements = statements
	return setmetatable(self, AST.Expr.Block)
end

function AST.Expr.Block:evaluate(env)
	local block = Interpreter.Block(env)
	for _, statement in ipairs(self.statements) do
		local success, err = pcall(statement.evaluate, statement, block.environment)
		if not success then
			if type(err) == "table" and err.__name == "Yield" then
				return table.unpack(err.values)
			else
				error(err, 0)
			end
		end
	end
	return block
end

function AST.Expr.Block:resolve(scope)
	local childScope = {parent = scope}
	for i = 1, #self.statements do
		self.statements[i]:resolve(childScope)
	end
end

function AST.Expr.Block:__tostring()
	local strings = {}
	for _, statement in ipairs(self.statements) do
		table.insert(strings, tostring(statement))
	end
	return "{"..table.concat(strings, "; ").."}"
end

setmetatable(AST.Expr.Block, {
	__call = function(_, ...) return AST.Expr.Block.new(...) end,
})



AST.Expr.List = {}
AST.Expr.List.__index = AST.Expr.List
AST.Expr.List.__name = "List"

function AST.Expr.List.new(expressions)
	local self = {}
	self.expressions = expressions
	return setmetatable(self, AST.Expr.List)
end

function AST.Expr.List:evaluate(parent)
	local list = Interpreter.List(parent)
	local values = evaluateAll(self.expressions, list.environment)
	for _, value in ipairs(values) do list:push(value) end
	return list
end

function AST.Expr.List:resolve(scope)
	local childScope = {parent = scope}
	for i = 1, #self.expressions do
		self.expressions[i]:resolve(childScope)
	end
end

function AST.Expr.List:__tostring()
	local strings = {}
	for _, value in ipairs(self.environment.environment) do
		table.insert(strings, tostring(value))
	end
	return "["..table.concat(strings, ", ").."]"
end

setmetatable(AST.Expr.List, {
	__call = function(_, ...) return AST.Expr.List.new(...) end,
})



AST.Expr.Function = {}
AST.Expr.Function.__index = AST.Expr.Function
AST.Expr.Function.__name = "Function"

function AST.Expr.Function.new(parameters, body)
	local self = {}
	self.parameters = parameters
	self.body = body
	return setmetatable(self, AST.Expr.Function)
end

function AST.Expr.Function:evaluate(env)
	local fn = Interpreter.Function(env, function(environment, args)
		return self:call(environment, args)
	end)
	function fn.__tostring() return self:__tostring() end
	return fn
end

function AST.Expr.Function:call(env, arguments)
	for i, parameter in ipairs(self.parameters.expressions) do
		local argument = arguments[i]
		if parameter.__name == "Variable" then
			env:define(parameter.token.lexeme, argument)
		elseif parameter.__name == "Unary" and parameter.op.type == "dot dot dot"
				and parameter.right.__name == "Variable" then
			local list = Interpreter.List(env)
			for j = i, #arguments do
				list:push(arguments[j])
			end
			env:define(parameter.right.token.lexeme, list)
			break
		else
			error("invalid parameter type", 0)
		end
	end
	
	return self.body:evaluate(env)
end

function AST.Expr.Function:resolve(scope)
	local childScope = {parent = {parent = scope}}
	for _, parameter in ipairs(self.parameters.expressions) do
		if parameter.__name == "Variable" then
			childScope[parameter.token.lexeme] = true
		elseif parameter.__name == "Unary" and parameter.op.type == "dot dot dot"
				and parameter.right.__name == "Variable" then
			childScope[parameter.right.token.lexeme] = true
			break
		else
			error("invalid parameter type", 0)
		end
	end
	self.body:resolve(childScope)
end

function AST.Expr.Function:__tostring()
	return string.format("%s => %s", self.parameters, self.body)
end

setmetatable(AST.Expr.Function, {
	__call = function(_, ...) return AST.Expr.Function.new(...) end,
})



AST.Expr.Call = {}
AST.Expr.Call.__index = AST.Expr.Call
AST.Expr.Call.__name = "Call"

function AST.Expr.Call.new(expression, arglist)
	local self = {}
	self.expression = expression
	self.arglist = arglist
	return setmetatable(self, AST.Expr.Call)
end

function AST.Expr.Call:evaluate(env)
	local fn = self.expression:evaluate(env)
	if not Interpreter.isCallable(fn) then
		error("Attempt to call non-callable type "..fn.__name, 0)
	end
	local arguments = {self.arglist:evaluate(env)}
	return fn:call(arguments)
end

function AST.Expr.Call:resolve(scope)
	self.expression:resolve(scope)
	self.arglist:resolve(scope)
end

function AST.Expr.Call:__tostring()
	return string.format("%s %s", self.expression, self.arglist)
end

setmetatable(AST.Expr.Call, {
	__call = function(_, ...) return AST.Expr.Call.new(...) end,
})



AST.Expr.Literal = {}
AST.Expr.Literal.__index = AST.Expr.Literal
AST.Expr.Literal.__name = "Literal"

function AST.Expr.Literal.new(literal, lexeme)
	local self = {}
	if lexeme then
		self.literal = literal
		self.lexeme = lexeme
	else
		self.literal = literal.literal
		self.lexeme = literal.lexeme
	end
	return setmetatable(self, AST.Expr.Literal)
end

function AST.Expr.Literal:evaluate(env)
	if type(self.literal) == "number" then
		return Interpreter.Number(env, self.literal)
	elseif type(self.literal) == "string" then
		return Interpreter.String(env, self.literal)
	elseif type(self.literal) == "nil" then
		return Interpreter.Nil(env)
	end
end

function AST.Expr.Literal.resolve() end

function AST.Expr.Literal:__tostring()
	return self.lexeme
end

setmetatable(AST.Expr.Literal, {
	__call = function(_, ...) return AST.Expr.Literal.new(...) end,
})

function AST.Expr.Literal.Nil()
	return AST.Expr.Literal(nil, "nil")
end



AST.Stat = {}

AST.Stat.Return = {}
AST.Stat.Return.__index = AST.Stat.Return
AST.Stat.Return.__name = "Return"

function AST.Stat.Return.new(expressions)
	local self = {}
	self.expressions = expressions or {}
	return setmetatable(self, AST.Stat.Return)
end

function AST.Stat.Return:evaluate(env)
	self.values = evaluateAll(self.expressions, env)
	error(self, 0)
end

function AST.Stat.Return:resolve(scope)
	for _, expr in ipairs(self.expressions) do
		expr:resolve(scope)
	end
end

function AST.Stat.Return:__tostring()
	local expressions = {}
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return "return "..table.concat(expressions, ", ")
end

setmetatable(AST.Stat.Return, {
	__call = function(_, ...) return AST.Stat.Return.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.Yield = {}
AST.Stat.Yield.__index = AST.Stat.Yield
AST.Stat.Yield.__name = "Yield"

function AST.Stat.Yield.new(expressions)
	local self = {}
	self.expressions = expressions
	return setmetatable(self, AST.Stat.Yield)
end

function AST.Stat.Yield:evaluate(env)
	self.values = self.expressions and evaluateAll(self.expressions, env)
	error(self, 0)
end

function AST.Stat.Yield:resolve(scope)
	for _, expr in ipairs(self.expressions) do
		expr:resolve(scope)
	end
end

function AST.Stat.Yield:__tostring()
	local expressions = {}
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return "yield "..table.concat(expressions, ", ")
end

setmetatable(AST.Stat.Yield, {
	__call = function(_, ...) return AST.Stat.Yield.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.If = {}
AST.Stat.If.__index = AST.Stat.If
AST.Stat.If.__name = "If"

function AST.Stat.If.new(condition, ifTrue, ifFalse)
	local self = {}
	self.condition = condition
	self.ifTrue = ifTrue
	self.ifFalse = ifFalse
	return setmetatable(self, AST.Stat.If)
end

function AST.Stat.If:evaluate(env)
	if self.condition:evaluate(env).value then
		self.ifTrue:evaluate(env)
	elseif self.ifFalse then
		self.ifFalse:evaluate(env)
	end
end

function AST.Stat.If:resolve(scope)
	self.condition:resolve(scope)
	self.ifTrue:resolve(scope)
	if self.ifFalse then self.ifFalse:resolve(scope) end
end

function AST.Stat.If:__tostring()
	if self.ifFalse then
		return string.format("if %s: %s else %s", self.condition, self.ifTrue, self.ifFalse)
	else
		return string.format("if %s: %s", self.condition, self.ifTrue)
	end
end

setmetatable(AST.Stat.If, {
	__call = function(_, ...) return AST.Stat.If.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.While = {}
AST.Stat.While.__index = AST.Stat.While
AST.Stat.While.__name = "While"

function AST.Stat.While.new(condition, body)
	local self = {}
	self.condition = condition
	self.body = body
	return setmetatable(self, AST.Stat.While)
end

function AST.Stat.While:evaluate(env)
	while self.condition:evaluate(env).value do
		self.body:evaluate(env)
	end
end

function AST.Stat.While:resolve(scope)
	self.condition:resolve(scope)
	self.body:resolve(scope)
end

function AST.Stat.While:__tostring()
	return string.format("while %s: %s", self.condition, self.body)
end

setmetatable(AST.Stat.While, {
	__call = function(_, ...) return AST.Stat.While.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.For = {}
AST.Stat.For.__index = AST.Stat.For
AST.Stat.For.__name = "For"

function AST.Stat.For.new(variable, expr, body)
	local self = {}
	self.variable = variable
	self.expr = expr
	self.body = body
	return setmetatable(self, AST.Stat.For)
end

function AST.Stat.For:evaluate(env)
	-- Get iterator from expr
	local container = self.expr:evaluate(env)
	local iteratorSource = container:get("iterate")
	if not Interpreter.isCallable(iteratorSource) then
		error(string.format("no callable instance 'iterate' on %s value '%s'",
			container.__name, self.expr), 0)
	end
	local iterator = iteratorSource:call(env)
	if not Interpreter.isCallable(iterator) then
		error("'iterate' does not return callable", 0)
	end
	
	-- Loop: set variable to iterator result, run body if result was non-nil
	local block = Interpreter.Block(env)
	local value = iterator:call(block)
	self.variable:define(block)
	while value and value.__name ~= "Nil" do
		self.variable:assign(block, value)
		self.body:evaluate(block)
		value = iterator:call(block)
	end
end

function AST.Stat.For:resolve(scope)
	self.expr:resolve(scope)
	local childScope = {parent = scope}
	childScope[self.variable.token.lexeme] = true
	self.body:resolve(childScope)
end

function AST.Stat.For:__tostring()
	return string.format("for %s in %s: %s", self.variable, self.expr, self.body)
end

setmetatable(AST.Stat.For, {
	__call = function(_, ...) return AST.Stat.For.new(...) end,
	__index = AST.Expr.Literal,
})



AST.Stat.Definition = {}
AST.Stat.Definition.__index = AST.Stat.Definition
AST.Stat.Definition.__name = "Definition"

function AST.Stat.Definition.new(targets, expressions, modifiers, predef)
	local self = {}
	self.targets = targets
	self.expressions = expressions
	self.modifiers = modifiers
	self.predef = predef
	return setmetatable(self, AST.Stat.Definition)
end

function AST.Stat.Definition:evaluate(env)
	local values = evaluateAll(self.expressions, env)
	
	for i, target in ipairs(self.targets) do
		target:define(env, values[i] or AST.Expr.Literal.Nil(), self.modifiers)
	end
end

function AST.Stat.Definition:resolve(scope)
	for _, target in ipairs(self.targets) do
		if scope[target.token.lexeme] then
			error("redefinition of "..target.token.lexeme, 0)
		end
		if self.predef then scope[target.token.lexeme] = true end
	end
	
	for _, expr in ipairs(self.expressions) do
		expr:resolve(scope)
	end
	
	for _, target in ipairs(self.targets) do
		scope[target.token.lexeme] = true
	end
end

function AST.Stat.Definition:__tostring()
	local targets, expressions = {}, {}
	for _, target in ipairs(self.targets) do
		table.insert(targets, tostring(target))
	end
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return "var "..(self.predef and table.concat(targets, ", ").."; " or "")
		..table.concat(targets, ", ").." = "..table.concat(expressions, ", ")
end

setmetatable(AST.Stat.Definition, {
	__call = function(_, ...) return AST.Stat.Definition.new(...) end,
})



AST.Stat.Assignment = {}
AST.Stat.Assignment.__index = AST.Stat.Assignment
AST.Stat.Assignment.__name = "Assignment"

function AST.Stat.Assignment.new(targets, expressions)
	local self = {}
	self.targets = targets
	self.expressions = expressions
	return setmetatable(self, AST.Stat.Assignment)
end

function AST.Stat.Assignment:evaluate(env)
	local values = evaluateAll(self.expressions, env)
	
	for i, target in ipairs(self.targets) do
		target:assign(env, values[i] or AST.Expr.Literal.Nil())
	end
end

function AST.Stat.Assignment:resolve(scope)
	for _, expr in ipairs(self.expressions) do expr:resolve(scope) end
	for _, target in ipairs(self.targets) do target:resolve(scope) end
end

function AST.Stat.Assignment:__tostring()
	return tostring(self.target).." = "..tostring(self.expr)
end

setmetatable(AST.Stat.Assignment, {
	__call = function(_, ...) return AST.Stat.Assignment.new(...) end,
})



return AST
