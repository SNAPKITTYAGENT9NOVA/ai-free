"""Wolfram Parser: tokens → AST.

Wolfram is a symbolic mathematics language. This parser handles:
  - Numbers (integer, float, scientific notation)
  - Symbols (variables, functions)
  - Operators (arithmetic, comparison, logical)
  - Function calls
  - Lists and matrix notation
  - Proper operator precedence

The parser builds a full AST representing Wolfram expressions,
with support for nested expressions and function calls.
"""

from typing import List, Optional
from src.frontends.wolfram.wolfram_lexer import WolframLexer, TokenType
from .base_parser import (
    Parser, ParseError, Program, ASTNode, Literal, Identifier,
    BinaryOp, UnaryOp, Call, Index, SourceLocation
)


# ============================================================================
# Wolfram-specific AST Nodes
# ============================================================================

class WolframExpr(ASTNode):
    """Base class for Wolfram expressions."""
    pass


class WolframLiteral(WolframExpr, Literal):
    """Wolfram numeric or string literal."""
    pass


class WolframSymbol(WolframExpr, Identifier):
    """Wolfram symbol (variable or function name)."""
    pass


class WolframFunctionCall(WolframExpr, Call):
    """Wolfram function call: f[x, y, z] or f(x, y, z)."""
    pass


class WolframList(WolframExpr):
    """Wolfram list: {a, b, c, ...}."""
    def __init__(self, elements: List[WolframExpr]):
        super().__init__()
        self.elements = elements


class WolframMatrix(WolframExpr):
    """Wolfram matrix: {{a, b}, {c, d}}."""
    def __init__(self, rows: List[WolframList]):
        super().__init__()
        self.rows = rows


class WolframProgram(Program):
    """Wolfram program: sequence of expressions."""
    def __init__(self, expressions: List[WolframExpr]):
        super().__init__(items=expressions)
        self.expressions = expressions


# ============================================================================
# Wolfram Parser
# ============================================================================

class WolframParser(Parser[WolframProgram]):
    """Wolfram parser: tokens → AST with operator precedence."""

    def parse(self) -> WolframProgram:
        """Parse Wolfram program: sequence of expressions."""
        expressions = []
        while self.current() and self.current().type != TokenType.EOF:
            expr = self.parse_expression()
            if expr:
                expressions.append(expr)
            # Skip semicolons and commas at top level
            if self.match(TokenType.SEMICOLON, TokenType.COMMA):
                self.advance()

        program = WolframProgram(expressions=expressions)
        program.set_location(1, 0, "wolfram_program")
        return program

    # ========================================================================
    # Expression Parsing (Precedence Climbing)
    # ========================================================================

    def parse_expression(self) -> Optional[WolframExpr]:
        """Parse expression (entry point)."""
        if not self.current() or self.current().type == TokenType.EOF:
            return None
        return self.parse_logical_or()

    def parse_logical_or(self) -> WolframExpr:
        """Parse logical OR: expr || expr."""
        left = self.parse_logical_and()
        while self.match(TokenType.OR):
            op_token = self.current()
            self.advance()
            right = self.parse_logical_and()
            left = BinaryOp(op="||", left=left, right=right)
            left.set_location(op_token.line, op_token.col, "||")
        return left

    def parse_logical_and(self) -> WolframExpr:
        """Parse logical AND: expr && expr."""
        left = self.parse_comparison()
        while self.match(TokenType.AND):
            op_token = self.current()
            self.advance()
            right = self.parse_comparison()
            left = BinaryOp(op="&&", left=left, right=right)
            left.set_location(op_token.line, op_token.col, "&&")
        return left

    def parse_comparison(self) -> WolframExpr:
        """Parse comparison: ==, !=, <, <=, >, >=."""
        left = self.parse_additive()
        while self.match(TokenType.EQ, TokenType.NEQU, TokenType.LT,
                          TokenType.LE, TokenType.GT, TokenType.GE):
            op_token = self.current()
            op = op_token.value
            self.advance()
            right = self.parse_additive()
            left = BinaryOp(op=op, left=left, right=right)
            left.set_location(op_token.line, op_token.col, op)
        return left

    def parse_additive(self) -> WolframExpr:
        """Parse addition/subtraction: +, -."""
        left = self.parse_multiplicative()
        while self.match(TokenType.PLUS, TokenType.MINUS):
            op_token = self.current()
            op = op_token.value
            self.advance()
            right = self.parse_multiplicative()
            left = BinaryOp(op=op, left=left, right=right)
            left.set_location(op_token.line, op_token.col, op)
        return left

    def parse_multiplicative(self) -> WolframExpr:
        """Parse multiplication/division: *, /."""
        left = self.parse_power()
        while self.match(TokenType.STAR, TokenType.SLASH):
            op_token = self.current()
            op = op_token.value
            self.advance()
            right = self.parse_power()
            left = BinaryOp(op=op, left=left, right=right)
            left.set_location(op_token.line, op_token.col, op)
        return left

    def parse_power(self) -> WolframExpr:
        """Parse power: expr ^ expr (right-associative)."""
        left = self.parse_unary()
        if self.match(TokenType.POWER):
            op_token = self.current()
            self.advance()
            right = self.parse_power()  # Right-associative
            left = BinaryOp(op="^", left=left, right=right)
            left.set_location(op_token.line, op_token.col, "^")
        return left

    def parse_unary(self) -> WolframExpr:
        """Parse unary operations: -, Not."""
        if self.match(TokenType.MINUS):
            op_token = self.current()
            self.advance()
            operand = self.parse_unary()
            expr = UnaryOp(op="-", operand=operand)
            expr.set_location(op_token.line, op_token.col, "-")
            return expr
        elif self.match(TokenType.NOT):
            op_token = self.current()
            self.advance()
            operand = self.parse_unary()
            expr = UnaryOp(op="!", operand=operand)
            expr.set_location(op_token.line, op_token.col, "!")
            return expr
        return self.parse_postfix()

    def parse_postfix(self) -> WolframExpr:
        """Parse postfix operations: function calls f[...], indexing."""
        expr = self.parse_primary()
        while True:
            if self.match(TokenType.LBRACKET):
                # Function call: f[x, y, z]
                bracket_token = self.current()
                self.advance()
                args = []
                while not self.match(TokenType.RBRACKET):
                    args.append(self.parse_expression())
                    if self.match(TokenType.COMMA):
                        self.advance()
                self.expect(TokenType.RBRACKET)

                if isinstance(expr, WolframSymbol):
                    expr = WolframFunctionCall(name=expr.name, args=args)
                    expr.set_location(bracket_token.line, bracket_token.col, "[]")
                elif isinstance(expr, Identifier):
                    expr = WolframFunctionCall(name=expr.name, args=args)
                    expr.set_location(bracket_token.line, bracket_token.col, "[]")

            elif self.match(TokenType.LPAREN):
                # Function call with parentheses: f(x, y, z)
                paren_token = self.current()
                self.advance()
                args = []
                while not self.match(TokenType.RPAREN):
                    args.append(self.parse_expression())
                    if self.match(TokenType.COMMA):
                        self.advance()
                self.expect(TokenType.RPAREN)

                if isinstance(expr, (WolframSymbol, Identifier)):
                    name = expr.name if isinstance(expr, (WolframSymbol, Identifier)) else str(expr)
                    expr = WolframFunctionCall(name=name, args=args)
                    expr.set_location(paren_token.line, paren_token.col, "()")

            else:
                break
        return expr

    def parse_primary(self) -> WolframExpr:
        """Parse primary expressions: literals, symbols, lists, parenthesized expressions."""
        if not self.current():
            self.error("Unexpected end of input")

        if self.match(TokenType.NUMBER):
            num_token = self.current()
            try:
                if '.' in num_token.value or 'e' in num_token.value.lower():
                    value = float(num_token.value)
                    type_hint = "float"
                else:
                    value = int(num_token.value)
                    type_hint = "integer"
            except ValueError:
                value = float('nan')
                type_hint = "number"
            self.advance()
            expr = WolframLiteral(value=value, type_hint=type_hint)
            expr.set_location(num_token.line, num_token.col, num_token.value)
            return expr

        elif self.match(TokenType.STRING):
            str_token = self.current()
            value = str_token.value
            self.advance()
            expr = WolframLiteral(value=value, type_hint="string")
            expr.set_location(str_token.line, str_token.col, f'"{value}"')
            return expr

        elif self.match(TokenType.SYMBOL, TokenType.FUNCTION):
            sym_token = self.current()
            name = sym_token.value
            self.advance()
            expr = WolframSymbol(name=name)
            expr.set_location(sym_token.line, sym_token.col, name)
            return expr

        elif self.match(TokenType.LBRACE):
            # List or matrix: { ... }
            return self.parse_list()

        elif self.match(TokenType.LPAREN):
            # Parenthesized expression
            paren_token = self.current()
            self.advance()
            expr = self.parse_expression()
            self.expect(TokenType.RPAREN)
            expr.set_location(paren_token.line, paren_token.col, "()")
            return expr

        else:
            self.error(f"Unexpected token: {self.current()}")

    def parse_list(self) -> WolframList:
        """Parse list or matrix: { elem1, elem2, ... }."""
        brace_token = self.expect(TokenType.LBRACE)
        elements = []

        while not self.match(TokenType.RBRACE):
            # Check if this might be a matrix (nested list)
            if self.match(TokenType.LBRACE):
                # Nested list - parse as element
                elements.append(self.parse_list())
            else:
                # Regular element
                expr = self.parse_expression()
                if expr:
                    elements.append(expr)

            if self.match(TokenType.COMMA):
                self.advance()

        self.expect(TokenType.RBRACE)

        # Check if this is a matrix (all elements are lists)
        is_matrix = all(isinstance(e, WolframList) for e in elements)
        if is_matrix and len(elements) > 0:
            matrix = WolframMatrix(rows=elements)
            matrix.set_location(brace_token.line, brace_token.col, "{}")
            return matrix
        else:
            list_expr = WolframList(elements=elements)
            list_expr.set_location(brace_token.line, brace_token.col, "{}")
            return list_expr


def parse_wolfram(source: str) -> WolframProgram:
    """Parse Wolfram source code → AST with source locations."""
    lexer = WolframLexer(source)
    tokens = lexer.tokenize()
    parser = WolframParser(tokens)
    return parser.parse()
