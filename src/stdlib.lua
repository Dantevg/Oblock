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
		print(env:get("values"):spread())
		return nil
	end}
)

return function(environment)
	environment:set("clock", fnClock:evaluate(environment))
	environment:set("print", fnPrint:evaluate(environment))
end
