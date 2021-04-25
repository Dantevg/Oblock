local AST = require "AST"

local fnClock = AST.Expr.Function(
	AST.Expr.Group {},
	{evaluate = function()
		return os.clock()
	end}
)

local fnPrint = AST.Expr.Function(
	AST.Expr.Group {AST.Expr.Unary({type = "dot dot dot"}, AST.Expr.Variable(nil, AST.Expr.Literal("values", "values")))},
	{evaluate = function(_, env)
		local values = env:get("values").environment.environment
		for i, value in ipairs(values) do values[i] = value.value end
		print(table.unpack(values))
		return nil
	end}
)

local function prepareEnvironment(environment)
	environment:set("clock", fnClock:evaluate(environment))
	environment:set("print", fnPrint:evaluate(environment))
end

local Interpreter = {}
Interpreter.__index = Interpreter

function Interpreter.new(program)
	local self = {}
	self.program = program
	self.environment = AST.Environment()
	prepareEnvironment(self.environment)
	return setmetatable(self, Interpreter)
end

function Interpreter:interpret()
	return self.program:evaluate(self.environment)
end

return setmetatable(Interpreter, {
	__call = function(_, ...) return Interpreter.new(...) end,
})