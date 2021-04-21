local AST = require "AST"

local fnClock = AST.Expr.Function(
	AST.Expr.Group {},
	AST.Expr.Literal.Number(os.clock())
)

local fnPrint = AST.Expr.Function(
	AST.Expr.Group {AST.Expr.Variable(nil, AST.Expr.Literal.String("str"))},
	{evaluate = function(_, env)
		print(env:get("str"))
		return nil
	end}
)

local globalBlock = AST.Expr.Block {
	AST.Expr.Assignment(
		AST.Expr.Variable(nil, AST.Expr.Literal.String("x")),
		{evaluate = function() return 10 end}
	)
}

local function prepareEnvironment(environment)
	environment:set("clock", fnClock:evaluate(environment))
	environment:set("print", fnPrint:evaluate(environment))
	environment:set("block", globalBlock:evaluate(environment))
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