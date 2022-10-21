-- Inspired by https://craftinginterpreters.com/evaluating-expressions.html

local Interpreter = require "Interpreter"
local stdlib = require "stdlib"

local function catchBreakContinue(body, env)
	local success, err = pcall(body.evaluate, body, env)
	if not success then
		if type(err) == "table" and err.__name == "Break" then
			err.level = err.level-1
			if err.level > 0 then
				error(err, 0)
			else
				return err.values
			end
		elseif type(err) ~= "table" or err.__name ~= "Continue" then
			error(err, 0)
		end
	end
end

local pretty, tc
local function debugValue(indent, name, properties, nodelists)
	if not pretty then
		local success
		success, pretty = pcall(require, "pretty")
		if success then
			pretty = pretty.new {deep = 5}
		else
			pretty = tostring
		end
	end
	if not tc then
		local success
		success, tc = pcall(require, "terminalcolours")
		if not success then tc = setmetatable({fg={},bg={},cursor={}},{__call=function()return""end}) end
	end
	
	indent = indent or ""
	local str = {}
	
	local proplist = {}
	for k, v in pairs(properties) do
		table.insert(proplist, tostring(k)..": "..pretty(v))
	end
	str[1] = indent..tc(tc.fg.red)..name..tc(tc.reset).." { "..table.concat(proplist, ", ").." }"
	
	for nodelistname, nodes in pairs(nodelists) do
		table.insert(str, indent.."  - "..nodelistname..":")
		for _, node in ipairs(nodes) do
			local value, isSingleLine = node:debug(indent.."    ")
			table.insert(str, value)
		end
		if #nodes == 1 then
			str[#str-1] = str[#str-1].." "..table.remove(str):match("^%s*(.+)$")
		elseif #nodes == 0 then
			table.remove(str)
		end
	end
	
	return table.concat(str, "\n"), #str == 1
end

local AST = {}



AST.Expr = {}

AST.Expr.Logical = {}
AST.Expr.Logical.__index = AST.Expr.Logical
AST.Expr.Logical.__name = "Logical"

function AST.Expr.Logical.new(left, op, right, loc)
	local self = {}
	self.left = left
	self.op = op
	self.right = right
	self.loc = loc
	return setmetatable(self, AST.Expr.Logical)
end

function AST.Expr.Logical:evaluate(env)
	local left = self.left:evaluate(env)
	if self.op.lexeme == "or" then
		return stdlib.Boolean.toBoolean(left).value
			and left or self.right:evaluate(env)
	elseif self.op.lexeme == "and" then
		return stdlib.Boolean.toBoolean(left).value
			and self.right:evaluate(env) or left
	end
end

function AST.Expr.Logical:resolve(scope)
	self.left:resolve(scope)
	self.right:resolve(scope)
end

function AST.Expr.Logical:debug(indent)
	return debugValue(indent, self.__name, {op = self.op.lexeme},
		{left = {self.left}, right = {self.right}})
end

function AST.Expr.Logical:__tostring()
	return string.format("(%s %s %s)", self.left, self.op.lexeme, self.right)
end

setmetatable(AST.Expr.Logical, {
	__call = function(_, ...) return AST.Expr.Logical.new(...) end,
})



AST.Expr.Group = {}
AST.Expr.Group.__index = AST.Expr.Group
AST.Expr.Group.__name = "Group"

function AST.Expr.Group.new(expressions, loc)
	local self = {}
	self.expressions = expressions or {}
	self.loc = loc
	return setmetatable(self, AST.Expr.Group)
end

function AST.Expr.Group:evaluate(env)
	local values = {}
	for _, expr in ipairs(self.expressions) do
		for _, value in ipairs({expr:evaluate(env)}) do
			table.insert(values, value)
		end
	end
	return table.unpack(values)
end

function AST.Expr.Group:resolve(scope)
	for _, expr in ipairs(self.expressions) do
		expr:resolve(scope)
	end
end

function AST.Expr.Group:debug(indent)
	return debugValue(indent, self.__name, {}, {expressions = self.expressions})
end

function AST.Expr.Group:__tostring()
	local expressions = {}
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return table.concat(expressions, ", ")
end

setmetatable(AST.Expr.Group, {
	__call = function(_, ...) return AST.Expr.Group.new(...) end,
})



AST.Expr.Variable = {}
AST.Expr.Variable.__index = AST.Expr.Variable
AST.Expr.Variable.__name = "Variable"

function AST.Expr.Variable.new(token, loc)
	local self = {}
	self.token = token
	self.loc = loc
	return setmetatable(self, AST.Expr.Variable)
end

function AST.Expr.Variable:evaluate(env)
	local value = env:get(self.token.lexeme, self.level)
	if value and value.__name == "Nil" and not value.loc then value.loc = self.loc end
	return value
end

function AST.Expr.Variable:setSelf(env, value, modifiers)
	env:setAtLevel(self.token.lexeme, value, modifiers, self.level)
end

function AST.Expr.Variable:resolve(scope)
	if self.level then Interpreter.error("resolving already-resolved variable "..tostring(self), self.loc) end
	local level = 0
	while scope do
		if scope[self.token.lexeme] then self.level = level return end
		scope, level = scope.parent, level+1
	end
	if not self.level then Interpreter.error("unresolved variable "..self.token.lexeme, self.loc) end
end

function AST.Expr.Variable:debug(indent)
	return debugValue(indent, self.__name, {token = self.token.lexeme}, {})
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

-- b.(c).(d)  is  (b.(c)).(d)  is  Index(Index(Variable(b), c), d)

function AST.Expr.Index.new(base, expr, loc)
	local self = {}
	self.base = base
	self.expr = expr
	self.loc = loc
	return setmetatable(self, AST.Expr.Index)
end

local function ref(value, env)
	return value.__name == "Variable" and value.token.lexeme or value:evaluate(env)
end

function AST.Expr.Index:evaluate(env)
	local value = (self.base and self.base:evaluate(env) or env):get(ref(self.expr, env), self.level)
	if value and value.__name == "Nil" and not value.loc then value.loc = self.loc end
	return value
end

function AST.Expr.Index:setSelf(env, value, modifiers)
	(self.base and self.base:evaluate(env) or env):setAtLevel(ref(self.expr, env), value, modifiers, self.level)
end

function AST.Expr.Index:resolve(scope)
	if self.level then Interpreter.error("resolving already-resolved variable "..tostring(self), self.loc) end
	if self.base then self.base:resolve(scope) end
	if self.expr.__name ~= "Variable" then self.expr:resolve(scope) end
	self.level = 0
end

function AST.Expr.Index:debug(indent)
	return debugValue(indent, self.__name, {}, {base = {self.base}, expr = {self.expr}})
end

function AST.Expr.Index:__tostring()
	return tostring(self.base or "").."."..tostring(self.expr)
end

setmetatable(AST.Expr.Index, {
	__call = function(_, ...) return AST.Expr.Index.new(...) end,
})



AST.Expr.Block = {}
AST.Expr.Block.__index = AST.Expr.Block
AST.Expr.Block.__name = "Block"

function AST.Expr.Block.new(statements, loc)
	local self = {}
	self.statements = statements
	self.loc = loc
	return setmetatable(self, AST.Expr.Block)
end

function AST.Expr.Block:evaluate(env)
	local block = stdlib.Block(env)
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

function AST.Expr.Block:debug(indent)
	return debugValue(indent, self.__name, {}, {statements = self.statements})
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

function AST.Expr.List.new(expressions, loc)
	local self = {}
	self.expressions = AST.Expr.Group(expressions, loc)
	self.loc = loc
	return setmetatable(self, AST.Expr.List)
end

function AST.Expr.List:evaluate(parent)
	local list = stdlib.List(parent)
	local values = {self.expressions:evaluate(list.environment)}
	for _, value in ipairs(values) do list:push(value) end
	return list
end

function AST.Expr.List:resolve(scope)
	self.expressions:resolve {parent = scope}
end

function AST.Expr.List:debug(indent)
	return debugValue(indent, self.__name, {}, {expressions = self.expressions.expressions})
end

function AST.Expr.List:__tostring()
	return "["..self.expressions:__tostring().."]"
end

setmetatable(AST.Expr.List, {
	__call = function(_, ...) return AST.Expr.List.new(...) end,
})



AST.Expr.Function = {}
AST.Expr.Function.__index = AST.Expr.Function
AST.Expr.Function.__name = "Function"

function AST.Expr.Function.new(parameters, body, loc)
	local self = {}
	self.parameters = parameters
	self.body = body
	self.loc = loc
	return setmetatable(self, AST.Expr.Function)
end

function AST.Expr.Function:evaluate(env)
	local fn = stdlib.Function(env, function(environment, args)
		return self:call(environment, args)
	end, nil, self.parameters)
	function fn.__tostring() return self:__tostring() end
	return fn
end

function AST.Expr.Function:call(env, arguments)
	self.parameters:define(env, arguments)
	return self.body:evaluate(env)
end

function AST.Expr.Function:resolve(scope)
	local childScope = {this = true, parent = {parent = scope}}
	self.parameters:resolve(childScope, true)
	self.body:resolve(childScope)
end

function AST.Expr.Function:debug(indent)
	return debugValue(indent, self.__name, {},
		{parameters = {self.parameters}, body = {self.body}})
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

function AST.Expr.Call.new(expression, arglist, loc)
	local self = {}
	self.expression = expression
	self.arglist = arglist
	self.loc = loc
	return setmetatable(self, AST.Expr.Call)
end

function AST.Expr.Call:evaluate(env)
	local fn = self.expression:evaluate(env)
	if not Interpreter.isCallable(fn) then
		Interpreter.error("Attempt to call non-callable type "
			..(fn and fn.__name or "Nil"), self.loc, fn and fn.loc)
	end
	local args = {self.arglist:evaluate(env)}
	local argsToMatch = {}
	for i, v in ipairs(args) do argsToMatch[i] = v end -- Copy for matching
	if fn.parameters and not fn.parameters:match(env, argsToMatch) then
		Interpreter.error("function parameters do not match parameter signature "..tostring(fn.parameters), self.loc)
		return stdlib.Nil(self.loc)
	end
	return fn:call(table.unpack(args))
end

function AST.Expr.Call:resolve(scope)
	self.expression:resolve(scope)
	self.arglist:resolve(scope)
end

function AST.Expr.Call:debug(indent)
	return debugValue(indent, self.__name, {},
		{expression = {self.expression}, args = {self.arglist}})
end

function AST.Expr.Call:__tostring()
	return string.format("%s %s", self.expression, self.arglist)
end

setmetatable(AST.Expr.Call, {
	__call = function(_, ...) return AST.Expr.Call.new(...) end,
})



AST.Expr.If = {}
AST.Expr.If.__index = AST.Expr.If
AST.Expr.If.__name = "If"

function AST.Expr.If.new(condition, ifTrue, ifFalse, loc)
	local self = {}
	self.condition = condition
	self.ifTrue = ifTrue
	self.ifFalse = ifFalse
	self.loc = loc
	return setmetatable(self, AST.Expr.If)
end

function AST.Expr.If:evaluate(env)
	if self.condition:evaluate(env).value then
		return self.ifTrue:evaluate(env)
	elseif self.ifFalse then
		return self.ifFalse:evaluate(env)
	end
end

function AST.Expr.If:resolve(scope)
	self.condition:resolve(scope)
	self.ifTrue:resolve(scope)
	if self.ifFalse then self.ifFalse:resolve(scope) end
end

function AST.Expr.If:debug(indent)
	return debugValue(indent, self.__name, {},
		{condition = {self.condition}, ["then"] = {self.ifTrue}, ["else"] = {self.ifFalse}})
end

function AST.Expr.If:__tostring()
	if self.ifFalse then
		return string.format("if %s: %s else %s", self.condition, self.ifTrue, self.ifFalse)
	else
		return string.format("if %s: %s", self.condition, self.ifTrue)
	end
end

setmetatable(AST.Expr.If, {
	__call = function(_, ...) return AST.Expr.If.new(...) end,
})



AST.Expr.While = {}
AST.Expr.While.__index = AST.Expr.While
AST.Expr.While.__name = "While"

function AST.Expr.While.new(condition, body, loc)
	local self = {}
	self.condition = condition
	self.body = body
	self.loc = loc
	return setmetatable(self, AST.Expr.While)
end

function AST.Expr.While:evaluate(env)
	while self.condition:evaluate(env).value do
		local breakVals = catchBreakContinue(self.body, env)
		if breakVals then return table.unpack(breakVals) end
	end
end

function AST.Expr.While:resolve(scope)
	self.condition:resolve(scope)
	self.body:resolve(scope)
end

function AST.Expr.While:debug(indent)
	return debugValue(indent, self.__name, {},
		{condition = {self.condition}, body = {self.body}})
end

function AST.Expr.While:__tostring()
	return string.format("while %s: %s", self.condition, self.body)
end

setmetatable(AST.Expr.While, {
	__call = function(_, ...) return AST.Expr.While.new(...) end,
})



AST.Expr.For = {}
AST.Expr.For.__index = AST.Expr.For
AST.Expr.For.__name = "For"

function AST.Expr.For.new(targets, expr, body, loc)
	local self = {}
	self.targets = targets
	self.expr = expr
	self.body = body
	self.loc = loc
	return setmetatable(self, AST.Expr.For)
end

function AST.Expr.For:evaluate(env)
	-- Get iterator from expr
	local container = self.expr:evaluate(env)
	local iteratorSource = container:get("iterate")
	if not Interpreter.isCallable(iteratorSource) then
		Interpreter.error(string.format("no callable instance 'iterate' on %s value '%s'",
			container.__name, self.expr), self.loc, container.loc)
	end
	local iterator = iteratorSource:call()
	if not Interpreter.isCallable(iterator) then
		Interpreter.error("'iterate' returns non-callable type "..iterator.__name,
			self.loc, iterator.loc)
	end
	
	-- Loop: set variable to iterator result, run body if result was non-nil
	local block = stdlib.Block(env)
	local values = {iterator:call()}
	for _, target in ipairs(self.targets) do
		target:setSelf(block)
	end
	while values[1] and values[1].__name ~= "Nil" do
		for i, target in ipairs(self.targets) do
			local value = values[i] or stdlib.Nil(self.loc)
			target:setSelf(block, value)
		end
		local breakVals = catchBreakContinue(self.body, block)
		if breakVals then return table.unpack(breakVals) end
		values = {iterator:call()}
	end
end

function AST.Expr.For:resolve(scope)
	self.expr:resolve(scope)
	local childScope = {parent = scope}
	for _, target in ipairs(self.targets) do
		childScope[target.token.lexeme] = true
	end
	self.body:resolve(childScope)
end

function AST.Expr.For:debug(indent)
	return debugValue(indent, self.__name, {variable = self.variable},
		{expression = {self.expr}, body = {self.body}})
end

function AST.Expr.For:__tostring()
	return string.format("for %s in %s: %s", self.variable, self.expr, self.body)
end

setmetatable(AST.Expr.For, {
	__call = function(_, ...) return AST.Expr.For.new(...) end,
})



AST.Expr.Literal = {}
AST.Expr.Literal.__index = AST.Expr.Literal
AST.Expr.Literal.__name = "Literal"

function AST.Expr.Literal.new(literal, lexeme, loc)
	local self = {}
	if lexeme then
		self.literal = literal
		self.lexeme = lexeme
	else
		self.literal = literal.literal
		self.lexeme = literal.lexeme
	end
	self.loc = loc
	return setmetatable(self, AST.Expr.Literal)
end

function AST.Expr.Literal:evaluate(env)
	if type(self.literal) == "number" then
		return stdlib.Number(self.literal)
	elseif type(self.literal) == "string" then
		return stdlib.String(self.literal)
	elseif type(self.literal) == "nil" then
		return stdlib.Nil(self.loc)
	end
end

function AST.Expr.Literal.resolve() end

function AST.Expr.Literal:debug(indent)
	return debugValue(indent, self.__name, {token = self.lexeme}, {})
end

function AST.Expr.Literal:__tostring()
	return self.lexeme
end

setmetatable(AST.Expr.Literal, {
	__call = function(_, ...) return AST.Expr.Literal.new(...) end,
})



AST.Stat = {}

AST.Stat.ControlFlow = {}
AST.Stat.ControlFlow.__index = AST.Stat.ControlFlow

function AST.Stat.ControlFlow.new(expressions, loc)
	local self = {}
	self.expressions = AST.Expr.Group(expressions or {}, loc)
	self.loc = loc
	return setmetatable(self, AST.Stat.ControlFlow)
end

function AST.Stat.ControlFlow:evaluate(env)
	self.values = {self.expressions:evaluate(env)}
	error(self, 0)
end

function AST.Stat.ControlFlow:resolve(scope)
	self.expressions:resolve(scope)
end

function AST.Stat.ControlFlow:debug(indent)
	return debugValue(indent, self.__name, {}, {expressions = self.expressions.expressions})
end

setmetatable(AST.Stat.ControlFlow, {
	__call = function(_, ...) return AST.Stat.ControlFlow.new(...) end,
})



AST.Stat.Return = {}
AST.Stat.Return.__index = AST.Stat.Return
AST.Stat.Return.__name = "Return"

function AST.Stat.Return.new(expressions, loc)
	return setmetatable(AST.Stat.ControlFlow(expressions, loc), AST.Stat.Return)
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
	__index = AST.Stat.ControlFlow,
})



AST.Stat.Yield = {}
AST.Stat.Yield.__index = AST.Stat.Yield
AST.Stat.Yield.__name = "Yield"

function AST.Stat.Yield.new(expressions, loc)
	return setmetatable(AST.Stat.ControlFlow(expressions, loc), AST.Stat.Yield)
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
	__index = AST.Stat.ControlFlow,
})



AST.Stat.Break = {}
AST.Stat.Break.__index = AST.Stat.Break
AST.Stat.Break.__name = "Break"

function AST.Stat.Break.new(expressions, level, loc)
	local self = AST.Stat.ControlFlow(expressions, loc)
	self.level = level or 1
	return setmetatable(self, AST.Stat.Break)
end

function AST.Stat.Break:debug(indent)
	return debugValue(indent, self.__name, {level = self.level},
		{expressions = self.expressions.expressions})
end

function AST.Stat.Break:__tostring()
	local expressions = {}
	for _, expr in ipairs(self.expressions) do
		table.insert(expressions, tostring(expr))
	end
	return ("break "):rep(self.level)..table.concat(expressions, ", ")
end

setmetatable(AST.Stat.Break, {
	__call = function(_, ...) return AST.Stat.Break.new(...) end,
	__index = AST.Stat.ControlFlow,
})



AST.Stat.Continue = {}
AST.Stat.Continue.__index = AST.Stat.Continue
AST.Stat.Continue.__name = "Continue"

function AST.Stat.Continue.new(loc)
	return setmetatable(AST.Stat.ControlFlow(nil, loc), AST.Stat.Continue)
end

function AST.Stat.Continue:__tostring()
	return "continue"
end

setmetatable(AST.Stat.Continue, {
	__call = function(_, ...) return AST.Stat.Continue.new(...) end,
	__index = AST.Stat.ControlFlow,
})



AST.Stat.Assignment = {}
AST.Stat.Assignment.__index = AST.Stat.Assignment
AST.Stat.Assignment.__name = "Assignment"

function AST.Stat.Assignment.new(pattern, expressions, modifiers, predef, loc)
	local self = {}
	self.pattern = pattern
	self.expressions = AST.Expr.Group(expressions, loc)
	self.modifiers = modifiers
	self.predef = predef
	self.loc = loc
	return setmetatable(self, AST.Stat.Assignment)
end

function AST.Stat.Assignment:evaluate(env)
	local values = {self.expressions:evaluate(env)}
	
	if self.modifiers.empty then
		self.pattern:assign(env, values)
	else
		self.pattern:define(env, values, self.modifiers)
	end
end

function AST.Stat.Assignment:resolve(scope)
	if self.predef then
		self.pattern:resolve(scope, not self.modifiers.empty)
		self.expressions:resolve(scope)
	else
		self.expressions:resolve(scope)
		self.pattern:resolve(scope, not self.modifiers.empty)
	end
end

function AST.Stat.Assignment:debug(indent)
	return debugValue(indent, self.__name,
		{modifiers = self.modifiers, predef = self.predef},
		{target = {self.pattern}, expressions = self.expressions.expressions})
end

function AST.Stat.Assignment:__tostring()
	return self.pattern:__tostring().." = "..self.expressions:__tostring()
end

setmetatable(AST.Stat.Assignment, {
	__call = function(_, ...) return AST.Stat.Assignment.new(...) end,
})



AST.Pattern = {}
AST.Pattern.__index = AST.Pattern
AST.Pattern.__name = "Pattern"

function AST.Pattern.new(expr)
	if expr.__name == "Variable" then
		return AST.Pattern.Variable(expr.token, expr.loc)
	elseif expr.__name == "Index" then
		return AST.Pattern.Index(expr.base, expr.expr, expr.loc)
	elseif expr.__name == "Literal" then
		return AST.Pattern.Literal(expr.literal, expr.loc)
	elseif expr.__name == "Group" then
		return AST.Pattern.Group(expr.expressions, expr.loc)
	elseif expr.__name == "List" then
		return AST.Pattern.List(expr.expressions.expressions, expr.loc)
	elseif expr.__name == "Block" then
		return AST.Pattern.Block(expr.statements, expr.loc)
	elseif expr.__name == "Call"
			and expr.expression.__name == "Index"
			and expr.expression.expr.__name == "Literal"
			and expr.expression.expr.lexeme == "..."
			and expr.expression.base.__name == "Variable" then
		return AST.Pattern.Rest(expr.expression.base.token, expr.expression.base.loc)
	else
		return AST.Pattern.Expression(expr, expr.loc)
	end
end

setmetatable(AST.Pattern, {
	__call = function(_, ...) return AST.Pattern.new(...) end,
})



AST.Pattern.Variable = {}
AST.Pattern.Variable.__index = AST.Pattern.Variable
AST.Pattern.Variable.__name = "VariablePattern"

function AST.Pattern.Variable.new(token, loc)
	local self = {}
	self.token = token
	self.loc = loc
	return setmetatable(self, AST.Pattern.Variable)
end

function AST.Pattern.Variable:evaluate(env, arguments)
	env:setAtLevel(self.token.lexeme, table.remove(arguments, 1), nil, self.level)
	return true
end

function AST.Pattern.Variable:assign(env, arguments)
	env:setAtLevel(self.token.lexeme, table.remove(arguments, 1), nil, self.level)
	return true
end

function AST.Pattern.Variable:define(env, arguments, modifiers)
	env:setAtLevel(self.token.lexeme, table.remove(arguments, 1), modifiers, 0)
	return true
end

function AST.Pattern.Variable:match(env, arguments)
	return not not table.remove(arguments, 1)
end

function AST.Pattern.Variable:resolve(scope, isDef)
	if isDef and scope[self.token.lexeme] then
		Interpreter.error("Redefinition of variable "..tostring(self.token.lexeme))
	end
	
	local origScope = scope
	if not isDef then
		if self.level then Interpreter.error("resolving already-resolved variable "..tostring(self), self.loc) end
		local level = 0
		while scope do
			if scope[self.token.lexeme] then self.level = level return end
			scope, level = scope.parent, level+1
		end
	end
	-- Always define at current level (explicit or implicit)
	if not self.level then
		origScope[self.token.lexeme] = true
		self.level = 0
	end
end

function AST.Pattern.Variable:setSelf(env, value, modifiers)
	env:setAtLevel(self.token.lexeme, value, modifiers, 0)
end

function AST.Pattern.Variable:debug(indent)
	return debugValue(indent, self.__name, {token = self.token.lexeme}, {})
end

AST.Pattern.Variable.__tostring = AST.Expr.Variable.__tostring

setmetatable(AST.Pattern.Variable, {
	__call = function(_, ...) return AST.Pattern.Variable.new(...) end,
})



AST.Pattern.Index = {}
AST.Pattern.Index.__index = AST.Pattern.Index
AST.Pattern.Index.__name = "IndexPattern"

function AST.Pattern.Index.new(base, expr, loc)
	local self = {}
	self.base = base
	self.expr = expr
	self.loc = loc
	return setmetatable(self, AST.Pattern.Index)
end

function AST.Pattern.Index:evaluate(env, arguments)
	local arg = table.remove(arguments, 1); -- require ';' because next line starts with '('
	(self.base and self.base:evaluate(env) or env):setAtLevel(ref(self.expr, env), arg, nil, 0)
	return true
end

function AST.Pattern.Index:assign(env, arguments)
	local arg = table.remove(arguments, 1); -- require ';' because next line starts with '('
	(self.base and self.base:evaluate(env) or env):setAtLevel(ref(self.expr, env), arg, nil, self.level)
	return true
end

function AST.Pattern.Index:define(env, arguments, modifiers)
	Interpreter.error("index is not a valid definition target", self.loc)
	return false
end

function AST.Pattern.Index:match(env, arguments)
	-- TODO: implement index matching
	return false
end

function AST.Pattern.Index:setSelf(env, value, modifiers)
	(self.base and self.base:evaluate(env) or env):setAtLevel(ref(self.expr, env), value, modifiers, 0)
end

function AST.Pattern.Index:resolve(scope, isDef)
	if isDef then
		Interpreter.error("index is not a valid definition target", self.loc)
		-- TODO: should remove the next line? (should allow index definition in function parameters)
		if self.expr.__name ~= "Variable" then self.expr:resolve(scope) end
	else
		AST.Expr.Index.resolve(self, scope)
	end
end

function AST.Pattern.Index:debug(indent)
	return debugValue(indent, self.__name, {}, {base = {self.base}, expr = {self.expr}})
end

function AST.Pattern.Index:__tostring()
	return tostring(self.base or "").."."..tostring(self.expr)
end

setmetatable(AST.Pattern.Index, {
	__call = function(_, ...) return AST.Pattern.Index.new(...) end,
})



AST.Pattern.Literal = {}
AST.Pattern.Literal.__index = AST.Pattern.Literal
AST.Pattern.Literal.__name = "LiteralPattern"

function AST.Pattern.Literal.new(literal, loc)
	local self = {}
	self.literal = literal
	self.loc = loc
	return setmetatable(self, AST.Pattern.Literal)
end

function AST.Pattern.Literal:evaluate(env, arguments)
	env:setAtLevel(self.literal, table.remove(arguments, 1), nil, 0)
	return true
end

function AST.Pattern.Literal:assign(env, arguments)
	env:setAtLevel(self.literal, table.remove(arguments, 1), nil, self.level)
	return true
end

function AST.Pattern.Literal:define(env, arguments, modifiers)
	env:setAtLevel(self.literal, table.remove(arguments, 1), modifiers, 0)
	return true
end

function AST.Pattern.Literal:match(env, arguments)
	local value = table.remove(arguments, 1)
	return value and value.__name == "Literal" and value.literal == self.literal
end

function AST.Pattern.Literal:resolve(scope, isDef)
	if isDef and scope[self.literal] then
		Interpreter.error("Redefinition of variable "..tostring(self.literal))
	end
	scope[self.literal] = true
end

function AST.Pattern.Literal:setSelf(env, value, modifiers)
	env:setAtLevel(self.literal, value, modifiers, 0)
end

function AST.Pattern.Literal:debug(indent)
	return debugValue(indent, self.__name, {literal = self.literal}, {})
end

AST.Pattern.Literal.__tostring = AST.Expr.Literal.__tostring

setmetatable(AST.Pattern.Literal, {
	__call = function(_, ...) return AST.Pattern.Literal.new(...) end,
})



AST.Pattern.Group = {}
AST.Pattern.Group.__index = AST.Pattern.Group
AST.Pattern.Group.__name = "GroupPattern"

function AST.Pattern.Group.new(patterns, loc)
	local self = {}
	self.patterns = {}
	for i, pattern in ipairs(patterns) do
		self.patterns[i] = AST.Pattern(pattern)
	end
	self.loc = loc
	return setmetatable(self, AST.Pattern.Group)
end

function AST.Pattern.Group:evaluate(env, arguments)
	for _, pattern in ipairs(self.patterns) do
		if not pattern:evaluate(env, arguments) then return false end
	end
	return true
end

function AST.Pattern.Group:assign(env, arguments)
	for _, pattern in ipairs(self.patterns) do
		if not pattern:assign(env, arguments) then return false end
	end
	return true
end

function AST.Pattern.Group:define(env, arguments, modifiers)
	for _, pattern in ipairs(self.patterns) do
		if not pattern:define(env, arguments, modifiers) then return false end
	end
	return true
end

function AST.Pattern.Group:match(env, arguments)
	for _, pattern in ipairs(self.patterns) do
		if not pattern:match(env, arguments) then return false end
	end
	return true
end

function AST.Pattern.Group:resolve(scope, isDef)
	for _, pattern in ipairs(self.patterns) do
		pattern:resolve(scope, isDef)
	end
end

function AST.Pattern.Group:setSelf(env, value, modifiers)
	for i, pattern in ipairs(self.patterns) do
		pattern:setSelf(env, value[i], modifiers)
	end
end

function AST.Pattern.Group:debug(indent)
	return debugValue(indent, self.__name, {}, {patterns = self.patterns})
end

function AST.Pattern.Group:__tostring()
	local patterns = {}
	for _, expr in ipairs(self.patterns) do
		table.insert(patterns, tostring(expr))
	end
	return table.concat(patterns, ", ")
end

setmetatable(AST.Pattern.Group, {
	__call = function(_, ...) return AST.Pattern.Group.new(...) end,
})



AST.Pattern.List = {}
AST.Pattern.List.__index = AST.Pattern.List
AST.Pattern.List.__name = "ListPattern"

function AST.Pattern.List.new(patterns, loc)
	local self = {}
	self.patterns = {}
	for i, pattern in ipairs(patterns) do
		self.patterns[i] = AST.Pattern(pattern)
	end
	self.loc = loc
	return setmetatable(self, AST.Pattern.List)
end

function AST.Pattern.List:evaluate(env, arguments)
	local arg = table.remove(arguments, 1)
	if not arg then return end
	local values = {}
	for _, value in ipairs(arg.environment.env) do
		table.insert(values, value.value)
	end
	for _, pattern in ipairs(self.patterns) do
		if not pattern:evaluate(env, values) then return false end
	end
	return true
end

function AST.Pattern.List:assign(env, arguments)
	local arg = table.remove(arguments, 1)
	if not arg then return end
	local values = {}
	for _, value in ipairs(arg.environment.env) do
		table.insert(values, value.value)
	end
	for _, pattern in ipairs(self.patterns) do
		if not pattern:assign(env, values) then return false end
	end
	return true
end

function AST.Pattern.List:define(env, arguments, modifiers)
	local arg = table.remove(arguments, 1)
	if not arg then return end
	local values = {}
	for _, value in ipairs(arg.environment.env) do
		table.insert(values, value.value)
	end
	for _, pattern in ipairs(self.patterns) do
		if not pattern:define(env, values, modifiers) then return false end
	end
	return true
end

function AST.Pattern.List:match(env, arguments)
	local arg = table.remove(arguments, 1)
	if not arg or arg.__name ~= "List" then return false end
	local values = {}
	for _, value in ipairs(arg.environment.env) do
		table.insert(values, value.value)
	end
	for _, pattern in ipairs(self.patterns) do
		if not pattern:match(env, values) then return false end
	end
	return true
end

function AST.Pattern.List:resolve(scope, isDef)
	for _, pattern in ipairs(self.patterns) do
		pattern:resolve(scope, isDef)
	end
end

function AST.Pattern.List:debug(indent)
	return debugValue(indent, self.__name, {}, {patterns = self.patterns})
end

function AST.Pattern.Group:__tostring()
	local patterns = {}
	for _, expr in ipairs(self.patterns) do
		table.insert(patterns, tostring(expr))
	end
	return "["..table.concat(patterns, ", ").."]"
end

setmetatable(AST.Pattern.List, {
	__call = function(_, ...) return AST.Pattern.List.new(...) end,
})



AST.Pattern.Block = {}
AST.Pattern.Block.__index = AST.Pattern.Block
AST.Pattern.Block.__name = "BlockPattern"

function AST.Pattern.Block.new(patterns, loc)
	local self = {}
	self.patterns = {}
	for i, pattern in ipairs(patterns) do
		self.patterns[i] = AST.Pattern(pattern)
		if not self.patterns[i] then return nil end
		if self.patterns[i].__name ~= "VariablePattern" then
			-- TODO: check if this is correct
			return nil
			-- Interpreter.error("invalid pattern", self.patterns[i].loc)
		end
	end
	self.loc = loc
	return setmetatable(self, AST.Pattern.Block)
end

function AST.Pattern.Block:evaluate(env, arguments)
	local arg = table.remove(arguments, 1)
	for i, pattern in ipairs(self.patterns) do
		if not pattern:evaluate(env, {arg:get(pattern.token.lexeme)}) then return false end
	end
	return true
end

function AST.Pattern.Block:assign(env, arguments)
	local arg = table.remove(arguments, 1)
	for i, pattern in ipairs(self.patterns) do
		if not pattern:assign(env, {arg:get(pattern.token.lexeme)}) then return false end
	end
	return true
end

function AST.Pattern.Block:define(env, arguments, modifiers)
	local arg = table.remove(arguments, 1)
	for i, pattern in ipairs(self.patterns) do
		if not pattern:define(env, {arg:get(pattern.token.lexeme)}, modifiers) then return false end
	end
	return true
end

function AST.Pattern.Block:match(env, arguments)
	local arg = table.remove(arguments, 1)
	for i, pattern in ipairs(self.patterns) do
		if not pattern:match(env, {arg:get(pattern.token.lexeme)}) then return false end
	end
	return true
end

function AST.Pattern.Block:resolve(scope, isDef)
	for _, pattern in ipairs(self.patterns) do
		pattern:resolve(scope, isDef)
	end
end

function AST.Pattern.Block:debug(indent)
	return debugValue(indent, self.__name, {}, {patterns = self.patterns})
end

function AST.Pattern.Group:__tostring()
	local patterns = {}
	for _, expr in ipairs(self.patterns) do
		table.insert(patterns, tostring(expr))
	end
	return "("..table.concat(patterns, ", ")..")"
end

setmetatable(AST.Pattern.Block, {
	__call = function(_, ...) return AST.Pattern.Block.new(...) end,
})



AST.Pattern.Rest = {}
AST.Pattern.Rest.__index = AST.Pattern.Rest
AST.Pattern.Rest.__name = "RestPattern"

function AST.Pattern.Rest.new(token, loc)
	local self = {}
	self.token = token
	self.loc = loc
	return setmetatable(self, AST.Pattern.Rest)
end

function AST.Pattern.Rest:evaluate(env, arguments)
	local list = stdlib.List()
	while #arguments > 0 do list:push(table.remove(arguments, 1)) end
	env:setAtLevel(self.token.lexeme, list, nil, 0)
	return true
end

function AST.Pattern.Rest:assign(env, arguments)
	local list = stdlib.List()
	while #arguments > 0 do list:push(table.remove(arguments, 1)) end
	env:setAtLevel(self.token.lexeme, list, nil, 0)
	return true
end

function AST.Pattern.Rest:define(env, arguments, modifiers)
	local list = stdlib.List()
	while #arguments > 0 do list:push(table.remove(arguments, 1)) end
	env:setAtLevel(self.token.lexeme, list, modifiers, 0)
	return true
end

function AST.Pattern.Rest:match(env, arguments)
	return true
end

function AST.Pattern.Rest:resolve(scope)
	scope[self.token.lexeme] = true
end

function AST.Pattern.Rest:debug(indent)
	return debugValue(indent, self.__name, {token = self.token}, {})
end

function AST.Pattern.Rest:__tostring()
	return "..."..self.token.lexeme
end

setmetatable(AST.Pattern.Rest, {
	__call = function(_, ...) return AST.Pattern.Rest.new(...) end,
})



AST.Pattern.Expression = {}
AST.Pattern.Expression.__index = AST.Pattern.Expression
AST.Pattern.Expression.__name = "ExpressionPattern"

function AST.Pattern.Expression.new(expression, loc)
	local self = {}
	self.expression = expression
	self.loc = loc
	return setmetatable(self, AST.Pattern.Expression)
end

function AST.Pattern.Expression:evaluate(env, arguments)
	env:setAtLevel(self.expression:evaluate(env), table.remove(arguments, 1), nil, 0)
	return true
end

function AST.Pattern.Expression:assign(env, arguments)
	env:setAtLevel(self.expression:evaluate(env), table.remove(arguments, 1), nil, 0)
	return true
end

function AST.Pattern.Expression:define(env, arguments, modifiers)
	env:setAtLevel(self.expression:evaluate(env), table.remove(arguments, 1), modifiers, 0)
	return true
end

function AST.Pattern.Expression:match(env, arguments)
	-- TODO: match on expressions?
	return true
end

function AST.Pattern.Expression:resolve(scope, isDef)
	self.expression:resolve(scope)
end

function AST.Pattern.Expression:debug(indent)
	return self.expression:debug(indent)
end

function AST.Pattern.Expression:__tostring()
	return tostring(self.expression)
end

setmetatable(AST.Pattern.Expression, {
	__call = function(_, ...) return AST.Pattern.Expression.new(...) end,
})



return AST
